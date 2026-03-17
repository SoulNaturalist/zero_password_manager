from typing import List

from fastapi import APIRouter, Depends, Query, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy.orm import Session

from ..auth.dependencies import get_current_user, require_otp_for
from ..database import get_db
from ..models import Folder, User
from ..passwords.schemas import PasswordResponse
from ..passwords.service import get_passwords_by_folder
from ..utils import attach_favicons
from .dependencies import valid_folder
from .schemas import FolderCreate, FolderResponse, FolderUpdate
from .service import create_folder, delete_folder, get_folders, update_folder

router = APIRouter(prefix="/folders", tags=["folders"])
limiter = Limiter(key_func=get_remote_address)


@router.get("", response_model=List[FolderResponse])
@limiter.limit("60/minute")
def read_folders(
    request: Request,
    include_hidden: bool = Query(False, alias="include_hidden"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return get_folders(db, user_id=current_user.id, include_hidden=include_hidden)


@router.post("", response_model=FolderResponse, status_code=201)
@limiter.limit("30/minute")
def create_folder_entry(
    request: Request,
    body: FolderCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return create_folder(db, data=body, user_id=current_user.id)


@router.put("/{folder_id}", response_model=FolderResponse)
@limiter.limit("30/minute")
def update_folder_entry(
    request: Request,
    body: FolderUpdate,
    folder: Folder = Depends(valid_folder),
    db: Session = Depends(get_db),
):
    return update_folder(db, folder=folder, data=body)


@router.delete("/{folder_id}", status_code=204)
@limiter.limit("30/minute")
def delete_folder_entry(
    request: Request,
    folder: Folder = Depends(valid_folder),
    db: Session = Depends(get_db),
):
    delete_folder(db, folder=folder)


@router.get("/{folder_id}/passwords", response_model=List[PasswordResponse])
@limiter.limit("60/minute")
def read_folder_passwords(
    request: Request,
    folder_id: int,
    current_user: User = Depends(require_otp_for("vault_read")),
    db: Session = Depends(get_db),
):
    passwords = get_passwords_by_folder(db, folder_id=folder_id, user_id=current_user.id)
    attach_favicons(passwords)
    return passwords
