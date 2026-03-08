#!/usr/bin/env python3
"""
Creates an animated GIF demonstration of Zero Password Manager.
Uses Pillow to render terminal-style frames.
"""
from PIL import Image, ImageDraw, ImageFont
import json
import os

# ── Canvas settings ──────────────────────────────────────────────
W, H = 900, 600
BG      = (13, 17, 23)       # GitHub dark background
PANEL   = (22, 27, 34)       # sidebar / card
BORDER  = (48, 54, 61)       # subtle border
GREEN   = (63, 185, 80)      # success green
CYAN    = (88, 166, 255)     # accent blue
YELLOW  = (210, 153, 34)     # warning
RED     = (248, 81, 73)      # error
WHITE   = (230, 237, 243)    # main text
GREY    = (125, 133, 144)    # muted text
PURPLE  = (188, 140, 255)    # method badge
ORANGE  = (255, 166, 87)     # POST badge

FONT_PATH_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_PATH_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

try:
    font_sm   = ImageFont.truetype(FONT_PATH_MONO, 12)
    font_md   = ImageFont.truetype(FONT_PATH_MONO, 14)
    font_lg   = ImageFont.truetype(FONT_PATH_BOLD, 17)
    font_xl   = ImageFont.truetype(FONT_PATH_BOLD, 22)
    font_tiny = ImageFont.truetype(FONT_PATH_MONO, 11)
except:
    font_sm = font_md = font_lg = font_xl = font_tiny = ImageFont.load_default()


# ── Helper ────────────────────────────────────────────────────────
def rounded_rect(draw, xy, radius, fill, outline=None, width=1):
    x0, y0, x1, y1 = xy
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.ellipse([x0, y0, x0 + 2*radius, y0 + 2*radius], fill=fill)
    draw.ellipse([x1 - 2*radius, y0, x1, y0 + 2*radius], fill=fill)
    draw.ellipse([x0, y1 - 2*radius, x0 + 2*radius, y1], fill=fill)
    draw.ellipse([x1 - 2*radius, y1 - 2*radius, x1, y1], fill=fill)
    if outline:
        draw.rounded_rectangle(xy, radius, fill=None, outline=outline, width=width)


def method_color(method):
    return {
        "GET":    CYAN,
        "POST":   GREEN,
        "PUT":    YELLOW,
        "DELETE": RED,
        "PATCH":  PURPLE,
    }.get(method, WHITE)


def draw_base(step_num, total, title):
    img = Image.new("RGB", (W, H), BG)
    d   = ImageDraw.Draw(img)

    # ── Top bar ──────────────────────────────────────────────────
    d.rectangle([0, 0, W, 48], fill=(17, 21, 30))
    # logo dot
    d.ellipse([18, 14, 34, 30], fill=CYAN)
    d.text((42, 12), "Zero Password Manager", font=font_lg, fill=WHITE)
    # tagline
    d.text((42, 31), "Privacy-first self-hosted vault  •  AES-256-GCM  •  Argon2id  •  TOTP 2FA",
           font=font_tiny, fill=GREY)
    # step counter
    counter = f"Step {step_num}/{total}"
    cw = d.textlength(counter, font=font_sm)
    d.text((W - cw - 16, 16), counter, font=font_sm, fill=GREY)

    # ── Progress bar ─────────────────────────────────────────────
    bar_y = 48
    bar_w = int(W * step_num / total)
    d.rectangle([0, bar_y, W, bar_y + 3], fill=PANEL)
    d.rectangle([0, bar_y, bar_w, bar_y + 3], fill=CYAN)

    # ── Title card ───────────────────────────────────────────────
    d.rectangle([0, 51, W, 92], fill=PANEL)
    d.rectangle([0, 92, W, 93], fill=BORDER)
    d.text((20, 63), title, font=font_xl, fill=WHITE)

    return img, d


