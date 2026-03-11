import httpx
import re
from typing import Optional, List
from datetime import datetime, timedelta, timezone
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


# ── Password Rotation CRUD ────────────────────────────────────────────────────

def set_rotation_config(db: Session, password_id: int, user_id: int,
                        rotation_enabled: bool, rotation_interval_days: Optional[int]):
    pwd = db.query(models.Password).filter(
        models.Password.id == password_id,
        models.Password.user_id == user_id,
    ).first()
    if not pwd:
        raise HTTPException(status_code=404, detail="Password not found")
    pwd.rotation_enabled = rotation_enabled
    pwd.rotation_interval_days = rotation_interval_days
    db.commit()
    db.refresh(pwd)
    return pwd


def record_rotation(db: Session, password_id: int, user_id: int,
                    encrypted_payload: str,
                    notes_encrypted: Optional[str],
                    encrypted_metadata,
                    background_tasks: BackgroundTasks = None):
    pwd = db.query(models.Password).filter(
        models.Password.id == password_id,
        models.Password.user_id == user_id,
    ).first()
    if not pwd:
        raise HTTPException(status_code=404, detail="Password not found")
    pwd.encrypted_payload = encrypted_payload
    if notes_encrypted is not None:
        pwd.notes_encrypted = notes_encrypted
    if encrypted_metadata is not None:
        pwd.encrypted_metadata = encrypted_metadata
    pwd.last_rotated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(pwd)
    audit_event(db, user_id, "password_rotated", {"password_id": password_id},
                background_tasks=background_tasks)
    return pwd


def get_passwords_due_for_rotation(db: Session, user_id: int) -> List[models.Password]:
    """Return passwords with rotation enabled whose next rotation date has passed."""
    now = datetime.now(timezone.utc)
    passwords = db.query(models.Password).filter(
        models.Password.user_id == user_id,
        models.Password.rotation_enabled == True,
        models.Password.rotation_interval_days.isnot(None),
    ).all()
    due = []
    for p in passwords:
        if p.last_rotated_at is None:
            due.append(p)
        else:
            last = p.last_rotated_at
            if last.tzinfo is None:
                last = last.replace(tzinfo=timezone.utc)
            if now >= last + timedelta(days=p.rotation_interval_days):
                due.append(p)
    return due


# ── Secure Sharing CRUD ───────────────────────────────────────────────────────

def get_user_by_login(db: Session, login: str):
    return db.query(models.User).filter(models.User.login == login).first()


def create_share(db: Session, owner_id: int, data: schemas.ShareCreate,
                 background_tasks: BackgroundTasks = None) -> models.SharedPassword:
    # Resolve recipient
    recipient = get_user_by_login(db, data.recipient_login)
    if not recipient:
        raise HTTPException(status_code=404, detail="Recipient user not found")
    if recipient.id == owner_id:
        raise HTTPException(status_code=400, detail="Cannot share with yourself")

    expires_at = None
    if data.expires_in_days:
        expires_at = datetime.now(timezone.utc) + timedelta(days=data.expires_in_days)

    share = models.SharedPassword(
        owner_id=owner_id,
        recipient_id=recipient.id,
        recipient_login=data.recipient_login,
        encrypted_payload=data.encrypted_payload,
        encrypted_metadata=data.encrypted_metadata,
        label=data.label,
        status="pending",
        expires_at=expires_at,
    )
    db.add(share)
    db.commit()
    db.refresh(share)
    audit_event(db, owner_id, "share_created",
                {"recipient": data.recipient_login, "share_id": share.id},
                background_tasks=background_tasks)
    return share


def get_shares_incoming(db: Session, user_id: int) -> List[models.SharedPassword]:
    return db.query(models.SharedPassword).filter(
        models.SharedPassword.recipient_id == user_id,
        models.SharedPassword.status != "revoked",
    ).order_by(models.SharedPassword.created_at.desc()).all()


def get_shares_outgoing(db: Session, user_id: int) -> List[models.SharedPassword]:
    return db.query(models.SharedPassword).filter(
        models.SharedPassword.owner_id == user_id,
        models.SharedPassword.status != "revoked",
    ).order_by(models.SharedPassword.created_at.desc()).all()


