import re
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from . import models, schemas, auth


# ── Private helpers ───────────────────────────────────────────────────────────

def _get_password_or_404(db: Session, password_id: int, user_id: int) -> models.Password:
    """Return a password owned by user_id, or raise 404."""
    pw = (
        db.query(models.Password)
        .filter(models.Password.id == password_id, models.Password.user_id == user_id)
        .first()
    )
    if not pw:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Password not found")
    return pw


def _get_folder_or_404(db: Session, folder_id: int, user_id: int) -> models.Folder:
    """Return a folder owned by user_id, or raise 404."""
    folder = (
        db.query(models.Folder)
        .filter(models.Folder.id == folder_id, models.Folder.user_id == user_id)
        .first()
    )
    if not folder:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Folder not found")
    return folder


def _validate_password_strength(password: str) -> bool:
    """Min 12 characters, at least one uppercase, one lowercase, one digit."""
    return (
        len(password) >= 12
        and bool(re.search(r'[A-Z]', password))
        and bool(re.search(r'[a-z]', password))
        and bool(re.search(r'\d',    password))
    )


# ── Audit ─────────────────────────────────────────────────────────────────────

def audit_event(
    db: Session,
    user_id: int,
    event: str,
    meta: Optional[dict] = None,
    ip: Optional[str] = None,
) -> None:
    db.add(models.Audit(user_id=user_id, event=event, meta=meta or {}, ip_address=ip))
    db.commit()


# ── Users ─────────────────────────────────────────────────────────────────────

def get_user_by_login(db: Session, login: str) -> Optional[models.User]:
    return db.query(models.User).filter(models.User.login == login).first()


def create_user(db: Session, user: schemas.UserCreate) -> models.User:
    if not _validate_password_strength(user.password):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Password too weak. Minimum 12 characters including uppercase, lowercase and a digit.",
        )

    db_user = models.User(
        login=user.login,
        hashed_password=auth.hash_password(user.password),
        salt=auth.generate_salt(),
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)

    audit_event(db, db_user.id, "register")
    return db_user


def update_user_totp(
    db: Session,
    user_id: int,
    secret: Optional[str] = None,
    enabled: Optional[bool] = None,
) -> models.User:
    user = db.get(models.User, user_id)
    if secret is not None:
        user.totp_secret = secret
    if enabled is not None:
        user.totp_enabled = enabled
    db.commit()
    db.refresh(user)
    return user


# ── Passwords ─────────────────────────────────────────────────────────────────

def get_passwords(db: Session, user_id: int) -> list[models.Password]:
    audit_event(db, user_id, "vault_read")
    return db.query(models.Password).filter(models.Password.user_id == user_id).all()


def create_password(
    db: Session, password: schemas.PasswordCreate, user_id: int
) -> models.Password:
    if password.folder_id is not None:
        _get_folder_or_404(db, password.folder_id, user_id)  # ensures ownership

    db_password = models.Password(
        user_id=user_id,
        folder_id=password.folder_id,
        site_url=password.site_url,
        site_login=password.site_login,
        encrypted_payload=password.encrypted_payload,
        notes_encrypted=password.notes_encrypted,
        has_2fa=password.has_2fa,
        has_seed_phrase=password.has_seed_phrase,
    )
    db.add(db_password)
    db.commit()
    db.refresh(db_password)

    audit_event(db, user_id, "vault_create", meta={"site_url": password.site_url})
    return db_password


def update_password(
    db: Session, password_id: int, password: schemas.PasswordUpdate, user_id: int
) -> models.Password:
    db_password = _get_password_or_404(db, password_id, user_id)

    if password.folder_id is not None:
        _get_folder_or_404(db, password.folder_id, user_id)  # ensures ownership

    db_password.folder_id        = password.folder_id
    db_password.site_url         = password.site_url
    db_password.site_login       = password.site_login
    db_password.encrypted_payload = password.encrypted_payload
    db_password.notes_encrypted  = password.notes_encrypted
    db_password.has_2fa          = password.has_2fa
    db_password.has_seed_phrase  = password.has_seed_phrase
    db.commit()
    db.refresh(db_password)

    audit_event(db, user_id, "vault_update", meta={"site_url": password.site_url})
    return db_password


