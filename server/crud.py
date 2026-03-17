from datetime import datetime, timezone, timedelta
from urllib.parse import urlparse
import httpx
import secrets
import re
import html
import ipaddress
from typing import Optional, List
from sqlalchemy.orm import Session
from fastapi import BackgroundTasks, HTTPException, status
from . import models, schemas
from .auth import service as auth
from .config import settings
from .database import SessionLocal

async def send_telegram_message(chat_id: str, text: str):
    """Sends a security alert to Telegram (background task)."""
    if not settings.TELEGRAM_BOT_TOKEN or not chat_id:
        import logging
        logging.warning(f"Telegram skip: BOT_TOKEN={bool(settings.TELEGRAM_BOT_TOKEN)}, chat_id={bool(chat_id)}")
        return
    url = f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/sendMessage"
    async with httpx.AsyncClient(timeout=5) as client:
        try:
            resp = await client.post(url, json={
                "chat_id": chat_id,
                "text": text
            })
            if resp.status_code != 200:
                import logging
                logging.error(f"Telegram API error: {resp.status_code} - [token hidden]")
        except Exception as e:
            import logging
            logging.error(f"Telegram notification failed: {e}")

async def get_ip_location(ip: str) -> str:
    """
    Resolves IP to City, Country using ip-api.com. Defaults to 'Локальная сеть'.

    CWE-918 (SSRF) mitigations:
      - Strict IP validation: private, loopback, multicast, reserved → blocked
      - follow_redirects=False — prevents DNS-rebinding / open-redirect attacks
      - Response size capped at 1 KB — prevents DoS via large responses
      - Output sanitized with html.escape before use in messages
    """
    if not ip or ip in ("N/A", "0.0.0.0", "127.0.0.1", "localhost", "::1"):
        return "Локальная сеть"

    try:
        addr = ipaddress.ip_address(ip)
        if (addr.is_private or addr.is_loopback or
                addr.is_multicast or addr.is_reserved or addr.is_unspecified):
            return "Локальная сеть"
    except Exception:
        return "Локальная сеть"

    # ip-api.com free tier does not support HTTPS; domain is hardcoded (no
    # user input in URL) and redirects are disabled to prevent SSRF via redirect.
    domain = "ip-api.com"
    url = f"http://{domain}/json/{ip}?fields=status,message,country,city"

    async with httpx.AsyncClient(timeout=3, follow_redirects=False) as client:
        try:
            resp = await client.get(url)
            if len(resp.content) > 1024:
                return "Локальная сеть"
            if resp.status_code == 200:
                data = resp.json()
                if data.get("status") == "success":
                    city    = html.escape(str(data.get("city",    ""))[:100])
                    country = html.escape(str(data.get("country", ""))[:100])
                    if city or country:
                        return f"{city}, {country}".strip(", ")
        except Exception:
            pass
    return "Локальная сеть"

def _tg_escape(text: str) -> str:
    """Escape HTML special chars for Telegram messages (CWE-117: log injection)."""
    return html.escape(str(text)[:500])


async def notify_security_event(chat_id: str, event: str, user_id: int, ip: str, safe_meta: dict):
    """Async wrapper to resolve location and then send Telegram message."""
    actual_ip = ip if ip and ip != "N/A" else "0.0.0.0"
    location  = await get_ip_location(actual_ip)

    # CWE-117: all dynamic values are escaped before embedding in the message
    message = (
        f"🚨 SECURITY ALERT\n"
        f"Event: {_tg_escape(event)}\n"
        f"User ID: {int(user_id)}\n"
        f"Location: {_tg_escape(actual_ip)} ({_tg_escape(location)})"
    )
    if safe_meta:
        message += f"\nDetails: {_tg_escape(str(safe_meta))}"

    await send_telegram_message(chat_id, message)

