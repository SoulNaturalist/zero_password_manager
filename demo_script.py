#!/usr/bin/env python3
"""
Zero Password Manager - Demo Script
Records all API interactions and outputs structured results for GIF generation.
"""
import requests
import pyotp
import base64
import json
import time
import os

BASE_URL = "http://localhost:3000"
DEMO_LOGIN = "demo_user"
DEMO_PASSWORD = "SecurePass123!"

results = []

def step(title, method, endpoint, **kwargs):
    url = f"{BASE_URL}{endpoint}"
    try:
        resp = getattr(requests, method)(url, **kwargs)
        data = resp.json() if resp.text else {}
        results.append({
            "title": title,
            "method": method.upper(),
            "endpoint": endpoint,
            "status": resp.status_code,
            "response": data,
            "ok": resp.status_code < 400
        })
        return resp.status_code, data
    except Exception as e:
        results.append({
            "title": title,
            "method": method.upper(),
            "endpoint": endpoint,
            "status": 0,
            "response": {"error": str(e)},
            "ok": False
        })
        return 0, {}

# Step 1: Health Check
print("[1/8] Health Check...")
status, data = step("Health Check", "get", "/health")
print(f"  -> {status}: {data}")

# Step 2: Register
print("[2/8] Register new user...")
status, reg_data = step("Register User", "post", "/register",
    json={"login": DEMO_LOGIN, "password": DEMO_PASSWORD})
print(f"  -> {status}: id={reg_data.get('id')}, totp_secret generated")

if status != 201:
    print(f"  ERROR: {reg_data}")
    # Try with different name if already exists
    import random
    DEMO_LOGIN = f"demo_{random.randint(1000,9999)}"
    status, reg_data = step("Register User (retry)", "post", "/register",
        json={"login": DEMO_LOGIN, "password": DEMO_PASSWORD})
    print(f"  -> Retry {status}: id={reg_data.get('id')}")

user_id = reg_data.get("id")
totp_secret = reg_data.get("totp_secret")

# Step 3: Confirm 2FA
print("[3/8] Confirm 2FA setup...")
totp = pyotp.TOTP(totp_secret)
otp_code = totp.now()
status, data = step("Confirm 2FA", "post", "/2fa/confirm",
    json={"user_id": user_id, "code": otp_code})
print(f"  -> {status}: {data}")

# Step 4: Login
print("[4/8] Login...")
time.sleep(1)  # brief pause
status, login_data = step("Login", "post", "/login",
    data={"username": DEMO_LOGIN, "password": DEMO_PASSWORD},
    headers={"Content-Type": "application/x-www-form-urlencoded"})
print(f"  -> {status}: access_token={'present' if login_data.get('access_token') else 'missing'}")

token = login_data.get("access_token")
auth_headers = {"Authorization": f"Bearer {token}"}

# Step 5: Generate Password
print("[5/8] Generate secure password...")
status, gen_data = step("Generate Password", "get", "/api/generate-password?length=20")
print(f"  -> {status}: {gen_data.get('password', '')[:10]}...")

# Step 6: Create Password Entry (encrypted payload simulation)
print("[6/8] Create password entry (github.com)...")
# Simulate client-side AES-256-GCM encryption
import secrets as sec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
nonce = sec.token_bytes(12)
key = sec.token_bytes(32)
plaintext = json.dumps({"password": "MyGitHubP@ss2024!", "notes": "Work account"})
ciphertext = AESGCM(key).encrypt(nonce, plaintext.encode(), None)
encrypted_payload = base64.b64encode(nonce + ciphertext).decode()

status, pw_data = step("Add Password (GitHub)", "post", "/passwords",
    json={
        "site_url": "github.com",
        "site_login": "dev@example.com",
        "encrypted_payload": encrypted_payload,
        "notes_encrypted": None,
        "has_2fa": True,
        "has_seed_phrase": False
    },
    headers=auth_headers)
print(f"  -> {status}: id={pw_data.get('id')}, site={pw_data.get('site_url')}")

# Step 7: Add another password
print("[7/8] Create password entry (gmail.com)...")
nonce2 = sec.token_bytes(12)
key2 = sec.token_bytes(32)
plaintext2 = json.dumps({"password": "G00gleSecure#99", "notes": "Personal email"})
ciphertext2 = AESGCM(key2).encrypt(nonce2, plaintext2.encode(), None)
encrypted_payload2 = base64.b64encode(nonce2 + ciphertext2).decode()

status, pw_data2 = step("Add Password (Gmail)", "post", "/passwords",
    json={
        "site_url": "gmail.com",
        "site_login": "user@gmail.com",
        "encrypted_payload": encrypted_payload2,
        "notes_encrypted": None,
        "has_2fa": False,
        "has_seed_phrase": False
    },
    headers=auth_headers)
print(f"  -> {status}: id={pw_data2.get('id')}, site={pw_data2.get('site_url')}")

# Step 8: List Passwords
print("[8/8] List all passwords...")
status, pw_list = step("List Passwords", "get", "/passwords", headers=auth_headers)
count = len(pw_list) if isinstance(pw_list, list) else 0
print(f"  -> {status}: {count} passwords stored (encrypted)")

# Audit logs
status, audit = step("View Audit Log", "get", "/audit", headers=auth_headers)
audit_count = len(audit) if isinstance(audit, list) else 0
print(f"  -> Audit: {audit_count} events logged")

# Save results for GIF generation
with open("/tmp/demo_results.json", "w") as f:
    json.dump(results, f, indent=2, default=str)

print("\n=== DEMO COMPLETE ===")
all_ok = all(r["ok"] for r in results)
print(f"All steps passed: {all_ok}")
for r in results:
    icon = "✓" if r["ok"] else "✗"
    print(f"  {icon} [{r['status']}] {r['method']} {r['endpoint']} - {r['title']}")
