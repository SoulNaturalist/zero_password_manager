import sqlite3
import os

db_paths = [
    r"d:\zero_password_manager\zero_vault.db",
    r"d:\zero_password_manager\server\zero_vault.db"
]

migrations = [
    "ALTER TABLE users ADD COLUMN failed_reset_attempts INTEGER DEFAULT 0",
    "ALTER TABLE users ADD COLUMN reset_lockout_until DATETIME",
    "ALTER TABLE users ADD COLUMN seed_phrase_encrypted VARCHAR",
    "ALTER TABLE users ADD COLUMN seed_phrase_last_viewed_at DATETIME",
    "ALTER TABLE users ADD COLUMN token_version INTEGER DEFAULT 0",
    "ALTER TABLE folders ADD COLUMN is_hidden BOOLEAN DEFAULT 0"
]

for db_path in db_paths:
    if not os.path.exists(db_path):
        print(f"Skipping: {db_path} (does not exist)")
        continue

    print(f"Migrating: {db_path}")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for sql in migrations:
        try:
            print(f"  Executing: {sql}")
            cursor.execute(sql)
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e).lower():
                print(f"    Column already exists, skipping.")
            else:
                print(f"    Error: {e}")

    conn.commit()
    conn.close()

print("Migration flow completed.")