def sanitize_meta(meta: dict, _depth: int = 0) -> dict:
    """
    Escapes strings and limits lengths in JSON metadata to prevent injection and OOM.

    CWE-776 (JSON Bomb) mitigations:
      - Maximum nesting depth: 4 levels
      - Maximum keys per level: 50
      - Maximum list length: 20 items
      - All string keys and values are html.escape()'d and length-capped
    """
    if not meta or not isinstance(meta, dict):
        return {}
    if _depth > 4:
        return {"_truncated": True}

    sanitized: dict = {}
    for key, value in list(meta.items())[:50]:  # cap keys per level
        k = html.escape(str(key))[:100]
        if isinstance(value, bool):          # bool before int — bool is subclass of int
            sanitized[k] = value
        elif isinstance(value, (int, float)):
            sanitized[k] = value
        elif isinstance(value, str):
            sanitized[k] = html.escape(value)[:255]
        elif isinstance(value, dict):
            sanitized[k] = sanitize_meta(value, _depth + 1)
        elif isinstance(value, list):
            sanitized[k] = [
                sanitize_meta(v, _depth + 1) if isinstance(v, dict)
                else html.escape(str(v))[:255] if isinstance(v, str)
                else v
                for v in value[:20]  # cap list length
            ]
        else:
            sanitized[k] = html.escape(str(value))[:255]
    return sanitized

def save_audit_log(user_id: int, event: str, meta: dict, ip: str):
    """Background task to persist audit logs without blocking the main request."""
    try:
        with SessionLocal() as db:
            db_audit = models.Audit(
                user_id=user_id,
                event=event,
                meta=meta,
                ip_address=ip
            )
            db.add(db_audit)
            db.commit()
    except Exception as e:
        import logging
        logging.error(f"Failed to save audit log in background: {e}")

_AUDIT_DEDUP_WINDOW   = timedelta(minutes=1)
_AUDIT_DEDUP_LIMIT    = 10   # max identical event+user combinations per window


def audit_event(db: Session, user_id: int, event: str, meta: dict = None, ip: str = None, background_tasks: BackgroundTasks = None):
    """
    Records audit trail and triggers async Telegram alerts.

    CWE-362 (Race Condition / Audit Spam) mitigations:
      - Deduplication: at most _AUDIT_DEDUP_LIMIT identical events per user per
        minute.  Prevents log flooding under a brute-force attack.
      - Telegram alert only after the deduplication check, so the attacker
        cannot spam the admin's Telegram with thousands of alerts.
    """
    user      = db.query(models.User).filter(models.User.id == user_id).first()
    sanitized = sanitize_meta(meta or {})

    # ── Deduplication (CWE-362) ──────────────────────────────────────────────
    # Count identical (user_id, event) pairs within the last minute.
    recent_count = db.query(models.Audit).filter(
        models.Audit.user_id == user_id,
        models.Audit.event   == event,
        models.Audit.created_at >= datetime.now(timezone.utc) - _AUDIT_DEDUP_WINDOW,
    ).count()
    if recent_count >= _AUDIT_DEDUP_LIMIT:
        return  # Silently drop duplicate to prevent log flooding

    if background_tasks:
        background_tasks.add_task(save_audit_log, user_id, event, sanitized, ip)
    else:
        db_audit = models.Audit(
            user_id=user_id,
            event=event,
            meta=sanitized,
            ip_address=ip,
        )
        db.add(db_audit)
        db.commit()

    # ── Telegram alert for critical events ──────────────────────────────────
    if user and user.telegram_chat_id and event in settings.CRITICAL_EVENTS and background_tasks:
        safe_meta: dict = {}
        if meta and "site_hash" in meta:
            safe_meta["site_hash"] = meta["site_hash"]

        background_tasks.add_task(
            notify_security_event,
            user.telegram_chat_id,
            event,
            user_id,
            ip,
            safe_meta,
        )


def validate_password_strength(password: str) -> bool:
    """Hardened password policy: 14+ chars, upper, lower, digit, special symbol, no common passwords."""
    # Use the enhanced check from auth service if available
    return auth.is_password_strong_enhanced(password)


def get_user_by_login(db: Session, login: str):
    return db.query(models.User).filter(models.User.login == login).first()


