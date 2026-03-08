#!/usr/bin/env python3
"""
Flutter UI Demo GIF Generator
Recreates the Zero Password Manager app screens as pixel-accurate mockups
using exact colors, layouts and design from lib/theme/colors.dart and screen files.
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math
import os

# ─── FONTS ───────────────────────────────────────────────────────────────────
FONT_DIR = "/usr/share/fonts/truetype/dejavu"
FONT_REGULAR = ImageFont.truetype(f"{FONT_DIR}/DejaVuSans.ttf", 16)
FONT_BOLD    = ImageFont.truetype(f"{FONT_DIR}/DejaVuSans-Bold.ttf", 16)

def font(size, bold=False):
    path = f"{FONT_DIR}/DejaVuSans-Bold.ttf" if bold else f"{FONT_DIR}/DejaVuSans.ttf"
    return ImageFont.truetype(path, size)

# ─── THEMES ──────────────────────────────────────────────────────────────────
THEMES = {
    "dark": {
        "bg":      (26, 20, 46),
        "button":  (93, 82, 210),
        "input":   (34, 25, 55),
        "text":    (255, 255, 255),
        "accent":  (139, 126, 216),
        "surface": (42, 31, 61),
        "secondary":(64, 58, 92),
        "subtext": (160, 150, 200),
        "error":   (231, 76, 60),
        "appbar":  (20, 14, 38),
        "name":    "Тёмная",
    },
    "cyberpunk": {
        "bg":      (10, 10, 10),
        "button":  (0, 255, 255),
        "input":   (26, 26, 26),
        "text":    (0, 255, 255),
        "accent":  (255, 0, 128),
        "surface": (21, 21, 21),
        "secondary":(128, 0, 255),
        "subtext": (0, 200, 200),
        "error":   (255, 0, 64),
        "appbar":  (5, 5, 5),
        "name":    "Cyberpunk",
    },
    "glass": {
        "bg":      (30, 30, 46),
        "button":  (137, 180, 250),
        "input":   (49, 50, 68),
        "text":    (205, 214, 244),
        "accent":  (180, 190, 254),
        "surface": (24, 24, 37),
        "secondary":(147, 153, 178),
        "subtext": (147, 153, 178),
        "error":   (243, 139, 168),
        "appbar":  (24, 24, 37),
        "name":    "Glassmorphism",
    },
}

# ─── CANVAS DIMENSIONS ───────────────────────────────────────────────────────
GIF_W, GIF_H = 520, 1000     # total GIF frame size
PHONE_W, PHONE_H = 420, 910  # phone outline
PHONE_X = (GIF_W - PHONE_W) // 2
PHONE_Y = (GIF_H - PHONE_H) // 2
SCREEN_X = PHONE_X + 10
SCREEN_Y = PHONE_Y + 10
SCREEN_W = PHONE_W - 20
SCREEN_H = PHONE_H - 20
CORNER_R = 36

# ─── HELPERS ─────────────────────────────────────────────────────────────────

def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def alpha_blend(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

def draw_rounded_rect(draw, xy, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    if fill:
        draw.rectangle([x0+r, y0, x1-r, y1], fill=fill)
        draw.rectangle([x0, y0+r, x1, y1-r], fill=fill)
        draw.ellipse([x0, y0, x0+2*r, y0+2*r], fill=fill)
        draw.ellipse([x1-2*r, y0, x1, y0+2*r], fill=fill)
        draw.ellipse([x0, y1-2*r, x0+2*r, y1], fill=fill)
        draw.ellipse([x1-2*r, y1-2*r, x1, y1], fill=fill)
    if outline:
        draw.arc([x0, y0, x0+2*r, y0+2*r], 180, 270, fill=outline, width=width)
        draw.arc([x1-2*r, y0, x1, y0+2*r], 270, 360, fill=outline, width=width)
        draw.arc([x0, y1-2*r, x0+2*r, y1], 90, 180, fill=outline, width=width)
        draw.arc([x1-2*r, y1-2*r, x1, y1], 0, 90, fill=outline, width=width)
        draw.line([x0+r, y0, x1-r, y0], fill=outline, width=width)
        draw.line([x0+r, y1, x1-r, y1], fill=outline, width=width)
        draw.line([x0, y0+r, x0, y1-r], fill=outline, width=width)
        draw.line([x1, y0+r, x1, y1-r], fill=outline, width=width)

def draw_gradient_rect(img, xy, c1, c2, vertical=True):
    x0, y0, x1, y1 = xy
    draw = ImageDraw.Draw(img)
    if vertical:
        for y in range(y0, y1+1):
            t = (y - y0) / max(y1 - y0, 1)
            c = alpha_blend(c1, c2, t)
            draw.line([(x0, y), (x1, y)], fill=c)
    else:
        for x in range(x0, x1+1):
            t = (x - x0) / max(x1 - x0, 1)
            c = alpha_blend(c1, c2, t)
            draw.line([(x, y0), (x, y1)], fill=c)

def draw_gradient_rounded(img, xy, r, c1, c2):
    """Draw a rounded rectangle with vertical gradient."""
    tmp = Image.new("RGBA", img.size, (0, 0, 0, 0))
    x0, y0, x1, y1 = xy
    for y in range(y0, y1+1):
        t = (y - y0) / max(y1 - y0, 1)
        c = alpha_blend(c1, c2, t)
        tmp_draw = ImageDraw.Draw(tmp)
        # horizontal strip
        lx0, lx1 = x0, x1
        if y < y0 + r:
            dr = r - (y - y0)
            angle = math.acos(min(dr / r, 1.0))
            dx = int(r * math.sin(angle))
            lx0 = x0 + r - dx
            lx1 = x1 - r + dx
        elif y > y1 - r:
            dr = r - (y1 - y)
            angle = math.acos(min(dr / r, 1.0))
            dx = int(r * math.sin(angle))
            lx0 = x0 + r - dx
            lx1 = x1 - r + dx
        if lx1 > lx0:
            tmp_draw.line([(lx0, y), (lx1, y)], fill=c + (255,))
    img.paste(tmp, mask=tmp.split()[3])

def centered_text(draw, y, text, fnt, color, width=SCREEN_W, ox=SCREEN_X):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    tw = bbox[2] - bbox[0]
    x = ox + (width - tw) // 2
    draw.text((x, y), text, font=fnt, fill=color)
    return bbox[3] - bbox[1]  # return height

def text_h(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return bbox[3] - bbox[1]

def text_w(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return bbox[2] - bbox[0]

# ─── PHONE FRAME ─────────────────────────────────────────────────────────────

def make_base_frame(bg_color):
    """Create a frame with phone outline and background."""
    img = Image.new("RGB", (GIF_W, GIF_H), (18, 18, 24))  # outer bg
    draw = ImageDraw.Draw(img)

    # Phone body gradient
    draw_gradient_rect(img, [PHONE_X, PHONE_Y, PHONE_X+PHONE_W, PHONE_Y+PHONE_H],
                       (45, 45, 55), (30, 30, 40))

    # Screen background
    draw_gradient_rect(img, [SCREEN_X, SCREEN_Y, SCREEN_X+SCREEN_W, SCREEN_Y+SCREEN_H],
                       bg_color, tuple(max(0, c-15) for c in bg_color))

    # Phone frame border
    draw_rounded_rect(draw, [PHONE_X, PHONE_Y, PHONE_X+PHONE_W, PHONE_Y+PHONE_H],
                      CORNER_R+2, outline=(80, 80, 100), width=3)

    # Screen corners clip (subtle inner rounding)
    draw_rounded_rect(draw, [SCREEN_X, SCREEN_Y, SCREEN_X+SCREEN_W, SCREEN_Y+SCREEN_H],
                      CORNER_R, outline=(50, 50, 65), width=1)

    # Notch (pill shaped, top center)
    notch_w, notch_h = 100, 20
    nx = SCREEN_X + (SCREEN_W - notch_w) // 2
    ny = SCREEN_Y + 4
    draw_rounded_rect(draw, [nx, ny, nx+notch_w, ny+notch_h], 10, fill=(18, 18, 24))

    # Side button (right)
    draw.rectangle([PHONE_X+PHONE_W-2, PHONE_Y+120, PHONE_X+PHONE_W+3, PHONE_Y+180],
                   fill=(60, 60, 75))
    # Volume buttons (left)
    draw.rectangle([PHONE_X-3, PHONE_Y+100, PHONE_X+2, PHONE_Y+140], fill=(60, 60, 75))
    draw.rectangle([PHONE_X-3, PHONE_Y+155, PHONE_X+2, PHONE_Y+195], fill=(60, 60, 75))

    return img

def draw_status_bar(draw, theme):
    """Draw status bar at top of screen."""
    sy = SCREEN_Y + 8
    # Time
    draw.text((SCREEN_X + 16, sy), "22:10",
              font=font(13, bold=True), fill=theme["text"])
    # Signal dots
    sx = SCREEN_X + SCREEN_W - 80
    for i in range(4):
        h = 6 + i * 3
        c = theme["text"] if i < 3 else theme["secondary"]
        draw.rectangle([sx + i*10, sy+12-h, sx+i*10+6, sy+12], fill=c)
    # WiFi
    draw.text((SCREEN_X + SCREEN_W - 40, sy), "WiFi",
              font=font(11), fill=theme["text"])
    # Battery
    bx = SCREEN_X + SCREEN_W - 18
    draw.rectangle([bx, sy, bx+14, sy+9], outline=theme["text"], width=1)
    draw.rectangle([bx+14, sy+3, bx+16, sy+6], fill=theme["text"])
    draw.rectangle([bx+1, sy+1, bx+11, sy+8], fill=theme["button"])

STATUS_H = 30  # height of status bar area

# ─── SCREEN RENDERERS ────────────────────────────────────────────────────────

def draw_input_field(draw, img, x, y, w, h, hint, theme, value=None, is_password=False):
    """Draw a text input field."""
    bg = theme["input"]
    border = theme["secondary"]
    draw_rounded_rect(draw, [x, y, x+w, y+h], 12, fill=bg, outline=border, width=1)
    txt = value if value else hint
    color = theme["text"] if value else theme["subtext"]
    if is_password and value:
        txt = "•" * len(value)
    draw.text((x+16, y + (h - 18)//2), txt, font=font(16), fill=color)

def draw_button(draw, img, x, y, w, h, label, theme):
    """Draw a primary button with gradient."""
    bc = theme["button"]
    c1 = bc
    c2 = tuple(max(0, c-40) for c in bc)
    draw_gradient_rounded(img, [x, y, x+w, y+h], 14, c1, c2)
    # Subtle overlay
    draw_rounded_rect(draw, [x, y, x+w, y+h], 14,
                      outline=tuple(min(255, c+40) for c in bc), width=1)
    # Text
    f = font(18, bold=True)
    bbox = draw.textbbox((0, 0), label, font=f)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    tx = x + (w - tw) // 2
    ty = y + (h - th) // 2
    draw.text((tx, ty), label, font=f, fill=(255, 255, 255))

def draw_icon_circle(draw, x, y, r, bg_color, icon_char, icon_color=(255,255,255)):
    """Draw a circle icon container."""
    draw.ellipse([x-r, y-r, x+r, y+r], fill=bg_color)
    f = font(r, bold=True)
    bbox = draw.textbbox((0, 0), icon_char, font=f)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    draw.text((x - tw//2, y - th//2 - 2), icon_char, font=f, fill=icon_color)

def draw_icon_box(draw, img, cx, cy, size, theme, icon_char):
    """Draw a gradient square icon container (like Flutter's BoxDecoration)."""
    half = size // 2
    x0, y0 = cx - half, cy - half
    x1, y1 = cx + half, cy + half
    bc = theme["button"]
    c1 = tuple(min(255, c+30) for c in bc)
    c2 = tuple(max(0, c-20) for c in bc)
    draw_gradient_rounded(img, [x0, y0, x1, y1], 20, c1, c2)
    # Glow effect
    draw_rounded_rect(draw, [x0, y0, x1, y1], 20,
                      outline=tuple(min(255, c+80) for c in bc) + (100,), width=1)
    f = font(size // 2, bold=True)
    bbox = draw.textbbox((0, 0), icon_char, font=f)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    draw.text((cx - tw//2, cy - th//2 - 2), icon_char, font=f, fill=(255, 255, 255))

def draw_appbar(draw, img, title, theme, show_back=False):
    """Draw app bar at top of screen content."""
    bar_y = SCREEN_Y + STATUS_H
    bar_h = 52
    bar_bg = theme["appbar"]
    # AppBar background
    draw.rectangle([SCREEN_X, bar_y, SCREEN_X+SCREEN_W, bar_y+bar_h], fill=bar_bg)
    # Subtle bottom border
    draw.line([SCREEN_X, bar_y+bar_h, SCREEN_X+SCREEN_W, bar_y+bar_h],
              fill=theme["secondary"], width=1)
    if show_back:
        draw.text((SCREEN_X+16, bar_y+14), "<", font=font(22, bold=True), fill=theme["button"])
    f = font(20, bold=True)
    bbox = draw.textbbox((0, 0), title, font=f)
    tw = bbox[2] - bbox[0]
    tx = SCREEN_X + (SCREEN_W - tw) // 2
    draw.text((tx, bar_y+14), title, font=f, fill=theme["accent"])
    return bar_y + bar_h  # returns Y where content starts


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 1: SPLASH
# ═══════════════════════════════════════════════════════════════════════════════

def screen_splash(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    draw_status_bar(draw, theme)

    cy = SCREEN_Y + SCREEN_H // 2

    # Large logo box
    logo_size = 120
    lx = SCREEN_X + SCREEN_W // 2
    ly = cy - 50
    draw_icon_box(draw, img, lx, ly, logo_size, theme, "Z")

    # Neon glow effect around logo
    bc = theme["button"]
    for radius in [70, 80, 90]:
        alpha = max(0, 30 - (radius - 60))
        draw.ellipse(
            [lx-radius, ly-radius, lx+radius, ly+radius],
            outline=bc + (alpha,) if len(bc) == 3 else bc,
        )

    # "ZERO" title
    y = ly + logo_size // 2 + 24
    f = font(52, bold=True)
    bbox = draw.textbbox((0, 0), "ZERO", font=f)
    tw = bbox[2] - bbox[0]
    tx = SCREEN_X + (SCREEN_W - tw) // 2
    draw.text((tx+2, y+2), "ZERO", font=f, fill=tuple(max(0, c-80) for c in bc))  # shadow
    draw.text((tx, y), "ZERO", font=f, fill=bc)

    # Subtitle
    y += 60
    centered_text(draw, y, "Менеджер паролей", font(16), theme["subtext"])

    # Animated dots (static)
    dot_y = y + 60
    for i in range(3):
        dx = SCREEN_X + SCREEN_W//2 - 20 + i * 20
        c = theme["button"] if i == 1 else theme["secondary"]
        draw.ellipse([dx-5, dot_y-5, dx+5, dot_y+5], fill=c)

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 2: LOGIN
# ═══════════════════════════════════════════════════════════════════════════════

def screen_login(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    draw_status_bar(draw, theme)

    content_y = SCREEN_Y + STATUS_H + 40
    cx = SCREEN_X + SCREEN_W // 2

    # Icon box
    draw_icon_box(draw, img, cx, content_y + 40, 80, theme, "S")  # Security shield

    # "ZERO" title
    y = content_y + 100
    f_big = font(48, bold=True)
    bbox = draw.textbbox((0, 0), "ZERO", font=f_big)
    tw = bbox[2] - bbox[0]
    tx = SCREEN_X + (SCREEN_W - tw) // 2
    bc = theme["button"]
    draw.text((tx+2, y+2), "ZERO", font=f_big, fill=tuple(max(0, c-60) for c in bc))
    draw.text((tx, y), "ZERO", font=f_big, fill=bc)

    # Subtitle
    y += 60
    centered_text(draw, y, "Менеджер паролей", font(16), theme["subtext"])

    # Input fields
    field_x = SCREEN_X + 24
    field_w = SCREEN_W - 48
    field_h = 52
    y += 40

    draw_input_field(draw, img, field_x, y, field_w, field_h, "Логин", theme,
                     value="user@example.com")
    y += field_h + 14
    draw_input_field(draw, img, field_x, y, field_w, field_h, "Пароль", theme,
                     value="mypassword123", is_password=True)
    y += field_h + 20

    # Login button
    draw_button(draw, img, field_x, y, field_w, 52, "Войти", theme)
    y += 64

    # Link
    link_text = "Нет аккаунта? Зарегистрироваться"
    centered_text(draw, y, link_text, font(14), theme["accent"])

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 3: SIGNUP
# ═══════════════════════════════════════════════════════════════════════════════

def screen_signup(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    draw_status_bar(draw, theme)

    content_y = SCREEN_Y + STATUS_H + 40
    cx = SCREEN_X + SCREEN_W // 2

    # Icon box (person_add)
    draw_icon_box(draw, img, cx, content_y + 40, 80, theme, "+U")

    # "ZERO" title
    y = content_y + 100
    f_big = font(48, bold=True)
    bbox = draw.textbbox((0, 0), "ZERO", font=f_big)
    tw = bbox[2] - bbox[0]
    tx = SCREEN_X + (SCREEN_W - tw) // 2
    bc = theme["button"]
    draw.text((tx+2, y+2), "ZERO", font=f_big, fill=tuple(max(0, c-60) for c in bc))
    draw.text((tx, y), "ZERO", font=f_big, fill=bc)

    # Subtitle
    y += 60
    centered_text(draw, y, "Создание аккаунта", font(16), theme["subtext"])

    # Fields
    field_x = SCREEN_X + 24
    field_w = SCREEN_W - 48
    field_h = 52
    y += 40

    draw_input_field(draw, img, field_x, y, field_w, field_h, "Логин", theme,
                     value="new_user")
    y += field_h + 14
    draw_input_field(draw, img, field_x, y, field_w, field_h, "Пароль", theme,
                     value="securepass", is_password=True)
    y += field_h + 20

    draw_button(draw, img, field_x, y, field_w, 52, "Зарегистрироваться", theme)
    y += 64

    centered_text(draw, y, "Уже есть аккаунт? Войти", font(14), theme["accent"])

    # 2FA setup hint card
    y += 40
    card_x = field_x
    card_w = field_w
    card_h = 80
    draw_rounded_rect(draw, [card_x, y, card_x+card_w, y+card_h], 12,
                      fill=tuple(c // 4 for c in theme["button"]),
                      outline=tuple(c // 2 for c in theme["button"]), width=1)
    draw.text((card_x+16, y+12), "2FA", font=font(14, bold=True), fill=theme["button"])
    draw.text((card_x+16, y+32), "Двухфакторная аутентификация", font=font(13), fill=theme["subtext"])
    draw.text((card_x+16, y+50), "будет настроена после регистрации", font=font(13), fill=theme["subtext"])

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 4: 2FA SETUP
# ═══════════════════════════════════════════════════════════════════════════════

def screen_2fa_setup(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    content_y = draw_appbar(draw, img, "Настройка 2FA", theme, show_back=True)

    cx = SCREEN_X + SCREEN_W // 2
    y = content_y + 20

    centered_text(draw, y, "Отсканируйте QR-код", font(18, bold=True), theme["text"])
    y += 30
    centered_text(draw, y, "в приложении Google Authenticator", font(14), theme["subtext"])

    # QR code placeholder (grid)
    y += 30
    qr_size = 200
    qx = cx - qr_size // 2
    qy = y
    draw_rounded_rect(draw, [qx-4, qy-4, qx+qr_size+4, qy+qr_size+4], 8,
                      fill=(255, 255, 255))
    # QR pattern
    cell = qr_size // 20
    bc = theme["button"]
    for row in range(20):
        for col in range(20):
            # Finder patterns in corners
            is_finder = (
                (row < 7 and col < 7) or
                (row < 7 and col > 12) or
                (row > 12 and col < 7)
            )
            # Random-ish data dots
            is_data = (row + col * 3 + row * col) % 3 == 0
            if is_finder or is_data:
                cx2 = qx + col * cell
                cy2 = qy + row * cell
                draw.rectangle([cx2+1, cy2+1, cx2+cell-1, cy2+cell-1], fill=(10, 10, 20))

    # Finder pattern corners (white squares inside)
    for (fr, fc) in [(1,1),(1,14),(14,1)]:
        draw.rectangle([qx+fc*cell+cell, qy+fr*cell+cell,
                        qx+fc*cell+5*cell, qy+fr*cell+5*cell], fill=(255,255,255))
        draw.rectangle([qx+fc*cell+2*cell, qy+fr*cell+2*cell,
                        qx+fc*cell+4*cell, qy+fr*cell+4*cell], fill=(10,10,20))

    y += qr_size + 24

    # Manual key
    centered_text(draw, y, "Или введите ключ вручную:", font(13), theme["subtext"])
    y += 22
    secret = "JBSWY3DPEHPK3PXP"
    f_mono = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 15)
    bbox = draw.textbbox((0,0), secret, font=f_mono)
    tw = bbox[2]-bbox[0]
    tx = SCREEN_X + (SCREEN_W - tw) // 2
    draw.text((tx, y), secret, font=f_mono, fill=theme["accent"])

    y += 30
    field_x = SCREEN_X + 24
    field_w = SCREEN_W - 48
    draw_input_field(draw, img, field_x, y, field_w, 52, "Введите код из приложения", theme)
    y += 66

    draw_button(draw, img, field_x, y, field_w, 52, "Подтвердить", theme)

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 5: PIN
# ═══════════════════════════════════════════════════════════════════════════════

def screen_pin(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    draw_status_bar(draw, theme)

    cx = SCREEN_X + SCREEN_W // 2
    cy = SCREEN_Y + SCREEN_H // 2 - 60

    # Lock icon box
    draw_icon_box(draw, img, cx, cy - 80, 80, theme, "[]")  # lock

    # Title
    centered_text(draw, cy - 20, "Введите PIN-код", font(26, bold=True), theme["text"])
    centered_text(draw, cy + 14, "Для доступа к приложению", font(15), theme["subtext"])

    # 4 PIN input boxes
    box_size = 60
    gap = 16
    total_w = 4 * box_size + 3 * gap
    start_x = SCREEN_X + (SCREEN_W - total_w) // 2
    box_y = cy + 55
    bc = theme["button"]

    for i in range(4):
        bx = start_x + i * (box_size + gap)
        # Filled boxes (first 2 filled)
        if i < 2:
            draw_rounded_rect(draw, [bx, box_y, bx+box_size, box_y+box_size], 12,
                              fill=theme["input"],
                              outline=bc, width=2)
            # Filled dot
            dcx = bx + box_size // 2
            dcy = box_y + box_size // 2
            draw.ellipse([dcx-10, dcy-10, dcx+10, dcy+10], fill=bc)
        else:
            draw_rounded_rect(draw, [bx, box_y, bx+box_size, box_y+box_size], 12,
                              fill=theme["input"],
                              outline=theme["secondary"], width=2)

    # Biometric button
    bio_y = box_y + box_size + 40
    btn_w = 260
    btn_x = SCREEN_X + (SCREEN_W - btn_w) // 2
    draw_button(draw, img, btn_x, bio_y, btn_w, 52,
                "  Биометрия", theme)
    # Fingerprint emoji-like icon
    draw.text((btn_x + 16, bio_y + 14), "~O~", font=font(18, bold=True), fill=(255,255,255))

    # Exit link
    centered_text(draw, bio_y + 70, "Выйти", font(15), theme["subtext"])

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 6: PASSWORDS LIST
# ═══════════════════════════════════════════════════════════════════════════════

SAMPLE_PASSWORDS = [
    {"site": "github.com",     "login": "dev@mail.com",    "color": (36, 41, 47),   "letter": "G", "has_2fa": True},
    {"site": "gmail.com",      "login": "myemail@gmail.com","color": (234, 67, 53), "letter": "G", "has_2fa": False},
    {"site": "aws.amazon.com", "login": "admin@company.io", "color": (255, 153, 0), "letter": "A", "has_2fa": True},
    {"site": "figma.com",      "login": "designer@team.co", "color": (162, 89, 255),"letter": "F", "has_2fa": False},
    {"site": "notion.so",      "login": "notes@work.dev",   "color": (0, 0, 0),     "letter": "N", "has_2fa": False},
]

def draw_password_card(draw, img, x, y, w, entry, theme):
    """Draw a single password card."""
    h = 72
    bg = theme["input"]
    border = theme["secondary"]

    # Card background
    draw_rounded_rect(draw, [x, y, x+w, y+h], 14, fill=bg, outline=border, width=1)

    # Favicon circle
    fav_r = 20
    fav_cx = x + 16 + fav_r
    fav_cy = y + h // 2
    draw.ellipse([fav_cx-fav_r, fav_cy-fav_r, fav_cx+fav_r, fav_cy+fav_r],
                 fill=entry["color"])
    lf = font(16, bold=True)
    bbox = draw.textbbox((0,0), entry["letter"], font=lf)
    lw, lh = bbox[2]-bbox[0], bbox[3]-bbox[1]
    draw.text((fav_cx-lw//2, fav_cy-lh//2-1), entry["letter"],
              font=lf, fill=(255, 255, 255))

    # Text content
    tx = fav_cx + fav_r + 14
    draw.text((tx, y+10), entry["site"], font=font(16, bold=True), fill=theme["text"])
    draw.text((tx, y+32), entry["login"], font=font(13), fill=theme["subtext"])

    # Right side icons
    rx = x + w - 16
    if entry.get("has_2fa"):
        draw.text((rx - 60, y + 26), "[2FA]", font=font(11), fill=theme["accent"])
    draw.text((rx - 30, y + 24), "[*]", font=font(13), fill=theme["subtext"])
    draw.text((rx - 8, y + 24), ">", font=font(14, bold=True), fill=theme["subtext"])

    return h

def screen_passwords(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    content_y = draw_appbar(draw, img, "Пароли", theme)

    # AppBar right icons
    ry = SCREEN_Y + STATUS_H + 12
    draw.text((SCREEN_X + SCREEN_W - 120, ry), "[S]", font=font(14), fill=theme["accent"])
    draw.text((SCREEN_X + SCREEN_W - 80, ry),  "[+]", font=font(14, bold=True), fill=theme["accent"])
    draw.text((SCREEN_X + SCREEN_W - 42, ry),  "[=]", font=font(14), fill=theme["accent"])

    # Search bar
    y = content_y + 12
    sx = SCREEN_X + 16
    sw = SCREEN_W - 32
    draw_input_field(draw, img, sx, y, sw, 44, "  Поиск...", theme)
    draw.text((sx+12, y+13), "?", font=font(16, bold=True), fill=theme["subtext"])

    # Password list
    y += 56 + 4
    card_x = SCREEN_X + 14
    card_w = SCREEN_W - 28
    for entry in SAMPLE_PASSWORDS:
        h = draw_password_card(draw, img, card_x, y, card_w, entry, theme)
        y += h + 10
        if y > SCREEN_Y + SCREEN_H - 80:
            break

    # Bottom nav bar
    nav_y = SCREEN_Y + SCREEN_H - 56
    draw.rectangle([SCREEN_X, nav_y, SCREEN_X+SCREEN_W, SCREEN_Y+SCREEN_H],
                   fill=theme["appbar"])
    draw.line([SCREEN_X, nav_y, SCREEN_X+SCREEN_W, nav_y], fill=theme["secondary"], width=1)
    nav_items = [("Пароли", True), ("Настройки", False)]
    for i, (label, active) in enumerate(nav_items):
        nx = SCREEN_X + (i + 0.5) * SCREEN_W // 2
        c = theme["button"] if active else theme["subtext"]
        bbox = draw.textbbox((0,0), label, font=font(13, bold=active))
        tw = bbox[2]-bbox[0]
        draw.text((nx - tw//2, nav_y + 10), label, font=font(13, bold=active), fill=c)
        if active:
            draw.rectangle([nx - 20, nav_y+2, nx+20, nav_y+4], fill=theme["button"])

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 7: ADD PASSWORD
# ═══════════════════════════════════════════════════════════════════════════════

def screen_add_password(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    content_y = draw_appbar(draw, img, "Добавление пароля", theme, show_back=True)

    field_x = SCREEN_X + 20
    field_w = SCREEN_W - 40
    field_h = 52
    y = content_y + 16

    fields = [
        ("Сайт", "github.com", False),
        ("Логин", "dev@example.com", False),
        ("Пароль", "SuperSecret!42", True),
        ("Заметки (необязательно)", "", False),
    ]

    for hint, value, is_pw in fields:
        draw_input_field(draw, img, field_x, y, field_w,
                         field_h if hint != "Заметки (необязательно)" else 80,
                         hint, theme, value=value if value else None, is_password=is_pw)
        y += (field_h if hint != "Заметки (необязательно)" else 80) + 12

    # Generate password button (small, next to password field)
    gen_y = content_y + 16 + (field_h + 12) * 2
    draw.text((field_x + field_w - 110, gen_y + field_h + 8),
              "[обновить]", font=font(12), fill=theme["accent"])

    y += 8
    # Toggle: 2FA
    toggle_h = 52
    draw_rounded_rect(draw, [field_x, y, field_x+field_w, y+toggle_h], 12,
                      fill=theme["input"], outline=theme["secondary"], width=1)
    draw.text((field_x+16, y+17), "Двухфакторная аутентификация", font=font(15), fill=theme["text"])
    # Toggle switch (ON)
    ts_x = field_x + field_w - 58
    ts_y = y + 14
    draw.rounded_rectangle([ts_x, ts_y, ts_x+46, ts_y+24], radius=12,
                            fill=theme["button"])
    draw.ellipse([ts_x+24, ts_y+2, ts_x+44, ts_y+22], fill=(255,255,255))
    y += toggle_h + 10

    # Toggle: Seed phrase
    draw_rounded_rect(draw, [field_x, y, field_x+field_w, y+toggle_h], 12,
                      fill=theme["input"], outline=theme["secondary"], width=1)
    draw.text((field_x+16, y+17), "Seed-фраза", font=font(15), fill=theme["text"])
    ts_x = field_x + field_w - 58
    ts_y = y + 14
    draw.rounded_rectangle([ts_x, ts_y, ts_x+46, ts_y+24], radius=12,
                            fill=theme["secondary"])
    draw.ellipse([ts_x+2, ts_y+2, ts_x+22, ts_y+22], fill=(255,255,255))
    y += toggle_h + 16

    # Save button
    draw_button(draw, img, field_x, y, field_w, 54, "Сохранить", theme)

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 8: SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════

def draw_settings_item(draw, img, x, y, w, icon, title, subtitle, theme, value=None, is_switch=None, switch_on=False):
    h = 62
    draw_rounded_rect(draw, [x, y, x+w, y+h], 12, fill=theme["input"], outline=theme["secondary"], width=1)
    # Icon
    bc = theme["button"]
    draw.ellipse([x+10, y+14, x+38, y+42], fill=tuple(c//3 for c in bc))
    draw.text((x+16, y+18), icon, font=font(14, bold=True), fill=bc)
    # Text
    tx = x + 52
    draw.text((tx, y+10), title, font=font(15, bold=True), fill=theme["text"])
    if subtitle:
        draw.text((tx, y+31), subtitle, font=font(12), fill=theme["subtext"])
    # Right side
    rx = x + w - 16
    if is_switch is not None:
        ts_x = rx - 52
        ts_y = y + 18
        col = theme["button"] if switch_on else theme["secondary"]
        draw.rounded_rectangle([ts_x, ts_y, ts_x+46, ts_y+24], radius=12, fill=col)
        cx2 = (ts_x+26) if switch_on else (ts_x+2)
        draw.ellipse([cx2, ts_y+2, cx2+20, ts_y+22], fill=(255,255,255))
    elif value:
        draw.text((rx - len(value)*7, y+22), value, font=font(13), fill=theme["subtext"])
    else:
        draw.text((rx-8, y+22), ">", font=font(16, bold=True), fill=theme["subtext"])
    return h

def screen_settings(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    content_y = draw_appbar(draw, img, "Настройки", theme)

    ix = SCREEN_X + 14
    iw = SCREEN_W - 28
    y = content_y + 10

    sections = [
        ("БЕЗОПАСНОСТЬ", [
            ("[]", "PIN-код",          "PIN-код установлен",      None, None, False),
            ("/",  "Скрыть seed-фразы","Включено",                None, True, True),
            ("~",  "Биометрия",        "Использовать отпечаток",  None, True, False),
        ]),
        ("ИНТЕРФЕЙС", [
            ("*",  "Тема приложения",  theme["name"],             None, None, False),
        ]),
        ("АККАУНТ", [
            ("@",  "Обновить favicon", "Обновить иконки сайтов",  None, None, False),
            ("->", "Выйти",            "Завершить сессию",        None, None, False),
        ]),
        ("ИНФОРМАЦИЯ", [
            ("i",  "Версия",           "0.2.1",                   None, None, False),
        ]),
    ]

    for section_name, items in sections:
        # Section header
        draw.text((ix+4, y+4), section_name, font=font(12, bold=True), fill=theme["button"])
        y += 26
        for icon, title, subtitle, value, is_sw, sw_on in items:
            h = draw_settings_item(draw, img, ix, y, iw, icon, title, subtitle, theme,
                                   value=value, is_switch=is_sw, switch_on=sw_on)
            y += h + 8
        y += 6

    # Creator card
    if y + 80 < SCREEN_Y + SCREEN_H - 60:
        ccard_h = 70
        bc = theme["button"]
        draw_rounded_rect(draw, [ix, y, ix+iw, y+ccard_h], 16,
                          fill=tuple(c//5 for c in bc),
                          outline=tuple(c//2 for c in bc), width=1)
        draw.text((ix+16, y+10), "{ }", font=font(22, bold=True), fill=bc)
        draw.text((ix+60, y+10), "Создано NK_TRIPLLE",
                  font=font(15, bold=True), fill=theme["text"])
        draw.text((ix+60, y+32), "С любовью к безопасности",
                  font=font(13), fill=theme["subtext"])

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# SCREEN 9: PASSWORD DETAIL (edit)
# ═══════════════════════════════════════════════════════════════════════════════

def screen_edit_password(theme):
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)
    content_y = draw_appbar(draw, img, "Редактирование", theme, show_back=True)

    field_x = SCREEN_X + 20
    field_w = SCREEN_W - 40
    field_h = 52
    y = content_y + 16

    # Favicon preview
    entry = SAMPLE_PASSWORDS[0]
    fav_r = 30
    fav_cx = SCREEN_X + SCREEN_W // 2
    draw.ellipse([fav_cx-fav_r, y-2, fav_cx+fav_r, y+2*fav_r-2], fill=entry["color"])
    lf = font(20, bold=True)
    bbox = draw.textbbox((0,0), entry["letter"], font=lf)
    lw, lh = bbox[2]-bbox[0], bbox[3]-bbox[1]
    draw.text((fav_cx-lw//2, y+fav_r-lh//2-2), entry["letter"], font=lf, fill=(255,255,255))
    y += 2*fav_r + 16

    fields = [
        ("Сайт",   "github.com",           False),
        ("Логин",  "dev@mail.com",          False),
        ("Пароль", "myGitHubPass!",         True),
        ("Заметки","Основной акаунт разработчика", False),
    ]
    for hint, value, is_pw in fields:
        h2 = field_h if hint != "Заметки" else 72
        draw_input_field(draw, img, field_x, y, field_w, h2, hint, theme,
                         value=value, is_password=is_pw)
        y += h2 + 12

    y += 8
    draw_button(draw, img, field_x, y, field_w, 54, "Сохранить изменения", theme)
    y += 68

    # Delete button
    del_col = theme["error"]
    draw_rounded_rect(draw, [field_x, y, field_x+field_w, y+54], 14,
                      fill=tuple(c//4 for c in del_col),
                      outline=del_col, width=1)
    bbox = draw.textbbox((0,0), "Удалить запись", font=font(17, bold=True))
    tw = bbox[2]-bbox[0]
    tx = field_x + (field_w - tw) // 2
    draw.text((tx, y+16), "Удалить запись", font=font(17, bold=True), fill=del_col)

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# THEME COMPARISON FRAMES (Cyberpunk + Glass passwords)
# ═══════════════════════════════════════════════════════════════════════════════

def screen_cyberpunk_passwords():
    theme = THEMES["cyberpunk"]
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)

    # Cyberpunk gradient background
    draw_gradient_rect(img,
                       [SCREEN_X, SCREEN_Y, SCREEN_X+SCREEN_W, SCREEN_Y+SCREEN_H],
                       (10, 10, 10), (26, 10, 26))

    content_y = draw_appbar(draw, img, "Пароли", theme)

    # Neon accent lines
    ac = theme["accent"]  # magenta
    bc = theme["button"]  # cyan
    draw.line([SCREEN_X, content_y, SCREEN_X+SCREEN_W, content_y], fill=bc, width=2)

    # Theme badge
    badge_text = "[ CYBERPUNK ]"
    bbox = draw.textbbox((0,0), badge_text, font=font(14, bold=True))
    tw = bbox[2]-bbox[0]
    bx = SCREEN_X + (SCREEN_W - tw) // 2
    draw.text((bx+1, content_y+8+1), badge_text, font=font(14, bold=True), fill=(0,0,0))
    draw.text((bx, content_y+8), badge_text, font=font(14, bold=True), fill=ac)

    y = content_y + 36
    card_x = SCREEN_X + 14
    card_w = SCREEN_W - 28

    for entry in SAMPLE_PASSWORDS:
        h = 72
        # Cyberpunk card style: dark bg, cyan border
        draw_rounded_rect(draw, [card_x, y, card_x+card_w, y+h], 14,
                          fill=(15, 15, 15),
                          outline=bc, width=2)
        # Neon left accent bar
        draw.rectangle([card_x+2, y+6, card_x+5, y+h-6], fill=bc)

        # Favicon
        fav_r = 20
        fav_cx = card_x + 26
        fav_cy = y + h // 2
        draw.ellipse([fav_cx-fav_r, fav_cy-fav_r, fav_cx+fav_r, fav_cy+fav_r],
                     fill=entry["color"])
        lf = font(16, bold=True)
        bbox2 = draw.textbbox((0,0), entry["letter"], font=lf)
        lw, lh = bbox2[2]-bbox2[0], bbox2[3]-bbox2[1]
        draw.text((fav_cx-lw//2, fav_cy-lh//2-1), entry["letter"], font=lf, fill=(255,255,255))

        tx = fav_cx + fav_r + 14
        draw.text((tx, y+10), entry["site"], font=font(16, bold=True), fill=bc)
        draw.text((tx, y+32), entry["login"], font=font(13), fill=(0, 180, 180))

        if entry.get("has_2fa"):
            draw.text((card_x+card_w-80, y+26), "[2FA]", font=font(11), fill=ac)

        y += h + 10
        if y > SCREEN_Y + SCREEN_H - 80:
            break

    return img


def screen_glass_passwords():
    theme = THEMES["glass"]
    img = make_base_frame(theme["bg"])
    draw = ImageDraw.Draw(img)

    # Glass gradient background
    draw_gradient_rect(img,
                       [SCREEN_X, SCREEN_Y, SCREEN_X+SCREEN_W, SCREEN_Y+SCREEN_H],
                       (30, 30, 46), (45, 42, 70))

    # Decorative blurred blobs (glassmorphism effect)
    blob_layer = Image.new("RGBA", img.size, (0,0,0,0))
    bd = ImageDraw.Draw(blob_layer)
    bd.ellipse([SCREEN_X+20, SCREEN_Y+80, SCREEN_X+180, SCREEN_Y+280],
               fill=(137,180,250,40))
    bd.ellipse([SCREEN_X+SCREEN_W-180, SCREEN_Y+200, SCREEN_X+SCREEN_W-20, SCREEN_Y+420],
               fill=(180,190,254,30))
    blob_layer = blob_layer.filter(ImageFilter.GaussianBlur(30))
    img.paste(Image.new("RGBA", img.size, (0,0,0,0)), mask=blob_layer.split()[3])
    # Compose manually
    arr = img.load()
    blobr = blob_layer.load()
    for py in range(img.height):
        for px in range(img.width):
            bpix = blobr[px, py]
            if bpix[3] > 0:
                opix = arr[px, py]
                a = bpix[3] / 255.0
                nr = int(opix[0] * (1-a) + bpix[0] * a)
                ng = int(opix[1] * (1-a) + bpix[1] * a)
                nb = int(opix[2] * (1-a) + bpix[2] * a)
                arr[px, py] = (nr, ng, nb)

    content_y = draw_appbar(draw, img, "Пароли", theme)

    badge_text = "[ GLASSMORPHISM ]"
    bbox = draw.textbbox((0,0), badge_text, font=font(14, bold=True))
    tw = bbox[2]-bbox[0]
    bx = SCREEN_X + (SCREEN_W - tw) // 2
    draw.text((bx, content_y+8), badge_text, font=font(14, bold=True), fill=theme["accent"])

    y = content_y + 36
    card_x = SCREEN_X + 14
    card_w = SCREEN_W - 28

    for entry in SAMPLE_PASSWORDS:
        h = 72
        # Glass card: semi-transparent white overlay
        glass_col = (255, 255, 255, 25)
        glass_img = Image.new("RGBA", img.size, (0,0,0,0))
        gd = ImageDraw.Draw(glass_img)
        draw_rounded_rect(gd, [card_x, y, card_x+card_w, y+h], 14,
                          fill=(255,255,255,30), outline=(255,255,255,60), width=1)
        img = img.convert("RGBA")
        img = Image.alpha_composite(img, glass_img)
        img = img.convert("RGB")
        draw = ImageDraw.Draw(img)

        # Content
        fav_r = 20
        fav_cx = card_x + 26
        fav_cy = y + h // 2
        draw.ellipse([fav_cx-fav_r, fav_cy-fav_r, fav_cx+fav_r, fav_cy+fav_r],
                     fill=entry["color"])
        lf = font(16, bold=True)
        bbox2 = draw.textbbox((0,0), entry["letter"], font=lf)
        lw, lh = bbox2[2]-bbox2[0], bbox2[3]-bbox2[1]
        draw.text((fav_cx-lw//2, fav_cy-lh//2-1), entry["letter"], font=lf, fill=(255,255,255))

        tx = fav_cx + fav_r + 14
        draw.text((tx, y+10), entry["site"], font=font(16, bold=True), fill=theme["text"])
        draw.text((tx, y+32), entry["login"], font=font(13), fill=theme["subtext"])
        if entry.get("has_2fa"):
            draw.text((card_x+card_w-80, y+26), "[2FA]", font=font(11), fill=theme["accent"])

        y += h + 10
        if y > SCREEN_Y + SCREEN_H - 80:
            break

    return img


# ═══════════════════════════════════════════════════════════════════════════════
# TRANSITION FRAMES
# ═══════════════════════════════════════════════════════════════════════════════

def make_transition(img1, img2, steps=4):
    """Generate blend frames between two screens."""
    frames = []
    for i in range(1, steps+1):
        t = i / (steps + 1)
        blended = Image.blend(img1.convert("RGB"), img2.convert("RGB"), t)
        frames.append(blended)
    return frames


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN: BUILD GIF
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    dark = THEMES["dark"]

    print("Rendering screens...")
    s1  = screen_splash(dark)
    s2  = screen_login(dark)
    s3  = screen_signup(dark)
    s4  = screen_2fa_setup(dark)
    s5  = screen_pin(dark)
    s6  = screen_passwords(dark)
    s7  = screen_add_password(dark)
    s8  = screen_settings(dark)
    s9  = screen_edit_password(dark)
    s10 = screen_cyberpunk_passwords()
    s11 = screen_glass_passwords()
    s12 = screen_splash(dark)  # loop back

    print("Building frame sequence...")

    HOLD = 220   # centiseconds = 2.2 sec per main screen
    HOLD_LONG = 300  # 3 sec for theme comparison screens
    TRANS = 8    # centiseconds per transition frame

    frames = []
    durations = []

    sequence = [
        (s1,  HOLD),
        *[(f, TRANS) for f in make_transition(s1, s2)],
        (s2,  HOLD),
        *[(f, TRANS) for f in make_transition(s2, s3)],
        (s3,  HOLD),
        *[(f, TRANS) for f in make_transition(s3, s4)],
        (s4,  HOLD),
        *[(f, TRANS) for f in make_transition(s4, s5)],
        (s5,  HOLD),
        *[(f, TRANS) for f in make_transition(s5, s6)],
        (s6,  HOLD),
        *[(f, TRANS) for f in make_transition(s6, s7)],
        (s7,  HOLD),
        *[(f, TRANS) for f in make_transition(s7, s8)],
        (s8,  HOLD),
        *[(f, TRANS) for f in make_transition(s8, s9)],
        (s9,  HOLD),
        *[(f, TRANS) for f in make_transition(s9, s10)],
        (s10, HOLD_LONG),
        *[(f, TRANS) for f in make_transition(s10, s11)],
        (s11, HOLD_LONG),
        *[(f, TRANS) for f in make_transition(s11, s12)],
        (s12, HOLD),
    ]

    for img, dur in sequence:
        frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=256))
        durations.append(dur * 10)  # PIL uses milliseconds

    print(f"Saving GIF ({len(frames)} frames)...")
    os.makedirs("assets", exist_ok=True)
    frames[0].save(
        "assets/demo.gif",
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=False,
    )

    size_kb = os.path.getsize("assets/demo.gif") // 1024
    print(f"Done! assets/demo.gif  ({size_kb} KB, {len(frames)} frames)")


if __name__ == "__main__":
    main()