def accept_share(db: Session, share_id: int, user_id: int,
                 background_tasks: BackgroundTasks = None) -> models.SharedPassword:
    share = db.query(models.SharedPassword).filter(
        models.SharedPassword.id == share_id,
        models.SharedPassword.recipient_id == user_id,
        models.SharedPassword.status == "pending",
    ).first()
    if not share:
        raise HTTPException(status_code=404, detail="Share not found or already processed")
    # Check expiry
    if share.expires_at:
        exp = share.expires_at
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if datetime.now(timezone.utc) > exp:
            share.status = "revoked"
            db.commit()
            raise HTTPException(status_code=410, detail="Share has expired")
    share.status = "accepted"
    db.commit()
    db.refresh(share)
    audit_event(db, user_id, "share_accepted", {"share_id": share_id},
                background_tasks=background_tasks)
    return share


def revoke_share(db: Session, share_id: int, owner_id: int,
                 background_tasks: BackgroundTasks = None):
    share = db.query(models.SharedPassword).filter(
        models.SharedPassword.id == share_id,
        models.SharedPassword.owner_id == owner_id,
    ).first()
    if not share:
        raise HTTPException(status_code=404, detail="Share not found")
    share.status = "revoked"
    db.commit()
    audit_event(db, owner_id, "share_revoked", {"share_id": share_id},
                background_tasks=background_tasks)


def get_share_detail(db: Session, share_id: int, user_id: int) -> models.SharedPassword:
    """Get full share including encrypted payload — only for recipient."""
    share = db.query(models.SharedPassword).filter(
        models.SharedPassword.id == share_id,
        models.SharedPassword.recipient_id == user_id,
        models.SharedPassword.status == "accepted",
    ).first()
    if not share:
        raise HTTPException(status_code=404, detail="Share not found or not yet accepted")
    # Check expiry
    if share.expires_at:
        exp = share.expires_at
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if datetime.now(timezone.utc) > exp:
            share.status = "revoked"
            db.commit()
            raise HTTPException(status_code=410, detail="Share has expired")
    return share


# ── Emergency Access CRUD ─────────────────────────────────────────────────────

def create_emergency_access(db: Session, grantor_id: int,
                             data: schemas.EmergencyInvite,
                             background_tasks: BackgroundTasks = None) -> models.EmergencyAccess:
    wait_days = max(1, min(data.wait_days, 30))  # clamp 1-30
    grantee = get_user_by_login(db, data.grantee_login)
    if not grantee:
        raise HTTPException(status_code=404, detail="Grantee user not found")
    if grantee.id == grantor_id:
        raise HTTPException(status_code=400, detail="Cannot add yourself as emergency contact")

    # Prevent duplicate active invites
    existing = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.grantor_id == grantor_id,
        models.EmergencyAccess.grantee_id == grantee.id,
        models.EmergencyAccess.status.in_(["invited", "accepted", "waiting"]),
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="Emergency access already active for this user")

    ea = models.EmergencyAccess(
        grantor_id=grantor_id,
        grantee_id=grantee.id,
        wait_days=wait_days,
        status="invited",
    )
    db.add(ea)
    db.commit()
    db.refresh(ea)
    audit_event(db, grantor_id, "emergency_access_invited",
                {"grantee": data.grantee_login}, background_tasks=background_tasks)
    return ea


def list_emergency_access(db: Session, user_id: int) -> List[models.EmergencyAccess]:
    return db.query(models.EmergencyAccess).filter(
        (models.EmergencyAccess.grantor_id == user_id) |
        (models.EmergencyAccess.grantee_id == user_id),
    ).order_by(models.EmergencyAccess.created_at.desc()).all()


def accept_emergency_invite(db: Session, ea_id: int, grantee_id: int,
                             background_tasks: BackgroundTasks = None) -> models.EmergencyAccess:
    ea = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.id == ea_id,
        models.EmergencyAccess.grantee_id == grantee_id,
        models.EmergencyAccess.status == "invited",
    ).first()
    if not ea:
        raise HTTPException(status_code=404, detail="Invitation not found")
    ea.status = "accepted"
    db.commit()
    db.refresh(ea)
    audit_event(db, grantee_id, "emergency_access_accepted", {"ea_id": ea_id},
                background_tasks=background_tasks)
    return ea