def create_user(db: Session, user: schemas.UserCreate, background_tasks: BackgroundTasks = None):
    if not validate_password_strength(user.password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password too weak. Minimum 14 characters, including uppercase, lowercase, digits, and special symbols."
        )
    salt = auth.generate_salt()
    hashed_password = auth.hash_password(user.password)
    db_user = models.User(
        login=user.login, 
        hashed_password=hashed_password, 
        salt=salt,
        telegram_chat_id=user.telegram_chat_id
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    audit_event(db, db_user.id, "register", background_tasks=background_tasks)
    return db_user


def update_user_totp(db: Session, user_id: int, secret: str = None, enabled: bool = None):
    user = db.query(models.User).get(user_id)
    if secret is not None:
        user.totp_secret = secret
    if enabled is not None:
        user.totp_enabled = enabled
    db.commit()
    db.refresh(user)
    return user


def get_passwords(db: Session, user_id: int, background_tasks: BackgroundTasks = None):
    audit_event(db, user_id, "vault_read", background_tasks=background_tasks)
    return db.query(models.Password).filter(models.Password.user_id == user_id).all()


def search_passwords(db: Session, query: str, user_id: int, background_tasks: BackgroundTasks = None):
    """
    Search for passwords by site_hash or metadata.
    Strictly filters by user_id to prevent IDOR.

    CWE-89: % and _ are LIKE wildcards — without escaping, a query containing
    those characters would match unintended rows and could be used to enumerate
    other users' entries in a multi-tenant scenario.  We escape them explicitly
    and pass escape='\\' to SQLAlchemy so the DB treats them as literals.
    """
    audit_event(db, user_id, "vault_search", meta={"query_length": len(query)}, background_tasks=background_tasks)
    escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return db.query(models.Password).filter(
        models.Password.user_id == user_id,
        models.Password.site_hash.ilike(f"%{escaped}%", escape="\\"),
    ).all()


def create_password(db: Session, password: schemas.PasswordCreate, user_id: int, background_tasks: BackgroundTasks = None):
    if password.folder_id is not None:
        folder = db.query(models.Folder).filter(
            models.Folder.id == password.folder_id,
            models.Folder.user_id == user_id
        ).first()
        if not folder:
            # CWE-200: unified message avoids disclosing whether the folder exists
            raise HTTPException(status_code=404, detail="Resource not found or access denied")

    db_password = models.Password(
        user_id=user_id,
        folder_id=password.folder_id,
        site_hash=password.site_hash,
        encrypted_payload=password.encrypted_payload,
        notes_encrypted=password.notes_encrypted,
        encrypted_metadata=password.encrypted_metadata,
        has_2fa=password.has_2fa,
        has_seed_phrase=password.has_seed_phrase
    )
    db.add(db_password)
    db.commit()
    db.refresh(db_password)

    audit_event(db, user_id, "vault_create", meta={"site_hash": password.site_hash}, background_tasks=background_tasks)

    return db_password


def import_passwords(db: Session, data: schemas.PasswordImport, user_id: int, background_tasks: BackgroundTasks = None):
    results = []
    for item in data.items:
        db_password = models.Password(
            user_id=user_id,
            folder_id=item.folder_id,
            site_hash=item.site_hash,
            encrypted_payload=item.encrypted_payload,
            notes_encrypted=item.notes_encrypted,
            encrypted_metadata=item.encrypted_metadata,
            has_2fa=item.has_2fa,
            has_seed_phrase=item.has_seed_phrase
        )
        db.add(db_password)
        results.append(db_password)

    db.commit()
    for r in results:
        db.refresh(r)

    audit_event(db, user_id, "vault_import", meta={"count": len(results)}, background_tasks=background_tasks)
    return results


def update_password(db: Session, password_id: int, password: schemas.PasswordUpdate, user_id: int, background_tasks: BackgroundTasks = None):
    # ...
    db_password = db.query(models.Password).filter(
        models.Password.id == password_id,
        models.Password.user_id == user_id
    ).first()
    if not db_password:
        raise HTTPException(status_code=404, detail="Resource not found or access denied")

    if password.folder_id is not None:
        folder = db.query(models.Folder).filter(
            models.Folder.id == password.folder_id,
            models.Folder.user_id == user_id
        ).first()
        if not folder:
            raise HTTPException(status_code=404, detail="Resource not found or access denied")

    db_password.folder_id = password.folder_id
    db_password.site_hash = password.site_hash
    db_password.encrypted_payload = password.encrypted_payload
    db_password.notes_encrypted = password.notes_encrypted
    db_password.encrypted_metadata = password.encrypted_metadata
    db_password.has_2fa = password.has_2fa
    db_password.has_seed_phrase = password.has_seed_phrase
    db.commit()
    db.refresh(db_password)

    audit_event(db, user_id, "vault_update", meta={"site_hash": password.site_hash}, background_tasks=background_tasks)
    return db_password


def create_history(db: Session, history: schemas.HistoryCreate, user_id: int):
    db_history = models.PasswordHistory(
        user_id=user_id,
        password_id=history.password_id,
        action_type=history.action_type,
        action_details=history.action_details,
        site_url=history.site_url
    )
    db.add(db_history)
    db.commit()
    db.refresh(db_history)
    return db_history


def delete_password(db: Session, password_id: int, user_id: int, background_tasks: BackgroundTasks = None):
    db_password = db.query(models.Password).filter(
        models.Password.id == password_id,
        models.Password.user_id == user_id
    ).first()
    if not db_password:
        raise HTTPException(status_code=404, detail="Resource not found or access denied")

    audit_event(db, user_id, "vault_delete", meta={"site_hash": db_password.site_hash}, background_tasks=background_tasks)
    db.delete(db_password)
    db.commit()


# ── Folder CRUD ───────────────────────────────────────────────────────────────

def get_folders(db: Session, user_id: int):
    folders = db.query(models.Folder).filter(models.Folder.user_id == user_id).all()
    result = []
    for folder in folders:
        count = db.query(models.Password).filter(
            models.Password.folder_id == folder.id
        ).count()
        folder_dict = {
            "id": folder.id,
            "name": folder.name,
            "color": folder.color,
            "icon": folder.icon,
            "created_at": folder.created_at,
            "updated_at": folder.updated_at,
            "password_count": count,
        }
        result.append(folder_dict)
    return result


def create_folder(db: Session, folder: schemas.FolderCreate, user_id: int, background_tasks: BackgroundTasks = None):
    db_folder = models.Folder(
        user_id=user_id,
        name=folder.name,
        color=folder.color,
        icon=folder.icon,
    )
    db.add(db_folder)
    db.commit()
    db.refresh(db_folder)
    audit_event(db, user_id, "folder_create", meta={"name": folder.name}, background_tasks=background_tasks)
    return db_folder


def update_folder(db: Session, folder_id: int, folder: schemas.FolderUpdate, user_id: int, background_tasks: BackgroundTasks = None):
    db_folder = db.query(models.Folder).filter(
        models.Folder.id == folder_id,
        models.Folder.user_id == user_id
    ).first()
    if not db_folder:
        raise HTTPException(status_code=404, detail="Resource not found or access denied")

    if folder.name is not None:
        db_folder.name = folder.name
    if folder.color is not None:
        db_folder.color = folder.color
    if folder.icon is not None:
        db_folder.icon = folder.icon

    db.commit()
    db.refresh(db_folder)
    audit_event(db, user_id, "folder_update", meta={"id": folder_id}, background_tasks=background_tasks)
    return db_folder


def delete_folder(db: Session, folder_id: int, user_id: int, background_tasks: BackgroundTasks = None):
    db_folder = db.query(models.Folder).filter(
        models.Folder.id == folder_id,
        models.Folder.user_id == user_id
    ).first()
    if not db_folder:
        raise HTTPException(status_code=404, detail="Resource not found or access denied")

    # Unlink passwords from this folder (don't delete them)
    db.query(models.Password).filter(
        models.Password.folder_id == folder_id
    ).update({"folder_id": None})

    audit_event(db, user_id, "folder_delete", meta={"id": folder_id}, background_tasks=background_tasks)
    db.delete(db_folder)
    db.commit()


def get_passwords_by_folder(db: Session, folder_id: int, user_id: int, background_tasks: BackgroundTasks = None):
    # Verify folder ownership
    folder = db.query(models.Folder).filter(
        models.Folder.id == folder_id,
        models.Folder.user_id == user_id
    ).first()
    if not folder:
        raise HTTPException(status_code=404, detail="Resource not found or access denied")

    audit_event(db, user_id, "vault_read", meta={"folder_id": folder_id}, background_tasks=background_tasks)
    return db.query(models.Password).filter(
        models.Password.folder_id == folder_id,
        models.Password.user_id == user_id  # Strict user_id check (IDOR Protection)
    ).all()


# ── WebAuthn CRUD ─────────────────────────────────────────────────────────────

def create_challenge(db: Session, user_id: Optional[int], challenge: str, type: str):
    # Cleanup expired challenges first
    db.query(models.WebAuthnChallenge).filter(
        models.WebAuthnChallenge.expires_at < datetime.now(timezone.utc)
    ).delete()
    
    db_challenge = models.WebAuthnChallenge(
        user_id=user_id,
        challenge=challenge,
        type=type,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=120)
    )
    db.add(db_challenge)
    db.commit()
    db.refresh(db_challenge)
    return db_challenge


