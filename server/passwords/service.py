from typing import Optional

from sqlalchemy.orm import Session

from ..audit.service import record as audit
from ..models import Password
from .exceptions import PasswordNotFound
from .schemas import PasswordCreate, PasswordUpdate


def get_password_by_id(
    db: Session, password_id: int, user_id: int
) -> Optional[Password]:
    return (
        db.query(Password)
        .filter(Password.id == password_id, Password.user_id == user_id)
        .first()
    )


def get_passwords(db: Session, user_id: int) -> list[Password]:
    audit(db, user_id, "vault_read")
    return db.query(Password).filter(Password.user_id == user_id).all()


def create_password(
    db: Session, data: PasswordCreate, user_id: int
) -> Password:
    # Folder ownership is validated in the dependency layer before reaching here
    pw = Password(
        user_id=user_id,
        folder_id=data.folder_id,
        site_url=data.site_url,
        site_login=data.site_login,
        encrypted_payload=data.encrypted_payload,
        notes_encrypted=data.notes_encrypted,
        has_2fa=data.has_2fa,
        has_seed_phrase=False,
    )
    db.add(pw)
    db.commit()
    db.refresh(pw)

    audit(db, user_id, "vault_create", meta={"site_url": data.site_url})
    return pw


def update_password(
    db: Session, password: Password, data: PasswordUpdate
) -> Password:
    """Update a Password model object that was already fetched and ownership-checked."""
    password.folder_id         = data.folder_id
    password.site_url          = data.site_url
    password.site_login        = data.site_login
    password.encrypted_payload = data.encrypted_payload
    password.notes_encrypted   = data.notes_encrypted
    password.has_2fa           = data.has_2fa
    password.has_seed_phrase   = False
    db.commit()
    db.refresh(password)

    audit(db, password.user_id, "vault_update", meta={"site_url": data.site_url})
    return password


def delete_password(db: Session, password: Password) -> None:
    """Delete a Password model object that was already fetched and ownership-checked."""
    audit(db, password.user_id, "vault_delete", meta={"site_url": password.site_url})
    db.delete(password)
    db.commit()


def get_passwords_by_folder(
    db: Session, folder_id: int, user_id: int
) -> list[Password]:
    audit(db, user_id, "vault_read", meta={"folder_id": folder_id})
    return (
        db.query(Password)
        .filter(Password.folder_id == folder_id, Password.user_id == user_id)
        .all()
    )