def draw_request_card(d, y, method, endpoint, body_lines, status_code, resp_lines):
    """Draw a request/response card."""
    card_x, card_w = 20, W - 40

    # ── Request row ──────────────────────────────────────────────
    mc = method_color(method)
    rounded_rect(d, [card_x, y, card_x + 56, y + 22], 4, fill=mc)
    d.text((card_x + 6, y + 4), method, font=font_sm, fill=BG)
    d.text((card_x + 64, y + 4), endpoint, font=font_md, fill=CYAN)

    # body lines
    by = y + 28
    for line in body_lines:
        d.text((card_x + 10, by), line, font=font_sm, fill=GREY)
        by += 16

    # ── Separator ────────────────────────────────────────────────
    sep_y = by + 4
    d.line([card_x, sep_y, card_x + card_w, sep_y], fill=BORDER, width=1)

    # ── Response row ─────────────────────────────────────────────
    resp_y = sep_y + 8
    sc = GREEN if status_code < 300 else (YELLOW if status_code < 400 else RED)
    status_txt = f"{status_code}"
    d.text((card_x + 10, resp_y), status_txt, font=font_lg, fill=sc)
    resp_y += 22
    for line in resp_lines:
        d.text((card_x + 10, resp_y), line, font=font_sm, fill=WHITE)
        resp_y += 16

    return resp_y + 8


# ─────────────────────────────────────────────────────────────────
# Frame definitions
# ─────────────────────────────────────────────────────────────────
STEPS = [
    {
        "title": "Backend Health Check",
        "method": "GET", "endpoint": "/health",
        "body": [],
        "status": 200,
        "resp": [
            '{ "status": "ok",',
            '  "security": "fortress",',
            '  "2fa": "enabled",',
            '  "architecture": "zero-knowledge" }',
        ],
        "note": "FastAPI backend running on port 3000",
    },
    {
        "title": "User Registration",
        "method": "POST", "endpoint": "/register",
        "body": ['{ "login": "alice", "password": "SecurePass123!" }'],
        "status": 201,
        "resp": [
            '{ "id": 1, "login": "alice",',
            '  "salt": "xH3mK9...base64...",',
            '  "totp_secret": "JBSWY3DPEHPK3PXP",',
            '  "totp_uri": "otpauth://totp/ZeroVault:alice?..." }',
        ],
        "note": "Password hashed with Argon2id  •  Salt generated for client KDF",
    },
    {
        "title": "2FA Setup & Confirmation",
        "method": "POST", "endpoint": "/2fa/confirm",
        "body": ['{ "user_id": 1, "code": "482931" }  ← from Google Authenticator'],
        "status": 200,
        "resp": ['{ "status": "2fa enabled" }'],
        "note": "TOTP secret bound  •  Replay protection active  •  Compatible with Google/Aegis",
    },
    {
        "title": "Secure Login with 2FA",
        "method": "POST", "endpoint": "/login",
        "body": [
            'username=alice  password=SecurePass123!',
            'Header: X-OTP: 482931',
        ],
        "status": 200,
        "resp": [
            '{ "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",',
            '  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",',
            '  "token_type": "bearer",',
            '  "user_id": 1, "login": "alice" }',
        ],
        "note": "JWT access token (15 min)  •  Refresh token (7 days)  •  Audit log written",
    },
    {
        "title": "Generate Secure Password",
        "method": "GET", "endpoint": "/api/generate-password?length=24",
        "body": [],
        "status": 200,
        "resp": ['{ "password": "tNxjBBc!LzQw@Rp#2KmV8sYe" }'],
        "note": "Cryptographically random  •  Letters + Digits + Symbols",
    },
    {
        "title": "Store Encrypted Password Entry",
        "method": "POST", "endpoint": "/passwords",
        "body": [
            '{ "site_url": "github.com",',
            '  "site_login": "dev@example.com",',
            '  "encrypted_payload": "base64(nonce+ciphertext+tag)",  ← AES-256-GCM',
            '  "has_2fa": true }',
        ],
        "status": 201,
        "resp": [
            '{ "id": 1, "site_url": "github.com",',
            '  "site_login": "dev@example.com",',
            '  "encrypted_payload": "...(only server sees ciphertext)...",',
            '  "created_at": "2026-03-08T22:10:01" }',
        ],
        "note": "Zero-Knowledge: server stores only ciphertext  •  Keys never leave device",
    },
    {
        "title": "List Vault Passwords",
        "method": "GET", "endpoint": "/passwords",
        "body": ['Header: Authorization: Bearer <token>'],
        "status": 200,
        "resp": [
            '[ { "id": 1, "site_url": "github.com",    "has_2fa": true  },',
            '  { "id": 2, "site_url": "gmail.com",     "has_2fa": false },',
            '  { "id": 3, "site_url": "aws.amazon.com","has_2fa": true  } ]',
        ],
        "note": "Rate-limited: 60 req/min  •  All payloads remain encrypted at rest",
    },
    {
        "title": "Audit & Security Log",
        "method": "GET", "endpoint": "/audit",
        "body": ['Header: Authorization: Bearer <token>'],
        "status": 200,
        "resp": [
            '[ { "event": "register",    "created_at": "2026-03-08T22:09:55" },',
            '  { "event": "2fa_enabled", "created_at": "2026-03-08T22:09:56" },',
            '  { "event": "login",       "ip_address": "127.0.0.1", ... },',
            '  { "event": "vault_read",  "created_at": "2026-03-08T22:10:05" } ]',
        ],
        "note": "Full audit trail  •  IP tracking  •  100 latest events per user",
    },
]