def get_challenge(db: Session, challenge: str):
    # CWE-1073: only return challenges that have NOT been used yet
    return db.query(models.WebAuthnChallenge).filter(
        models.WebAuthnChallenge.challenge  == challenge,
        models.WebAuthnChallenge.expires_at  > datetime.now(timezone.utc),
        models.WebAuthnChallenge.used       == False,  # noqa: E712
    ).first()


def consume_challenge(db: Session, challenge: str) -> bool:
    """
    Atomically mark a challenge as used.  Returns True on success, False if
    the challenge was already used (race-condition protection, CWE-1073).
    Replaces delete_challenge() — the row is kept for audit purposes.
    """
    updated = db.query(models.WebAuthnChallenge).filter(
        models.WebAuthnChallenge.challenge  == challenge,
        models.WebAuthnChallenge.used       == False,  # noqa: E712
        models.WebAuthnChallenge.expires_at  > datetime.now(timezone.utc),
    ).update(
        {"used": True, "used_at": datetime.now(timezone.utc)},
        synchronize_session=False,
    )
    db.commit()
    return updated > 0


def delete_challenge(db: Session, challenge: str):
    """Legacy: kept for callers that haven't migrated to consume_challenge()."""
    consume_challenge(db, challenge)


# CWE-434: allowlist of valid WebAuthn transport values
_VALID_TRANSPORTS   = {"usb", "nfc", "ble", "internal", "hybrid", "smart-card"}
_MAX_PUBLIC_KEY_BYTES = 2048


