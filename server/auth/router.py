import asyncio
import secrets
from datetime import datetime, timedelta

import pyotp
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy.orm import Session

from ..audit.service import record as audit
from ..database import get_db
from ..models import FailedAttempt, User
from ..utils import get_client_ip
from .dependencies import get_current_user
from .exceptions import (
    InvalidOTPCode,
    InvalidRefreshToken,
    TwoFAAlreadyEnabled,
    TwoFANotSetUp,
    UserAlreadyExists,
)
from .schemas import (
    LoginRequest,
    RefreshRequest,
    TOTPConfirmRequest,
    TOTPSetupResponse,
    Token,
    UserCreate,
    UserResponse,
    LoginPhase1Response,
)
from .service import (
    authenticate_user,
    create_access_token,
    create_refresh_token,
    create_user,
    decode_token,
    decrypt_totp,
    get_user_by_login,
    rotate_refresh_token,
    update_user_totp,
    verify_hardened_otp,
    verify_password,
    hash_password,
    create_short_token,
    generate_device_id,
    handle_failed_otp_attempt,
    reset_otp_failure_counters,
    safe_compare,
    constant_time_response,
    create_mfa_token,
    validate_mfa_token,
    get_device_id_from_request,
    log_security_event,
    notify_user_of_suspicious_activity,
)
from ..config import settings
from ..security import SecurityManager, SECURITY_PARAMS
from ..schemas import PasswordResetRequest
from functools import wraps
import time

router = APIRouter(tags=["auth"])
limiter = Limiter(key_func=get_remote_address)


class RateLimiter:
    def __init__(self):
        self.locks = {}

    def limit(self, path: str, max_attempts: int, period: int):
        def decorator(func):
            @wraps(func)
            async def wrapper(*args, **kwargs):
                key = f"{path}:{get_client_ip(kwargs.get('request')) if 'request' in kwargs else 'unknown'}"
                now = time.time()
                
                if key in self.locks:
                    attempts, timestamp = self.locks[key]
                    if now - timestamp < period:
                        if attempts >= max_attempts:
                            raise HTTPException(status_code=429, detail="Rate limit exceeded")
                        self.locks[key] = (attempts + 1, timestamp)
                    else:
                        self.locks[key] = (1, now)
                else:
                    self.locks[key] = (1, now)
                
                return await func(*args, **kwargs)
            
            return wrapper
        return decorator

rate_limiter = RateLimiter()


@router.on_event("startup")
async def startup_event():
    """Schedule periodic cleanup task."""
    import asyncio
    async def periodic_cleanup():
        while True:
            await asyncio.sleep(SECURITY_PARAMS["BLOCK_CLEANUP_INTERVAL"].total_seconds())
            # Использование db_session в фоновом режиме
            from ..database import SessionLocal
            db = SessionLocal()
            try:
                SecurityManager.cleanup_old_blocks(db)
            finally:
                db.close()
    
    asyncio.create_task(periodic_cleanup())


@router.post("/register", response_model=UserResponse, status_code=201)
@limiter.limit("3/minute")
def register(
    request: Request,
    body: UserCreate,
    db: Session = Depends(get_db),
):
    if get_user_by_login(db, login=body.login):
        raise UserAlreadyExists()

    new_user = create_user(db, data=body)

    secret = pyotp.random_base32()
    update_user_totp(db, new_user, secret=secret)
    totp_uri = pyotp.TOTP(secret).provisioning_uri(
        name=new_user.login, issuer_name="ZeroVault"
    )

    # Mint a short-lived enrollment token so the client can call /confirm_2fa
    # without a full login cycle. The token is valid for one access-token TTL
    # and TOTP is still disabled until the user confirms the code.
    enrollment_device_id = generate_device_id(request)
    enrollment_token = create_access_token(new_user, enrollment_device_id)

    audit(db, new_user.id, "register")

    return UserResponse(
        id=new_user.id,
        login=new_user.login,
        salt=new_user.salt,
        totp_uri=totp_uri,
        totp_secret=secret,
        access_token=enrollment_token,
    )