def delete_password(db: Session, password_id: int, user_id: int) -> None:
    db_password = _get_password_or_404(db, password_id, user_id)
    audit_event(db, user_id, "vault_delete", meta={"site_url": db_password.site_url})
    db.delete(db_password)
    db.commit()


# ── Folders ───────────────────────────────────────────────────────────────────

def get_folders(db: Session, user_id: int) -> list[models.Folder]:
    """Return all folders for a user with password_count attached as a transient attribute.

    A single LEFT JOIN query is used to avoid the N+1 problem.
    """
    rows = (
        db.query(models.Folder, func.count(models.Password.id).label("pw_count"))
        .outerjoin(models.Password, models.Password.folder_id == models.Folder.id)
        .filter(models.Folder.user_id == user_id)
        .group_by(models.Folder.id)
        .all()
    )
    for folder, count in rows:
        folder.password_count = count
    return [folder for folder, _ in rows]


def create_folder(
    db: Session, folder: schemas.FolderCreate, user_id: int
) -> models.Folder:
    db_folder = models.Folder(
        user_id=user_id,
        name=folder.name,
        color=folder.color,
        icon=folder.icon,
    )
    db.add(db_folder)
    db.commit()
    db.refresh(db_folder)
    db_folder.password_count = 0  # new folder has no passwords

    audit_event(db, user_id, "folder_create", meta={"name": folder.name})
    return db_folder


def update_folder(
    db: Session, folder_id: int, folder: schemas.FolderUpdate, user_id: int
) -> models.Folder:
    db_folder = _get_folder_or_404(db, folder_id, user_id)

    if folder.name  is not None: db_folder.name  = folder.name
    if folder.color is not None: db_folder.color = folder.color
    if folder.icon  is not None: db_folder.icon  = folder.icon
    db.commit()
    db.refresh(db_folder)

    count = db.query(func.count(models.Password.id)).filter(
        models.Password.folder_id == folder_id
    ).scalar()
    db_folder.password_count = count

    audit_event(db, user_id, "folder_update", meta={"id": folder_id})
    return db_folder


def delete_folder(db: Session, folder_id: int, user_id: int) -> None:
    db_folder = _get_folder_or_404(db, folder_id, user_id)

    # Detach passwords from this folder — never delete them
    db.query(models.Password).filter(
        models.Password.folder_id == folder_id
    ).update({"folder_id": None})

    audit_event(db, user_id, "folder_delete", meta={"id": folder_id})
    db.delete(db_folder)
    db.commit()


def get_passwords_by_folder(
    db: Session, folder_id: int, user_id: int
) -> list[models.Password]:
    _get_folder_or_404(db, folder_id, user_id)  # ensures ownership

    audit_event(db, user_id, "vault_read", meta={"folder_id": folder_id})
    return (
        db.query(models.Password)
        .filter(models.Password.folder_id == folder_id, models.Password.user_id == user_id)
        .all()
    )


# ── Audit / history ───────────────────────────────────────────────────────────

def get_history(db: Session, user_id: int) -> list[models.PasswordHistory]:
    audit_event(db, user_id, "history_read")
    return (
        db.query(models.PasswordHistory)
        .filter(models.PasswordHistory.user_id == user_id)
        .order_by(models.PasswordHistory.created_at.desc())
        .all()
    )


def get_audit_logs(db: Session, user_id: int) -> list[models.Audit]:
    return (
        db.query(models.Audit)
        .filter(models.Audit.user_id == user_id)
        .order_by(models.Audit.created_at.desc())
        .limit(100)
        .all()
    )
