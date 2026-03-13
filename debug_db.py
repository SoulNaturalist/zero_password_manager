from sqlalchemy import create_engine, inspect
from d.zero_password_manager.server.database import SQLALCHEMY_DATABASE_URL
import os

print(f"Database URL: {SQLALCHEMY_DATABASE_URL}")
# Ensure we are in the right directory
os.chdir(r"d:\zero_password_manager")

engine = create_engine(SQLALCHEMY_DATABASE_URL)
inspector = inspect(engine)

columns = [c['name'] for c in inspector.get_columns('users')]
print(f"Columns in 'users' table: {columns}")

required = ['failed_reset_attempts', 'reset_lockout_until', 'seed_phrase_encrypted', 'seed_phrase_last_viewed_at']
for col in required:
    if col in columns:
        print(f"  [OK]  {col}")
    else:
        print(f"  [MISSING] {col}")