def request_emergency_access(db: Session, ea_id: int, grantee_id: int,
                              background_tasks: BackgroundTasks = None) -> models.EmergencyAccess:
    ea = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.id == ea_id,
        models.EmergencyAccess.grantee_id == grantee_id,
        models.EmergencyAccess.status == "accepted",
    ).first()
    if not ea:
        raise HTTPException(status_code=404, detail="Emergency access not found or not accepted")
    ea.status = "waiting"
    ea.requested_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(ea)
    audit_event(db, grantee_id, "emergency_access_requested", {"ea_id": ea_id},
                background_tasks=background_tasks)
    return ea


def checkin_emergency_access(db: Session, ea_id: int, grantor_id: int,
                              background_tasks: BackgroundTasks = None) -> models.EmergencyAccess:
    ea = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.id == ea_id,
        models.EmergencyAccess.grantor_id == grantor_id,
        models.EmergencyAccess.status == "waiting",
    ).first()
    if not ea:
        raise HTTPException(status_code=404, detail="No pending emergency request found")
    ea.last_checkin_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(ea)
    audit_event(db, grantor_id, "emergency_checkin", {"ea_id": ea_id},
                background_tasks=background_tasks)
    return ea


def deny_emergency_access(db: Session, ea_id: int, grantor_id: int,
                           background_tasks: BackgroundTasks = None):
    ea = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.id == ea_id,
        models.EmergencyAccess.grantor_id == grantor_id,
        models.EmergencyAccess.status == "waiting",
    ).first()
    if not ea:
        raise HTTPException(status_code=404, detail="No pending emergency request found")
    ea.status = "denied"
    db.commit()
    audit_event(db, grantor_id, "emergency_access_denied", {"ea_id": ea_id},
                background_tasks=background_tasks)


def revoke_emergency_access(db: Session, ea_id: int, grantor_id: int,
                             background_tasks: BackgroundTasks = None):
    ea = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.id == ea_id,
        models.EmergencyAccess.grantor_id == grantor_id,
        models.EmergencyAccess.status.notin_(["revoked"]),
    ).first()
    if not ea:
        raise HTTPException(status_code=404, detail="Emergency access not found")
    ea.status = "revoked"
    db.commit()
    audit_event(db, grantor_id, "emergency_access_revoked", {"ea_id": ea_id},
                background_tasks=background_tasks)


def upload_emergency_vault(db: Session, ea_id: int, grantor_id: int,
                            encrypted_vault: str,
                            background_tasks: BackgroundTasks = None) -> models.EmergencyAccess:
    ea = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.id == ea_id,
        models.EmergencyAccess.grantor_id == grantor_id,
        models.EmergencyAccess.status.in_(["accepted", "waiting"]),
    ).first()
    if not ea:
        raise HTTPException(status_code=404, detail="Emergency access not found")
    ea.encrypted_vault = encrypted_vault
    db.commit()
    db.refresh(ea)
    audit_event(db, grantor_id, "emergency_vault_uploaded", {"ea_id": ea_id},
                background_tasks=background_tasks)
    return ea


def get_emergency_vault(db: Session, ea_id: int, grantee_id: int) -> models.EmergencyAccess:
    ea = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.id == ea_id,
        models.EmergencyAccess.grantee_id == grantee_id,
        models.EmergencyAccess.status == "approved",
    ).first()
    if not ea:
        raise HTTPException(status_code=403, detail="Access not approved or not found")
    if not ea.encrypted_vault:
        raise HTTPException(status_code=404, detail="No vault data uploaded by grantor yet")
    return ea


def process_emergency_approvals(db: Session):
    """Auto-approve emergency requests where the wait period has elapsed.
    Called periodically from a background scheduler.
    """
    now = datetime.now(timezone.utc)
    pending = db.query(models.EmergencyAccess).filter(
        models.EmergencyAccess.status == "waiting",
    ).all()
    for ea in pending:
        # Timer resets on each grantor check-in
        reference = ea.last_checkin_at or ea.requested_at
        if reference is None:
            continue
        if reference.tzinfo is None:
            reference = reference.replace(tzinfo=timezone.utc)
        if now >= reference + timedelta(days=ea.wait_days):
            ea.status = "approved"
            ea.approved_at = now
            audit_event(db, ea.grantee_id, "emergency_access_auto_approved",
                        {"ea_id": ea.id, "grantor_id": ea.grantor_id})
    db.commit()
