from ..exceptions import AppException


class InvalidCredentials(AppException):
    status_code = 401
    detail = "Incorrect login or password"
    headers = {"WWW-Authenticate": "Bearer"}


class WeakPassword(AppException):
    status_code = 400
    detail = (
        "Password must be at least 14 characters and include "
        "uppercase, lowercase, a digit, and a special character."
    )


class UserAlreadyExists(AppException):
    status_code = 400
    detail = "Login already registered"


class OTPRequired(AppException):
    status_code = 401
    detail = "OTP_REQUIRED"
    headers = {"X-2FA-Required": "true"}


class OTPInvalid(AppException):
    status_code = 403
    detail = "INVALID_OTP"


class OTPReplay(AppException):
    status_code = 403
    detail = "OTP_REPLAY_DETECTED"


class TwoFAAlreadyEnabled(AppException):
    status_code = 400
    detail = "2FA already enabled"


class TwoFANotSetUp(AppException):
    status_code = 400
    detail = "2FA not set up"


class InvalidOTPCode(AppException):
    status_code = 400
    detail = "Invalid OTP code"


class InvalidRefreshToken(AppException):
    status_code = 401
    detail = "Invalid refresh token"
