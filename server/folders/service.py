from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from ..audit.service import record as audit
from ..models import Folder, Password
from .exceptions import FolderNotFound
from .schemas import FolderCreate, FolderUpdate


def get_folder_by_id(
    db: Session, folder_id: int, user_id: int
) -> Optional[Folder]:
    return (
        db.query(Folder)
        .filter(Folder.id == folder_id, Folder.user_id == user_id)
        .first()
    )


def get_folders(
    db: Session, user_id: int, include_hidden: bool = False
) -> list[Folder]:
    """
    Return all folders with password_count attached as a transient attribute.
    When include_hidden is False (default), hidden folders are excluded from the result.
    Uses a single LEFT JOIN + GROUP BY to avoid the N+1 query problem.
    """
    query = (
        db.query(Folder, func.count(Password.id).label("pw_count"))
        .outerjoin(Password, Password.folder_id == Folder.id)
        .filter(Folder.user_id == user_id)
    )
    if not include_hidden:
        query = query.filter(Folder.is_hidden == False)  # noqa: E712
    rows = query.group_by(Folder.id).all()

    for folder, count in rows:
        folder.password_count = count
    return [folder for folder, _ in rows]


def create_folder(db: Session, data: FolderCreate, user_id: int) -> Folder:
    folder = Folder(
        user_id=user_id,
        name=data.name,
        color=data.color,
        icon=data.icon,
        is_hidden=data.is_hidden,
    )
    db.add(folder)
    db.commit()
    db.refresh(folder)
    folder.password_count = 0

    audit(db, user_id, "folder_create", meta={"name": data.name, "is_hidden": data.is_hidden})
    return folder


def update_folder(db: Session, folder: Folder, data: FolderUpdate) -> Folder:
    """Update a Folder object that was already fetched and ownership-checked."""
    if data.name      is not None: folder.name      = data.name
    if data.color     is not None: folder.color     = data.color
    if data.icon      is not None: folder.icon      = data.icon
    if data.is_hidden is not None: folder.is_hidden = data.is_hidden
    db.commit()
    db.refresh(folder)

    folder.password_count = (
        db.query(func.count(Password.id))
        .filter(Password.folder_id == folder.id)
        .scalar()
    )

    audit(db, folder.user_id, "folder_update", meta={"id": folder.id})
    return folder


def delete_folder(db: Session, folder: Folder) -> None:
    """
    Delete a folder. Passwords inside it are NOT deleted — they become unassigned.
    Ownership is verified by the dependency layer before this is called.
    """
    db.query(Password).filter(Password.folder_id == folder.id).update(
        {"folder_id": None}
    )
    audit(db, folder.user_id, "folder_delete", meta={"id": folder.id})
    db.delete(folder)
    db.commit()

