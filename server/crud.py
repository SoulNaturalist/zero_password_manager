from sqlalchemy.orm import Session
from fastapi import HTTPException, status
import re
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
    # Pure Zero-Knowledge: Just store what the client sends
    db_password = models.Password(
        user_id=user_id,
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


def get_history(db: Session, user_id: int):
    audit_event(db, user_id, "history_read")
    return db.query(models.PasswordHistory).filter(models.PasswordHistory.user_id == user_id).order_by(models.PasswordHistory.created_at.desc()).all()


def get_logs(db: Session, user_id: int):
    return db.query(models.Audit).filter(models.Audit.user_id == user_id).order_by(models.Audit.created_at.desc()).limit(100).all()