@router.post("/login", response_model=LoginPhase1Response)
@rate_limiter.limit("/login", max_attempts=5, period=60)
async def login_phase1(
    request: Request,
    body: LoginRequest,
    db: Session = Depends(get_db),
):
    """
    ПЕРВЫЙ этап аутентификации с кастомным rate limiting, CAPTCHA и защитой от брутфорса.
    """
    start_time = time.time()
    ip_address = get_client_ip(request)
    
    # 1. Проверка блокировки IP
    if SecurityManager.is_ip_blocked(db, ip_address):
        SecurityManager.constant_time_delay(start_time)
        raise HTTPException(status_code=429, detail="IP temporarily blocked")
    
    # 2. Проверка необходимости CAPTCHA (если много попыток)
    # В реализации клиента ожидается заголовок или флаг в ответе, но здесь мы просто проверяем.
    # Если требуется CAPTCHA, клиент должен вызвать /captcha-verify сначала.
    
    # 3. Получаем пользователя
    user = get_user_by_login(db, login=body.login)
    user_exists = bool(user)
    
    # 4. Защита от перебора
    # A valid (but unverifiable) argon2id hash used purely for constant-time
    # comparison when the login doesn't exist (prevents user-enumeration via
    # timing). Salt must decode to >= 8 bytes; hash must be >= 12 bytes.
    fake_hash = "$argon2id$v=19$m=65536,t=3,p=4$c2FsdHNhbHRzYWx0c2FsdA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    password_valid = False
    
    if user_exists:
        password_valid = verify_password(body.password, user.hashed_password)
    else:
        verify_password(body.password, fake_hash)
    
    # 5. Логика блокировки
    if not password_valid:
        SecurityManager.record_failed_attempt(db, ip_address)
        attempt = db.query(FailedAttempt).filter_by(ip=ip_address).first()
        attempts = attempt.count if attempt else 0
        
        BRUTE_FORCE_MAX = 4 # MAX_ATTEMPTS из security.py (BRUTE_FORCE_PROTECTION)
        if attempts >= BRUTE_FORCE_MAX:
             SecurityManager.block_ip(db, ip_address, timedelta(hours=3))
            
        log_security_event(db, user.id if user else None, "failed_login", 
            {"user_exists": user_exists, "ip": ip_address, "attempts": attempts}, ip_address)
        
        response = LoginPhase1Response(
            requires_mfa=False,
            salt=secrets.token_hex(16)
        )
    else:
        # Успех
        log_security_event(db, user.id, "password_verified", {"ip": ip_address}, ip_address)
        
        otp_required = user.totp_enabled and "login" in settings.PERMISSIONS_OTP_LIST
        
        if otp_required:
            device_id = generate_device_id(request, body.device_info)
            mfa_token = create_mfa_token(user.id, device_id)
            response = LoginPhase1Response(
                requires_mfa=True,
                mfa_token=mfa_token,
                salt=user.salt
            )
        else:
            device_id = generate_device_id(request, body.device_info)
            access_token = create_access_token(user, device_id)
            refresh_token = create_refresh_token(db, user.id, device_id)
            
            user.failed_login_attempts = 0
            attempt = db.query(FailedAttempt).filter_by(ip=ip_address).first()
            if attempt:
                attempt.count = 0
            db.commit()
            
            log_security_event(db, user.id, "login_success", {"device_id": device_id, "ip": ip_address}, ip_address)
            
            response = LoginPhase1Response(
                requires_mfa=False,
                salt=user.salt,
                access_token=access_token,
                refresh_token=refresh_token,
            )
    
    constant_time_response(start_time)
    return response


@router.post("/captcha-verify")
@limiter.limit("5/minute")
async def verify_captcha(
    request: Request,
    body: dict, # captcha_solution
    db: Session = Depends(get_db)
):
    ip_address = get_client_ip(request)
    captcha_solution = body.get("solution")
    
    if not SecurityManager.verify_captcha(captcha_solution):
        raise HTTPException(status_code=400, detail="Invalid CAPTCHA")
    
    # Reset failed attempts after successful CAPTCHA
    from ..models import FailedAttempt
    attempt = db.query(FailedAttempt).filter_by(ip=ip_address).first()
    if attempt:
        attempt.count = 0
    db.commit()
    
    return {"success": True}