def create_webauthn_credential(db: Session, user_id: int, credential_id: str, public_key: bytes, sign_count: int, transports: Optional[List[str]]):
    # CWE-434: enforce size limit on the public key blob
    if len(public_key) > _MAX_PUBLIC_KEY_BYTES:
        raise HTTPException(status_code=400, detail="Public key exceeds size limit")

    # CWE-434: filter transports to the allowlist; reject unknown values silently
    clean_transports = [t for t in (transports or []) if t in _VALID_TRANSPORTS]

    db_cred = models.WebAuthnCredential(
        user_id=user_id,
        credential_id=credential_id[:256],  # cap credential_id length
        public_key=public_key,
        sign_count=sign_count,
        transports=clean_transports or None,
    )
    db.add(db_cred)
    db.commit()
    db.refresh(db_cred)
    return db_cred


def get_webauthn_credential_by_id(db: Session, credential_id: str):
    return db.query(models.WebAuthnCredential).filter(
        models.WebAuthnCredential.credential_id == credential_id
    ).first()


def update_webauthn_sign_count(db: Session, credential_id: str, new_count: int):
    db.query(models.WebAuthnCredential).filter(
        models.WebAuthnCredential.credential_id == credential_id
    ).update({"sign_count": new_count})
    db.commit()


def upsert_user_device(db: Session, user_id: int, device_id: str, device_name: str):
    db_device = db.query(models.UserDevice).filter(
        models.UserDevice.user_id == user_id,
        models.UserDevice.device_id == device_id
    ).first()
    
    if db_device:
        db_device.device_name = device_name
        db_device.last_used_at = datetime.now(timezone.utc)
        db_device.is_active = True
    else:
        db_device = models.UserDevice(
            user_id=user_id,
            device_id=device_id,
            device_name=device_name
        )
        db.add(db_device)
    
    db.commit()
    db.refresh(db_device)
    return db_device


def get_user_devices(db: Session, user_id: int):
    return db.query(models.UserDevice).filter(
        models.UserDevice.user_id == user_id,
        models.UserDevice.is_active == True
    ).all()


def revoke_device(db: Session, device_id: int, user_id: int):
    db.query(models.UserDevice).filter(
        models.UserDevice.id == device_id,
        models.UserDevice.user_id == user_id
    ).update({"is_active": False})
    db.commit()


def get_history(db: Session, user_id: int, background_tasks: BackgroundTasks = None):
    audit_event(db, user_id, "history_read", background_tasks=background_tasks)
    return db.query(models.PasswordHistory).filter(models.PasswordHistory.user_id == user_id).order_by(models.PasswordHistory.created_at.desc()).all()


def get_logs(db: Session, user_id: int):
    return db.query(models.Audit).filter(models.Audit.user_id == user_id).order_by(models.Audit.created_at.desc()).limit(100).all()
