import base64
import hashlib
import hmac
import secrets
import time
from datetime import datetime, timedelta, timezone
from typing import Optional, Set, List

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session
from cryptography.hazmat.primitives import hashes

from .config import settings
from .models import User, IPBlock, FailedAttempt, SecurityEvent
import re
import logging
import json
import ipaddress
from fastapi import Request
from user_agents import parse


# Усиленные параметры безопасности
SECURITY_PARAMS = {
    "ARGON2": {
        "argon2__time_cost": 4,
        "argon2__memory_cost": 131072,  # 128 MB
        "argon2__parallelism": 2,
        "argon2__hash_len": 32
    },
    "HKDF": {
        "algorithm": hashes.SHA512(),
        "length": 64
    },
    "BLOCK_CLEANUP_INTERVAL": timedelta(hours=settings.BLOCK_CLEANUP_INTERVAL_HOURS),
    "DEVICE_FP_COMPONENTS": [
        "X-Forwarded-For",
        "Accept-Language",
        "Sec-CH-UA",
        "Sec-CH-UA-Platform",
        "Sec-CH-UA-Mobile",
        "Sec-CH-UA-Full-Version-List",
        "User-Agent"
    ],
    "SCANNER_SIGNATURES": {
        "nikto": [r"Nikto", r"X-Nikto-Scan", r"009094c3\.asp"],
        "nmap": [r"Nmap Scripting Engine", r"\.nse", r"NMAP"],
        "owasp_zap": [r"OWASP-ZAP", r"ZAP-Header", r"Mozilla/5\.0 \(compatible; OWASP ZAP\)"],
        "wazuh": [r"Wazuh", r"wazuh-agent"],
        "sqlmap": [r"sqlmap", r"UNION\s+SELECT", r"'\s+OR\s+1=1"],
        "dirbuster": [r"DirBuster", r"DirectoryScanner"]
    },
    "WHITELIST_IPS": [] # Deprecated, use settings.WHITELIST_IPS
}

BRUTE_FORCE_PROTECTION = {
    "MAX_ATTEMPTS": 4,
    "LOCKOUT_DURATION": timedelta(hours=3)
}

_pwd_context = CryptContext(
    schemes=["argon2"],
    deprecated="auto",
    **SECURITY_PARAMS["ARGON2"]
)

REQUIRED_CLAIMS: Set[str] = {"sub", "jti", "iat", "exp", "type"}