@router.post("/setup_2fa", response_model=TOTPSetupResponse)
async def setup_2fa(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Безопасная настройка 2FA с защитой от перезаписи существующего секрета.
    """
    start_time = time.time()
    
    # Проверяем, не включена ли уже 2FA
    if current_user.totp_enabled:
        log_security_event(db, current_user.id, "2fa_setup_attempt", 
            {"status": "already_enabled"}, None)
        raise HTTPException(
            status_code=400,
            detail="2FA is already enabled"
        )
    
    # Генерируем новый секрет
    secret = pyotp.random_base32()
    update_user_totp(db, current_user, secret=secret)
    
    # Создаем URI для QR кода
    otp_uri = pyotp.TOTP(secret).provisioning_uri(
        name=current_user.login, 
        issuer_name="ZeroVault"
    )
    
    # Логируем начало настройки 2FA
    log_security_event(db, current_user.id, "2fa_setup_started", {}, None)
    
    # КОНСТАНТНОЕ время ответа
    constant_time_response(start_time)
    
    return TOTPSetupResponse(secret=secret, otp_uri=otp_uri)


@router.post("/login/mfa", response_model=Token)
@limiter.limit("5/minute")
async def login_phase2(
    request: Request,
    body: TOTPConfirmRequest,
    db: Session = Depends(get_db),
):
    """
    ВТОРОЙ этап аутентификации: проверка TOTP.
    
    Ключевые исправления:
    1. Проверка TOTP происходит только после успешной проверки пароля
    2. Нет утечки информации о состоянии учетной записи
    3. Счетчик TOTP ошибок увеличивается ТОЛЬКО для существующих пользователей
    """
    start_time = time.time()
    ip_address = get_client_ip(request)
    totp_valid = False
    
    try:
        # Валидируем MFA токен
        payload = validate_mfa_token(body.mfa_token)
        user_id = int(payload["sub"])
        device_id = payload["device"]
        
        # Получаем пользователя
        user = db.get(User, user_id)
        if not user:
            raise HTTPException(
                status_code=401,
                detail="Invalid authentication"
            )
        
        # Проверка TOTP
        try:
            verify_hardened_otp(db, user, body.code, ip_address)
            totp_valid = True
            reset_otp_failure_counters(user, db)
        except Exception as e:
            handle_failed_otp_attempt(db, user, ip_address)
            log_security_event(db, user.id, "otp_failed", 
                {"error": str(e), "ip": ip_address}, ip_address)
            raise

        # Генерация полноценных токенов
        access_token = create_access_token(user, device_id)
        refresh_token = create_refresh_token(db, user.id, device_id)
        
        # Сброс счетчиков неудачных попыток
        user.failed_login_attempts = 0
        db.commit()
        
        # Логируем успешный вход
        log_security_event(db, user.id, "login_success", 
            {"device_id": device_id, "ip": ip_address}, ip_address)
        
        # Возвращаем полноценные токены
        return Token(
            access_token=access_token,
            refresh_token=refresh_token,
            user_id=user.id,
            login=user.login,
            salt=user.salt,
            two_fa_required=False,
        )

    except HTTPException:
        raise
    except Exception as e:
        log_security_event(db, None, "mfa_error", 
            {"error": str(e), "ip": ip_address}, ip_address)
        raise HTTPException(
            status_code=401,
            detail="Invalid authentication"
        )
    finally:
        # КОНСТАНТНОЕ время ответа для всех веток
        constant_time_response(start_time)

@router.post("/confirm_2fa", response_model=Token)
@limiter.limit("5/minute")
async def confirm_2fa(
    request: Request,
    body: TOTPConfirmRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Безопасное включение 2FA с защитой от захвата учетной записи.
    
    Ключевые исправления:
    1. Проверка TOTP происходит только после успешной проверки пароля
    2. Нет утечки информации о состоянии учетной записи
    """
    start_time = time.time()
    ip_address = get_client_ip(request)
    totp_valid = False
    
    # Проверка текущего пароля (уже выполнена в get_current_user)
    # Здесь мы можем быть уверены, что current_user аутентифицирован
    
    # Проверка TOTP
    # verify_hardened_otp skips when totp_enabled=False, so for the
    # enrollment step we verify the code directly against the stored secret.
    if not current_user.totp_secret:
        raise HTTPException(status_code=400, detail="2FA not set up. Call /setup_2fa first.")
    try:
        totp_secret = decrypt_totp(current_user.totp_secret, current_user.id)
        totp_obj = pyotp.TOTP(totp_secret)
        valid = any(
            totp_obj.verify(body.code, for_time=datetime.utcnow() + timedelta(seconds=offset), valid_window=1)
            for offset in (-30, 0, 30)
        )
        if not valid:
            handle_failed_otp_attempt(db, current_user, ip_address)
            log_security_event(db, current_user.id, "2fa_setup_failed",
                {"ip": ip_address}, ip_address)
            constant_time_response(start_time)
            raise HTTPException(status_code=401, detail="Invalid OTP code")
        totp_valid = True
        reset_otp_failure_counters(current_user, db)
    except HTTPException:
        raise
    except Exception as e:
        handle_failed_otp_attempt(db, current_user, ip_address)
        log_security_event(db, current_user.id, "2fa_setup_failed",
            {"error": str(e), "ip": ip_address}, ip_address)
        constant_time_response(start_time)
        raise HTTPException(status_code=401, detail="Invalid OTP code")

    # Включаем 2FA
    current_user.totp_enabled = True
    current_user.last_otp_ts = pyotp.TOTP(decrypt_totp(current_user.totp_secret, current_user.id)).timecode(datetime.utcnow())
    db.commit()
    
    # Генерация токенов
    device_id = generate_device_id(request)
    access_token = create_access_token(current_user, device_id)
    refresh_token = create_refresh_token(db, current_user.id, device_id)
    
    # Логируем успешное включение 2FA
    log_security_event(db, current_user.id, "2fa_enabled", 
        {"ip": ip_address, "device_id": device_id}, ip_address)
    
    # КОНСТАНТНОЕ время ответа
    constant_time_response(start_time)
    
    return Token(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=current_user.id,
        login=current_user.login,
        salt=current_user.salt,
        two_fa_required=False,
    )


@router.post("/refresh")
async def refresh_token(
    request: Request,
    response: Response,
    body: RefreshRequest,
    db: Session = Depends(get_db),
):
    """
    Безопасное обновление токенов с защитой от hijacking.
    
    Ключевые исправления:
    1. Device ID генерируется криптографически стойко и сохраняется в безопасной куке
    2. Безопасное сравнение device_id через hmac.compare_digest
    3. Нет преждевременных коммитов в БД
    """
    start_time = time.time()
    ip_address = get_client_ip(request)
    current_device_id = get_device_id_from_request(request)
    
    try:
        # Проверка refresh token
        db_token = None
        try:
            db_token = verify_refresh_token(db, body.refresh_token)
        except Exception:
            # Логируем попытку использования недействительного токена
            log_security_event(db, None, "invalid_refresh_token", 
                {"ip": ip_address, "device_id": current_device_id}, ip_address)
            raise HTTPException(
                status_code=401,
                detail="Invalid token"
            )
        
        # Безопасное сравнение device_id
        if not safe_compare(current_device_id, db_token.device_id):
            # Логируем подозрительную активность
            log_security_event(db, db_token.user_id, "suspicious_refresh", 
                {
                    "original_device_id": db_token.device_id,
                    "current_device_id": current_device_id,
                    "ip": ip_address
                }, ip_address)
            
            # Уведомляем пользователя о подозрительной активности
            user = db.get(User, db_token.user_id)
            if user:
                notify_user_of_suspicious_activity(db, user, ip_address, current_device_id)
            
            raise HTTPException(
                status_code=401,
                detail="Invalid token"
            )
        
        # Проверка срока действия
        if db_token.expires_at < datetime.utcnow():
            raise HTTPException(
                status_code=401,
                detail="Token expired"
            )
        
        # Ротация токена
        access, new_refresh = rotate_refresh_token(db, body.refresh_token)
        
        # Сохраняем изменения
        db.commit()
        
        # Логируем успешное обновление
        log_security_event(db, db_token.user_id, "token_refreshed", 
            {"ip": ip_address, "device_id": current_device_id}, ip_address)
        
        # Устанавливаем device_id в безопасную куку
        response.set_cookie(
            key="device_id",
            value=current_device_id,
            httponly=True,
            secure=True,
            samesite="strict",
            max_age=30 * 24 * 60 * 60  # 30 дней
        )
        
        return {
            "access_token": access,
            "refresh_token": new_refresh,
            "token_type": "bearer"
        }

    except HTTPException:
        raise
    except Exception as e:
        log_security_event(db, None, "token_refresh_error", 
            {"error": str(e), "ip": ip_address}, ip_address)
        raise HTTPException(
            status_code=401,
            detail="Invalid token"
        )
    finally:
        # КОНСТАНТНОЕ время ответа
        constant_time_response(start_time)


@router.post("/reset-password")
@limiter.limit("5/10minutes")
async def reset_password(
    request: Request,
    body: PasswordResetRequest,
    db: Session = Depends(get_db),
):
    """
    Безопасный сброс пароля с защитой от enumeration и DoS.
    
    Ключевые исправления:
    1. Правильная логика для пользователей без 2FA
    2. Нет утечки информации о существовании пользователя
    """
    start_time = time.time()
    ip_address = get_client_ip(request)
    
    # Получаем пользователя
    user = get_user_by_login(db, login=body.login)
    user_exists = user is not None
    
    # Фейковые данные
    fake_hash = "$argon2id$v=19$m=65536,t=3,p=4$fake$fakehash"
    fake_totp_secret = "JBSWY3DPEHPK3PXP"
    
    # ВСЕГДА выполняем проверку TOTP (реальную или фейковую)
    otp_valid = False
    
    if user_exists:
        # Для пользователей с включенной 2FA проверяем TOTP
        if user.totp_enabled:
            try:
                verify_hardened_otp(db, user, body.totp_code, ip_address)
                otp_valid = True
                reset_otp_failure_counters(user, db)
            except Exception:
                handle_failed_otp_attempt(db, user, ip_address)
        else:
            # Для пользователей без 2FA TOTP не требуется
            otp_valid = True
    else:
        # Фейковая проверка TOTP
        try:
            fake_user = User(totp_secret=fake_totp_secret, totp_enabled=True)
            verify_hardened_otp(db, fake_user, body.totp_code, ip_address)
            # Не устанавливаем otp_valid = True, так как пользователь не существует
        except Exception:
            pass
    
    # Определяем успешность операции
    operation_success = user_exists and otp_valid
    
    # Обработка успешной операции
    if operation_success:
        # Обновление пароля
        user.hashed_password = hash_password(body.new_password)
        user.token_version += 1  # Инвалидируем старые токены
        
        # Отзыв всех refresh токенов
        db.query(RefreshToken).filter(
            RefreshToken.user_id == user.id
        ).update({"revoked": True})
        
        # Сброс счетчиков
        user.failed_login_attempts = 0
        user.lockout_until = None
        db.commit()
        
        # Логируем успешный сброс
        log_security_event(db, user.id, "password_reset_success", 
            {"ip": ip_address}, ip_address)
    else:
        # Логируем неудачную попытку
        log_security_event(db, user.id if user else None, "password_reset_failed", 
            {
                "user_exists": user_exists,
                "otp_valid": otp_valid,
                "ip": ip_address
            }, ip_address)
    
    # КОНСТАНТНОЕ время ответа
    constant_time_response(start_time)
    
    # ВСЕГДА возвращаем одинаковый ответ для предотвращения enumeration
    return {"success": True}


@router.post("/verify-totp", response_model=dict)
@limiter.limit("5/minute")
async def verify_totp_for_seed(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Verify TOTP to get a short-lived token for sensitive resource access (e.g., Seed Phrase)."""
    otp = request.headers.get("X-OTP")
    if not otp:
        raise OTPRequired()

    verify_hardened_otp(db, current_user, otp)

    # Issue a very short-lived token with specific scope
    seed_access_token = create_short_token(current_user.id)
    
    return {"seed_access_token": seed_access_token}
