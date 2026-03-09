from sqlalchemy.orm import Session
from fastapi import HTTPException, status
import re
from typing import Optional
from . import models, schemas, auth

def get_user_by_login(db: Session, login: str):
    return db.query(models.User).filter(models.User.login == login).first()


def audit_event(db: Session, user_id: int, event: str, meta: dict = None, ip: str = None):
    db_audit = models.Audit(user_id=user_id, event=event, meta=meta or {}, ip_address=ip)
    db.add(db_audit)
    db.commit()


def validate_password_strength(password: str) -> bool:
    """Min 12 chars, uppercase, lowercase, digit"""
    return (
        len(password) >= 12 and
        re.search(r'[A-Z]', password) and
        re.search(r'[a-z]', password) and
        re.search(r'\d', password)
    )


def create_user(db: Session, user: schemas.UserCreate):
    if not validate_password_strength(user.password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password too weak. Minimum 12 characters, including uppercase, lowercase, and a digit."
        )
    salt = auth.generate_salt()
    hashed_password = auth.get_password_hash(user.password)
    db_user = models.User(login=user.login, hashed_password=hashed_password, salt=salt)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    audit_event(db, db_user.id, "register")
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


def get_passwords(db: Session, user_id: int):
    audit_event(db, user_id, "vault_read")
    return db.query(models.Password).filter(models.Password.user_id == user_id).all()


def create_password(db: Session, password: schemas.PasswordCreate, user_id: int):
    # Validate folder ownership if folder_id provided
    if password.folder_id is not None:
        folder = db.query(models.Folder).filter(
            models.Folder.id == password.folder_id,
            models.Folder.user_id == user_id
        ).first()
        if not folder:
            raise HTTPException(status_code=404, detail="Folder not found")

    # Pure Zero-Knowledge: Just store what the client sends
    db_password = models.Password(
        user_id=user_id,
        folder_id=password.folder_id,
        site_url=password.site_url,
        site_login=password.site_login,
        encrypted_payload=password.encrypted_payload,
        notes_encrypted=password.notes_encrypted,
        has_2fa=password.has_2fa,
        has_seed_phrase=password.has_seed_phrase
    )
    db.add(db_password)
    db.commit()
    db.refresh(db_password)

    audit_event(db, user_id, "vault_create", meta={"site_url": password.site_url})

    return db_password


def update_password(db: Session, password_id: int, password: schemas.PasswordUpdate, user_id: int):
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
    db_password.site_url = password.site_url
    db_password.site_login = password.site_login
    db_password.encrypted_payload = password.encrypted_payload
    db_password.notes_encrypted = password.notes_encrypted
    db_password.has_2fa = password.has_2fa
    db_password.has_seed_phrase = password.has_seed_phrase
    db.commit()
    db.refresh(db_password)

    audit_event(db, user_id, "vault_update", meta={"site_url": password.site_url})
    return db_password


def delete_password(db: Session, password_id: int, user_id: int):
    db_password = db.query(models.Password).filter(
        models.Password.id == password_id,
        models.Password.user_id == user_id
    ).first()
    if not db_password:
        raise HTTPException(status_code=404, detail="Password not found")

    audit_event(db, user_id, "vault_delete", meta={"site_url": db_password.site_url})
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


def create_folder(db: Session, folder: schemas.FolderCreate, user_id: int):
    db_folder = models.Folder(
        user_id=user_id,
        name=folder.name,
        color=folder.color,
        icon=folder.icon,
    )
    db.add(db_folder)
    db.commit()
    db.refresh(db_folder)
    audit_event(db, user_id, "folder_create", meta={"name": folder.name})
    return db_folder


def update_folder(db: Session, folder_id: int, folder: schemas.FolderUpdate, user_id: int):
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
    audit_event(db, user_id, "folder_update", meta={"id": folder_id})
    return db_folder


def delete_folder(db: Session, folder_id: int, user_id: int):
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

    audit_event(db, user_id, "folder_delete", meta={"id": folder_id})
    db.delete(db_folder)
    db.commit()


def get_passwords_by_folder(db: Session, folder_id: int, user_id: int):
    # Verify folder ownership
    folder = db.query(models.Folder).filter(
        models.Folder.id == folder_id,
        models.Folder.user_id == user_id
    ).first()
    if not folder:
        raise HTTPException(status_code=404, detail="Folder not found")

    audit_event(db, user_id, "vault_read", meta={"folder_id": folder_id})
    return db.query(models.Password).filter(
        models.Password.folder_id == folder_id,
        models.Password.user_id == user_id
    ).all()


def get_history(db: Session, user_id: int):
    audit_event(db, user_id, "history_read")
    return db.query(models.PasswordHistory).filter(models.PasswordHistory.user_id == user_id).order_by(models.PasswordHistory.created_at.desc()).all()


def get_logs(db: Session, user_id: int):
    return db.query(models.Audit).filter(models.Audit.user_id == user_id).order_by(models.Audit.created_at.desc()).limit(100).all()