TOTAL = len(STEPS)

# ── Build frames ──────────────────────────────────────────────────
frames = []

for i, step in enumerate(STEPS, start=1):
    img, d = draw_base(i, TOTAL, step["title"])

    y = 105
    y = draw_request_card(
        d, y,
        step["method"], step["endpoint"],
        step["body"],
        step["status"], step["resp"],
    )

    # ── Note bar ─────────────────────────────────────────────────
    note_y = H - 44
    d.rectangle([0, note_y, W, H], fill=(17, 21, 30))
    d.rectangle([0, note_y, W, note_y + 1], fill=BORDER)
    d.text((20, note_y + 10), f"ℹ  {step['note']}", font=font_sm, fill=GREY)

    # Hold each frame for a while
    for _ in range(5):
        frames.append(img.copy())

# ── Outro frame ───────────────────────────────────────────────────
img, d = draw_base(TOTAL, TOTAL, "Demo Complete  ✓")
d.rectangle([0, 51, W, H - 44], fill=PANEL)

lines = [
    ("ZERO PASSWORD MANAGER", font_xl, CYAN,  (W//2, 120)),
    ("Privacy-first, self-hosted vault", font_lg, WHITE, (W//2, 160)),
    ("", font_sm, GREY, (W//2, 185)),
    ("AES-256-GCM Encryption",    font_md, GREEN,  (W//2, 210)),
    ("Argon2id Key Derivation",   font_md, GREEN,  (W//2, 232)),
    ("TOTP 2FA (Google Authenticator)", font_md, GREEN, (W//2, 254)),
    ("Zero-Knowledge Architecture",font_md, GREEN, (W//2, 276)),
    ("JWT Auth + Rate Limiting",  font_md, GREEN,  (W//2, 298)),
    ("", font_sm, GREY, (W//2, 318)),
    ("FastAPI  •  SQLite  •  Flutter", font_sm, GREY, (W//2, 335)),
    ("github.com/SoulNaturalist/zero_password_manager", font_sm, CYAN, (W//2, 357)),
]
for text, font, color, pos in lines:
    if text:
        tw = d.textlength(text, font=font)
        d.text((pos[0] - tw // 2, pos[1]), text, font=font, fill=color)

for _ in range(12):
    frames.append(img.copy())

# ── Save as GIF ───────────────────────────────────────────────────
out_path = "/home/user/zero_password_manager/assets/demo.gif"
os.makedirs(os.path.dirname(out_path), exist_ok=True)

frames[0].save(
    out_path,
    save_all=True,
    append_images=frames[1:],
    loop=0,
    duration=400,       # ms per frame
    optimize=False,
)
print(f"GIF saved: {out_path}  ({len(frames)} frames)")
print(f"File size: {os.path.getsize(out_path) / 1024:.1f} KB")
