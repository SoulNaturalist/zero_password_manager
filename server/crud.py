import httpx
import re
from typing import Optional, List
from sqlalchemy.orm import Session
from fastapi import BackgroundTasks, HTTPException, status
from . import models, schemas, auth
from .config import settings

_TELEGRAM_ESCAPE = str.maketrans({
    "_": r"\_", "*": r"\*", "[": r"\[", "]": r"\]",
    "(": r"\(", ")": r"\)", "~": r"\~", "`": r"\`",
    ">": r"\>", "#": r"\#", "+": r"\+", "-": r"\-",
    "=": r"\=", "|": r"\|", "{": r"\{", "}": r"\}",
    ".": r"\.", "!": r"\!",
})


def _escape_telegram(value: str) -> str:
    """Escape user-supplied text for Telegram MarkdownV2 to prevent injection."""
    return str(value).translate(_TELEGRAM_ESCAPE)


async def send_telegram_message(chat_id: str, text: str):
    """Sends a security alert to Telegram (background task)."""
    if not settings.TELEGRAM_BOT_TOKEN or not chat_id:
        return
    url = f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/sendMessage"
    async with httpx.AsyncClient(timeout=5) as client:
        try:
            await client.post(url, json={
                "chat_id": chat_id,
                "text": text,
                "parse_mode": "MarkdownV2",
            })
        except Exception as e:
            import logging
            logging.error(f"Telegram notification failed: {e}")

def audit_event(db: Session, user_id: int, event: str, meta: dict = None, ip: str = None, background_tasks: BackgroundTasks = None):
    """Records audit trail and triggers async Telegram alerts for the user."""
    # Ensure user exists for notification
    user = db.query(models.User).filter(models.User.id == user_id).first()
    
    db_audit = models.Audit(user_id=user_id, event=event, meta=meta or {}, ip_address=ip)
    db.add(db_audit)
    db.commit()

    # Trigger Telegram Alert for critical events if user has chat_id
    if user and user.telegram_chat_id and event in settings.CRITICAL_EVENTS and background_tasks:
        # Filter meta to only keep safe fields
        safe_meta = {}
        if meta:
            if "site_hash" in meta:
                 safe_meta["site_hash"] = meta["site_hash"]
        
        # Escape all user-controlled fields before embedding in MarkdownV2 message
        # to prevent Telegram Markdown injection.
        safe_event = _escape_telegram(event)
        safe_uid = _escape_telegram(str(user_id))
        safe_ip = _escape_telegram(str(ip)) if ip else ""
        safe_meta_str = _escape_telegram(str(safe_meta)) if safe_meta else ""

        ip_line = f"IP: {safe_ip}\n" if safe_ip else ""
        meta_line = f"Details: {safe_meta_str}\n" if safe_meta_str else ""

        message = (
            "🚨 *Security Alert*\n"
            f"*Event*: `{safe_event}`\n"
            f"*User ID*: `{safe_uid}`\n"
            f"{ip_line}{meta_line}"
        )
        background_tasks.add_task(send_telegram_message, user.telegram_chat_id, message)


def validate_password_strength(password: str) -> bool:
    """Hardened password policy: 14+ chars, upper, lower, digit, special symbol"""
    if len(password) < 14:
        return False
    if not re.search(r'[A-Z]', password):
        return False
    if not re.search(r'[a-z]', password):
        return False
    if not re.search(r'\d', password):
        return False
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        return False
    return True


def create_user(db: Session, user: schemas.UserCreate, background_tasks: BackgroundTasks = None):
    if not validate_password_strength(user.password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password too weak. Minimum 14 characters, including uppercase, lowercase, digits, and special symbols."
        )
    salt = auth.generate_salt()
    hashed_password = auth.get_password_hash(user.password)
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


def create_password(db: Session, password: schemas.PasswordCreate, user_id: int, background_tasks: BackgroundTasks = None):
    # ... (folder ownership check)
    if password.folder_id is not None:
        folder = db.query(models.Folder).filter(
            models.Folder.id == password.folder_id,
            models.Folder.user_id == user_id
        ).first()
        if not folder:
            raise HTTPException(status_code=404, detail="Folder not found")

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


def update_password(db: Session, password_id: int, password: schemas.PasswordUpdate, user_id: int, background_tasks: BackgroundTasks = None):
    # ...
    db_password = db.query(models.Password).filter(
        models.Password.id == password_id,
        models.Password.user_id == user_id
    ).first()
    if not db_password:
        raise HTTPException(status_code=404, detail="Password not found")

    if password.folder_id is not None:
        folder = db.query(models.Folder).filter(
            models.Folder.id == password.folder_id,
            models.Folder.user_id == user_id
        ).first()
        if not folder:
            raise HTTPException(status_code=404, detail="Folder not found")

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


def delete_password(db: Session, password_id: int, user_id: int, background_tasks: BackgroundTasks = None):
    db_password = db.query(models.Password).filter(
        models.Password.id == password_id,
        models.Password.user_id == user_id
    ).first()
    if not db_password:
        raise HTTPException(status_code=404, detail="Password not found")

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
        raise HTTPException(status_code=404, detail="Folder not found")

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
        raise HTTPException(status_code=404, detail="Folder not found")

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
        raise HTTPException(status_code=404, detail="Folder not found")

    audit_event(db, user_id, "vault_read", meta={"folder_id": folder_id}, background_tasks=background_tasks)
    return db.query(models.Password).filter(
        models.Password.folder_id == folder_id,
        models.Password.user_id == user_id
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
    return db.query(models.WebAuthnChallenge).filter(
        models.WebAuthnChallenge.challenge == challenge,
        models.WebAuthnChallenge.expires_at > datetime.now(timezone.utc)
    ).first()


def delete_challenge(db: Session, challenge: str):
    db.query(models.WebAuthnChallenge).filter(
        models.WebAuthnChallenge.challenge == challenge
    ).delete()
    db.commit()


def create_webauthn_credential(db: Session, user_id: int, credential_id: str, public_key: bytes, sign_count: int, transports: Optional[List[str]]):
    db_cred = models.WebAuthnCredential(
        user_id=user_id,
        credential_id=credential_id,
        public_key=public_key,
        sign_count=sign_count,
        transports=transports
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


# ── JWT Revocation / Token Blacklist ──────────────────────────────────────────

def blacklist_token(db: Session, jti: str, expires_at) -> None:
    """Add a token's jti to the blacklist so it can no longer be used.

    Performs lazy cleanup of expired rows on each call to prevent unbounded
    growth — no separate cron job required.
    """
    from datetime import datetime, timezone

    # Prune expired entries first (lazy GC)
    db.query(models.TokenBlacklist).filter(
        models.TokenBlacklist.expires_at < datetime.now(timezone.utc)
    ).delete(synchronize_session=False)

    # Only insert if not already present (idempotent)
    existing = db.query(models.TokenBlacklist).filter(
        models.TokenBlacklist.jti == jti
    ).first()
    if not existing:
        db.add(models.TokenBlacklist(jti=jti, expires_at=expires_at))

    db.commit()


def is_token_blacklisted(db: Session, jti: str) -> bool:
    """Return True if the given jti has been revoked."""
    return (
        db.query(models.TokenBlacklist)
        .filter(models.TokenBlacklist.jti == jti)
        .first()
    ) is not None
