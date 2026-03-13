from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from .models import User
from .config import settings
import time


class SecurityManager:
    @staticmethod
    def get_lockout_duration(failures: int) -> int:
        """Return lockout duration in minutes based on failure count."""
        if failures < 5:
            return 0
        if failures < 10:
            return 10  # 10 minutes
        if failures < 20:
            return 60  # 1 hour
        return 1440  # 24 hours

    @staticmethod
    def is_locked_out(user: User) -> bool:
        """Check if the user is currently locked out from password resets."""
        if not user.reset_lockout_until:
            return False
        return datetime.now(timezone.utc) < user.reset_lockout_until

    @staticmethod
    def handle_failure(db: Session, user: User):
        """Register a failed attempt and update lockout status."""
        user.failed_reset_attempts += 1
        duration = SecurityManager.get_lockout_duration(user.failed_reset_attempts)
        if duration > 0:
            user.reset_lockout_until = datetime.now(timezone.utc) + timedelta(minutes=duration)
        db.commit()

    @staticmethod
    def handle_success(db: Session, user: User):
        """Reset failure counter on success."""
        user.failed_reset_attempts = 0
        user.reset_lockout_until = None
        db.commit()

    @staticmethod
    def constant_time_delay():
        """Sleep for a small random duration to prevent timing attacks."""
        # In a real high-load scenario, this might be handled by an orchestrator,
        # but for this app, a small sleep is a baseline.
        time.sleep(0.1)