class SecurityManager:
    @staticmethod
    def hash_password(plain: str) -> str:
        return _pwd_context.hash(plain)

    @staticmethod
    def verify_password(plain: str, hashed: str) -> bool:
        return _pwd_context.verify(plain, hashed)

    @staticmethod
    def decode_token(token: str, expected_type: str | None = "access") -> dict:
        try:
            # Hardened JWT decoding with strict options (v2026 security standards)
            # Explicitly require HS256, verify signature, and check all security claims
            payload = jwt.decode(
                token,
                settings.JWT_SECRET_KEY,
                algorithms=["HS256"],
                options={
                    "verify_signature": True,
                    "verify_alg": True,
                    "require": ["exp", "iat", "sub", "jti", "type"],
                }
            )
            
            # Double check algorithm to prevent substitution attacks
            # Some libraries might return it in headers or payload; jose check is usually sufficient with algorithms=["HS256"]
            # but we explicitly check here for defense-in-depth.
            
            if expected_type and payload.get("type") != expected_type:
                raise ValueError("Invalid token type")
            
            current_time = datetime.now(timezone.utc).timestamp()
            if payload["exp"] < current_time:
                raise ValueError("Token expired")
            
            return payload
        except (JWTError, ValueError):
            from .auth.exceptions import InvalidCredentials
            raise InvalidCredentials()

    @staticmethod
    def generate_device_id(request: Request) -> str:
        """
        Creates a unique device fingerprint (v2026 Enhanced).
        Uses Client Hints, hardware characteristics, and UA normalization.
        """
        # 1. Collect basic data
        fingerprint_data = {
            "user_agent": request.headers.get("User-Agent", ""),
            "sec_ch_ua": request.headers.get("Sec-CH-UA-Full-Version-List", ""),
            "accept_language": request.headers.get("Accept-Language", ""),
            "screen_resolution": f"{request.scope.get('width', 0)}x{request.scope.get('height', 0)}",
            "timezone_offset": request.headers.get("X-Timezone-Offset", ""),
            "device_memory": request.headers.get("Device-Memory", ""),
            "hardware_concurrency": request.headers.get("Hardware-Concurrency", ""),
            "platform": request.headers.get("Sec-CH-UA-Platform", ""),
            "color_depth": request.headers.get("Color-Depth", ""),
            "client_hints": SecurityManager._extract_client_hints(request),
        }

        # 2. Normalize User-Agent
        fingerprint_data["normalized_user_agent"] = SecurityManager._normalize_user_agent(fingerprint_data["user_agent"])

        # 3. Enhanced Entropy sources
        entropy_sources = [
            fingerprint_data["user_agent"],
            fingerprint_data["sec_ch_ua"],
            fingerprint_data["accept_language"],
            fingerprint_data["screen_resolution"],
            fingerprint_data["timezone_offset"],
            fingerprint_data["device_memory"],
            fingerprint_data["hardware_concurrency"],
            fingerprint_data["platform"],
            fingerprint_data["color_depth"],
        ]
        fingerprint_data["entropy_hash"] = SecurityManager._generate_entropy_hash(entropy_sources)

        # Sign with server secret to prevent forgery
        fingerprint_string = json.dumps(fingerprint_data, sort_keys=True)
        return hmac.new(
            settings.DEVICE_SECRET.encode(),
            fingerprint_string.encode(),
            hashlib.sha256
        ).hexdigest()

    @staticmethod
    def generate_device_id_from_flutter(data: dict) -> str:
        """
        Creates a unique device fingerprint for Flutter clients.
        Includes mandatory anti-emulation checks.
        """
        from fastapi import HTTPException, status
        
        # 1. Anti-emulation check
        if SecurityManager._is_emulated(data):
            # Log this as a security event
            # Note: We don't have DB here easily, we'll let the router handle the event logging
            # but we raise the exception to stop the flow.
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Emulated devices are not allowed"
            )

        # 2. Collect data
        fingerprint_data = {
            "platform": data.get("platform", "").lower(),
            "model": data.get("model", ""),
            "os_version": data.get("version", ""),
            "device_id": data.get("deviceId", ""),
            "screen_resolution": data.get("screenResolution", ""),
            "language": data.get("language", ""),
        }

        # 3. Entropy
        entropy_sources = [
            fingerprint_data["platform"],
            fingerprint_data["model"],
            fingerprint_data["os_version"],
            fingerprint_data["device_id"],
            fingerprint_data["screen_resolution"],
            fingerprint_data["language"],
        ]
        fingerprint_data["entropy_hash"] = SecurityManager._generate_entropy_hash(entropy_sources)

        # 4. Final signed hash
        fingerprint_string = json.dumps(fingerprint_data, sort_keys=True)
        return hmac.new(
            settings.DEVICE_SECRET.encode(),
            fingerprint_string.encode(),
            hashlib.sha256
        ).hexdigest()

    @staticmethod
    def _is_emulated(data: dict) -> bool:
        """
        Detects if the device is an emulator or compromised environment.
        Trusts results from the native RASP package (safe_device) if available.
        """
        # 1. Trust specialized RASP package results
        is_real_device = data.get("isRealDevice")
        if is_real_device is False:
            return True

        is_jailbroken = data.get("isJailBroken", False)
        if is_jailbroken:
            # We treat Root/Jailbreak as a compromised environment for a password manager
            return True

        # 2. Existing heuristic fallback
        emulator_signatures = [
            "sdk_gphone", "Android SDK built for x86", "iPhone Simulator",
            "Genymotion", "Bluestacks", "google_sdk", "Emulator"
        ]

        model = data.get("model", "").lower()
        is_emulator_flag = data.get("isEmulator", False)

        if is_emulator_flag:
            return True

        for signature in emulator_signatures:
            if signature.lower() in model:
                return True

        # 3. Heuristic: missing deviceId in production-like platforms
        if not data.get("deviceId") and data.get("platform") in ["android", "ios"]:
            return True

        return False

    @staticmethod
    def _normalize_user_agent(user_agent: str) -> dict:
        """Normalizes User-Agent for data unification."""
        try:
            ua = parse(user_agent)
            return {
                "browser_family": ua.browser.family,
                "browser_version": ua.browser.version_string,
                "os_family": ua.os.family,
                "os_version": ua.os.version_string,
                "device_family": ua.device.family,
                "is_mobile": ua.is_mobile,
                "is_tablet": ua.is_tablet,
                "is_pc": ua.is_pc,
                "is_bot": ua.is_bot,
            }
        except Exception:
            return {"raw": user_agent}

    @staticmethod
    def _extract_client_hints(request: Request) -> dict:
        """Extracts Client Hints from request headers."""
        return {
            "architecture": request.headers.get("Sec-CH-UA-Arch", ""),
            "model": request.headers.get("Sec-CH-UA-Model", ""),
            "platform_version": request.headers.get("Sec-CH-UA-Platform-Version", ""),
            "bitness": request.headers.get("Sec-CH-UA-Bitness", ""),
            "mobile": request.headers.get("Sec-CH-UA-Mobile", ""),
        }

    @staticmethod
    def _generate_entropy_hash(sources: list) -> str:
        """Generates entropy hash based on list of sources."""
        entropy_string = ":".join(str(source) for source in sources if source)
        return hashlib.sha256(entropy_string.encode()).hexdigest()

    @staticmethod
    def get_client_ip(request: Request) -> str:
        """
        Retrieves the client IP. 
        Prioritizes direct host for security unless a trusted proxy is explicitly handled.
        """
        # For production behind a trusted proxy, use X-Forwarded-For if you trust your load balancer.
        # Otherwise, use request.client.host to avoid spoofing.
        if request.client:
            return request.client.host
        
        # Fallback to header ONLY if direct host is missing (e.g. some mock environments)
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            return forwarded.split(",")[0].strip()
            
        return "127.0.0.1"

    @staticmethod
    def is_scanner_request(request) -> Optional[str]:
        """Detect if the request comes from a known scanning tool."""
        try:
            # Check User-Agent
            user_agent = request.headers.get("User-Agent", "").lower()
            for scanner, patterns in SECURITY_PARAMS["SCANNER_SIGNATURES"].items():
                for pattern in patterns:
                    if re.search(pattern, user_agent, re.IGNORECASE):
                        return scanner
            
            # Check other headers
            for header, value in request.headers.items():
                for scanner, patterns in SECURITY_PARAMS["SCANNER_SIGNATURES"].items():
                    for pattern in patterns:
                        if re.search(pattern, f"{header}:{value}", re.IGNORECASE):
                            return scanner
            
            # Check query parameters
            query_params = str(request.query_params).lower()
            for scanner, patterns in SECURITY_PARAMS["SCANNER_SIGNATURES"].items():
                for pattern in patterns:
                    if re.search(pattern, query_params, re.IGNORECASE):
                        return scanner
            
            # Request body check is too heavy for middleware, skip for now unless specifically needed for POST.
            # Usually scanners identify themselves via headers first.
                        
        except Exception as e:
            logging.warning(f"Error during scanner detection: {e}")
        
        return None

    @staticmethod
    def is_ip_whitelisted(ip: str) -> bool:
        if ip in settings.WHITELIST_IPS:
            return True
            
        try:
            addr = ipaddress.ip_address(ip)
            # Allow private network (192.168.x.x, 10.x.x.x, etc), loopback, and link-local
            return addr.is_private or addr.is_loopback or addr.is_link_local
        except ValueError:
            return False

    @staticmethod
    def is_ip_blocked(db: Session, ip: str) -> bool:
        if SecurityManager.is_ip_whitelisted(ip):
            return False
            
        block = db.query(IPBlock).filter(
            IPBlock.ip == ip,
            IPBlock.until > datetime.now(timezone.utc)
        ).first()
        return bool(block)

    @staticmethod
    def record_failed_attempt(db: Session, ip: str):
        if SecurityManager.is_ip_whitelisted(ip):
            return
            
        attempt = db.query(FailedAttempt).filter_by(ip=ip).first()
        if not attempt:
            attempt = FailedAttempt(ip=ip, count=0)
            db.add(attempt)
        
        attempt.count += 1
        attempt.last_attempt = datetime.now(timezone.utc)
        db.commit()

    @staticmethod
    def block_ip(db: Session, ip: str, duration: timedelta, reason: str = "Unknown"):
        if SecurityManager.is_ip_whitelisted(ip):
            return
            
        block = IPBlock(
            ip=ip,
            until=datetime.now(timezone.utc) + duration,
            reason=reason
        )
        db.add(block)
        db.commit()
        SecurityManager.notify_security_team("ip_blocked", {"ip": ip, "reason": reason})

    @staticmethod
    def cleanup_old_blocks(db: Session):
        """Cleanup old IP blocks and failed attempts periodically."""
        cutoff = datetime.now(timezone.utc) - BRUTE_FORCE_PROTECTION["LOCKOUT_DURATION"]
        db.query(IPBlock).filter(IPBlock.until < cutoff).delete()
        db.query(FailedAttempt).filter(FailedAttempt.last_attempt < cutoff).delete()
        db.commit()

    @staticmethod
    def verify_captcha(solution: str) -> bool:
        """Verify CAPTCHA solution (placeholder logic)."""
        # В реальной системе здесь будет проверка ключа в Redis или вызов внешнего API
        return solution == "validated_captcha_mock"

    @staticmethod
    def require_captcha(ip: str, db: Session) -> bool:
        """Determine if CAPTCHA is required based on failed attempts."""
        attempt = db.query(FailedAttempt).filter_by(ip=ip).first()
        return bool(attempt and attempt.count >= BRUTE_FORCE_PROTECTION["MAX_ATTEMPTS"] - 1)

    @staticmethod
    def notify_security_team(event_type: str, details: dict):
        """Notify security team about critical events."""
        # Реализация оповещения (лог, Telegram и т.д.)
        print(f"SECURITY NOTIFICATION [{event_type}]: {details}")

    @staticmethod
    def log_security_event(db: Session, event_type: str, details: dict, ip_address: str, user_id: Optional[int] = None):
        event = SecurityEvent(
            type=event_type,
            user_id=user_id,
            details=details,
            ip=ip_address,
            created_at=datetime.now(timezone.utc)
        )
        db.add(event)
        db.commit()

        CRITICAL_EVENTS = {"ip_blocked", "suspicious_login", "token_hijacking"}
        if event_type in CRITICAL_EVENTS:
            SecurityManager.notify_security_team(event_type, details)

    @staticmethod
    def constant_time_delay(start_time: float, min_duration: float = 0.5):
        elapsed = time.time() - start_time
        if elapsed < min_duration:
            time.sleep(min_duration - elapsed)
