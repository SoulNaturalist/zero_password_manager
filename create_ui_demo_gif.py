#!/usr/bin/env python3
"""Beautiful Flutter UI Demo GIF — v2 (uses real logo + bg images)."""
import os, math
import numpy as np
from PIL import (Image, ImageDraw, ImageFont, ImageFilter,
                 ImageChops, ImageEnhance)

BASE    = os.path.dirname(os.path.abspath(__file__))
LOGO    = os.path.join(BASE, "lib/assets/raw.png")
BG_CYB  = os.path.join(BASE, "assets/images/backgrounds/cyberpunk_bg.png")
BG_GLASS= os.path.join(BASE, "assets/images/backgrounds/glassmorphism_bg.jpg")
FD      = "/usr/share/fonts/truetype/dejavu"
def F(s,b=False):
    return ImageFont.truetype(f"{FD}/DejaVuSans-Bold.ttf" if b else f"{FD}/DejaVuSans.ttf", s)

def dim(c,f): return tuple(max(0,int(x*f)) for x in c)
def bri(c,f): return tuple(min(255,int(x*f)) for x in c)
def mix(a,b,t): return tuple(int(a[i]*(1-t)+b[i]*t) for i in range(3))

# ── Themes ─────────────────────────────────────────────────────────────────
class D:
    bg=(26,20,46);btn=(93,82,210);inp=(34,25,55);text=(255,255,255)
    accent=(139,126,216);sec=(64,58,92);sub=(130,120,175);appbar=(18,13,34);err=(231,76,60)
    name="Тёмная"
class C:
    bg=(10,10,10);btn=(0,235,235);inp=(20,20,30);text=(0,235,235)
    accent=(255,0,128);sec=(40,40,60);sub=(0,170,170);appbar=(5,5,10);err=(255,0,64)
    name="Cyberpunk"
class G:
    bg=(30,30,46);btn=(137,180,250);inp=(49,50,68);text=(205,214,244)
    accent=(180,190,254);sec=(60,62,85);sub=(147,153,178);appbar=(20,20,34);err=(243,139,168)
    name="Glassmorphism"

# ── Canvas ──────────────────────────────────────────────────────────────────
GW,GH = 480,980
PW,PH = 420,900
PX,PY = (GW-PW)//2,(GH-PH)//2
SW,SH = PW-20,PH-20
SX,SY = PX+10,PY+10
SCR   = 38
STATH = 32

# ── Numpy helpers ────────────────────────────────────────────────────────────
def vgrad(c1,c2,w,h):
    a=np.zeros((h,w,3),np.uint8)
    for i in range(3):
        a[:,:,i]=np.linspace(c1[i],c2[i],h,dtype=np.float32)[:,None]
    return a

def dgrad(c1,c2,c3,w,h):
    a=np.zeros((h,w,3),np.uint8)
    for y in range(h):
        t=y/(h-1)
        if t<0.5: c=mix(c1,c2,t*2)
        else:     c=mix(c2,c3,(t-0.5)*2)
        a[y,:]=c
    return a

# ── Rounded rect mask ───────────────────────────────────────────────────────
def rrmask(w,h,r,aa=3):
    big=Image.new("L",(w*aa,h*aa),0)
    ImageDraw.Draw(big).rounded_rectangle([0,0,w*aa-1,h*aa-1],radius=r*aa,fill=255)
    return big.resize((w,h),Image.LANCZOS)

def rrpaste(canvas,img_rgba,x,y):
    """Paste RGBA image with its own alpha."""
    canvas.paste(img_rgba.convert("RGB"),(x,y),img_rgba.split()[3])

# ── Phone frame ─────────────────────────────────────────────────────────────
def phone_frame(screen):
    frame=Image.new("RGB",(GW,GH),(12,12,18))
    # Body
    body_a=vgrad((54,54,64),(36,36,46),PW,PH)
    body=Image.fromarray(body_a)
    body_rgba=body.convert("RGBA")
    body_rgba.putalpha(rrmask(PW,PH,44))
    rrpaste(frame,body_rgba,PX,PY)
    d=ImageDraw.Draw(frame)
    d.rounded_rectangle([PX,PY,PX+PW,PY+PH],radius=44,outline=(76,76,92),width=2)
    # Buttons
    d.rounded_rectangle([PX+PW-1,PY+130,PX+PW+4,PY+195],radius=2,fill=(62,62,74))
    d.rounded_rectangle([PX-4,PY+110,PX+1,PY+155],radius=2,fill=(62,62,74))
    d.rounded_rectangle([PX-4,PY+165,PX+1,PY+210],radius=2,fill=(62,62,74))
    # Screen
    scr_rgba=screen.convert("RGBA")
    scr_rgba.putalpha(rrmask(SW,SH,SCR))
    rrpaste(frame,scr_rgba,SX,SY)
    d.rounded_rectangle([SX,SY,SX+SW,SY+SH],radius=SCR,outline=(55,55,70),width=1)
    # Notch
    nx=SX+(SW-88)//2; ny=SY+5
    d.rounded_rectangle([nx,ny,nx+88,ny+18],radius=9,fill=(12,12,18))
    d.ellipse([nx+72,ny+4,nx+84,ny+14],fill=(22,22,30))
    d.ellipse([nx+75,ny+7,nx+81,ny+11],fill=(8,8,14),outline=(28,28,38),width=1)
    return frame

# ── Screen helpers ───────────────────────────────────────────────────────────
def ns(c): return Image.new("RGB",(SW,SH),c)

def status(d,th):
    d.text((14,10),"22:10",font=F(13,True),fill=th.text)
    bx=SW-36
    d.rectangle([bx,10,bx+26,22],outline=th.text,width=1)
    d.rectangle([bx+26,13,bx+29,19],fill=th.text)
    d.rectangle([bx+1,11,bx+21,21],fill=th.btn)
    for i in range(4):
        bh=5+i*3; xi=SW-70+i*8
        d.rectangle([xi,22-bh,xi+5,22],fill=(th.text if i<3 else th.sec))

def appbar(sc,d,th,title,back=False):
    y0=STATH
    d.rectangle([0,y0,SW,y0+54],fill=th.appbar)
    d.line([0,y0+54,SW,y0+54],fill=th.sec,width=1)
    if back: d.text((14,y0+14),"‹",font=F(28,True),fill=th.accent)
    f=F(19,True); bb=d.textbbox((0,0),title,font=f)
    d.text(((SW-(bb[2]-bb[0]))//2,y0+16),title,font=f,fill=th.accent)
    return y0+60

def ctext(d,y,txt,f,c,W=None,ox=0):
    W=W or SW; bb=d.textbbox((0,0),txt,font=f)
    d.text((ox+(W-(bb[2]-bb[0]))//2,y),txt,font=f,fill=c)

def rr(d,x,y,w,h,r,fill=None,outline=None,width=1):
    d.rounded_rectangle([x,y,x+w,y+h],radius=r,fill=fill,outline=outline,width=width)

def grad_box(sc,x,y,w,h,r,c1,c2):
    arr=vgrad(c1,c2,w,h); tmp=Image.fromarray(arr)
    sc.paste(tmp,(x,y),rrmask(w,h,r))

def icon_box(sc,cx,cy,sz,th):
    half=sz//2; x0,y0=cx-half,cy-half
    grad_box(sc,x0,y0,sz,sz,sz//4,bri(th.btn,1.15),dim(th.btn,0.65))
    d=ImageDraw.Draw(sc)
    d.rounded_rectangle([x0,y0,x0+sz,y0+sz],radius=sz//4,
                         outline=(*bri(th.btn,1.5),100),width=2)

def inp(sc,d,x,y,w,h,hint,th,val=None,pw=False,icon=None,focus=False):
    rr(d,x,y,w,h,12,fill=th.inp)
    bc=th.btn if focus else th.sec
    rr(d,x,y,w,h,12,outline=bc,width=2 if focus else 1)
    px2=x+14
    if icon: d.text((px2,y+(h-18)//2),icon,font=F(14),fill=th.sub); px2+=24
    txt=("•"*min(len(val or ""),10) if pw and val else (val or hint))
    col=th.text if val else th.sub
    d.text((px2,y+(h-20)//2),txt,font=F(15),fill=col)

def btn(sc,d,x,y,w,h,lbl,th):
    grad_box(sc,x,y,w,h,12,mix(th.btn,(255,255,255),0.08),dim(th.btn,0.7))
    d2=ImageDraw.Draw(sc)
    d2.rounded_rectangle([x,y,x+w,y+h],radius=12,outline=(*bri(th.btn,1.5),70),width=1)
    f=F(17,True); bb=d2.textbbox((0,0),lbl,font=f)
    d2.text((x+(w-(bb[2]-bb[0]))//2,y+(h-(bb[3]-bb[1]))//2),lbl,font=f,fill=(255,255,255))

def toggle(sc,d,x,y,on,th):
    rr(d,x,y,46,24,12,fill=(th.btn if on else th.sec))
    cx2=(x+26) if on else (x+2)
    d.ellipse([cx2,y+2,cx2+20,y+22],fill=(255,255,255))

def nav_bar(sc,d,th,active=0):
    ny=SH-54
    d.rectangle([0,ny,SW,SH],fill=th.appbar)
    d.line([0,ny,SW,ny],fill=th.sec,width=1)
    for i,lbl in enumerate(["Пароли","Настройки"]):
        nx=(i+0.5)*SW//2; c=th.btn if i==active else th.sub
        bb=d.textbbox((0,0),lbl,font=F(13,i==active))
        d.text((nx-(bb[2]-bb[0])//2,ny+10),lbl,font=F(13,i==active),fill=c)
        if i==active: rr(d,nx-22,ny+2,44,3,2,fill=th.btn)

def neon_glow(sc,x,y,txt,f,col,gcol,gr=7):
    tmp=Image.new("RGBA",sc.size,(0,0,0,0))
    td=ImageDraw.Draw(tmp)
    td.text((x,y),txt,font=f,fill=(*gcol,180))
    blr=tmp.filter(ImageFilter.GaussianBlur(gr))
    sc.paste(blr.convert("RGB"),(0,0),blr.split()[3])
    ImageDraw.Draw(sc).text((x,y),txt,font=f,fill=col)

def neon_ctext(sc,y,txt,f,col,gcol,gr=7):
    d=ImageDraw.Draw(sc); bb=d.textbbox((0,0),txt,font=f)
    neon_glow(sc,(SW-(bb[2]-bb[0]))//2,y,txt,f,col,gcol,gr)

# ── Asset loaders ────────────────────────────────────────────────────────────
_logo=_bgc=_bgg=None

def get_logo(sz=160):
    global _logo
    if _logo is None: _logo=Image.open(LOGO).convert("RGBA")
    return _logo.resize((sz,sz),Image.LANCZOS)

def _crop_bg(path):
    img=Image.open(path).convert("RGB")
    ar=img.width/img.height; tar=SW/SH
    if ar>tar:
        nw=int(img.height*tar); x0=(img.width-nw)//2
        img=img.crop((x0,0,x0+nw,img.height))
    else:
        nh=int(img.width/tar); y0=(img.height-nh)//2
        img=img.crop((0,y0,img.width,y0+nh))
    return img.resize((SW,SH),Image.LANCZOS)

def get_bgc():
    global _bgc
    if _bgc is None: _bgc=_crop_bg(BG_CYB)
    return _bgc.copy()

def get_bgg():
    global _bgg
    if _bgg is None: _bgg=_crop_bg(BG_GLASS)
    return _bgg.copy()

# ── Sample data ──────────────────────────────────────────────────────────────
ENTRIES=[
    {"site":"github.com",      "login":"dev@mail.com",       "c":(36,41,47),   "L":"G","fa":True },
    {"site":"gmail.com",       "login":"myemail@gmail.com",  "c":(234,67,53),  "L":"G","fa":False},
    {"site":"aws.amazon.com",  "login":"admin@company.io",   "c":(255,153,0),  "L":"A","fa":True },
    {"site":"figma.com",       "login":"designer@studio.co", "c":(162,89,255), "L":"F","fa":False},
    {"site":"notion.so",       "login":"notes@work.dev",     "c":(0,0,0),      "L":"N","fa":False},
]

def draw_card(sc,d,x,y,w,e,th,glass=False):
    h=72
    if glass:
        ol=Image.new("RGBA",(w,h),(0,0,0,0))
        gd=ImageDraw.Draw(ol)
        gd.rounded_rectangle([0,0,w-1,h-1],radius=14,fill=(255,255,255,30),
                               outline=(255,255,255,75),width=1)
        sc=sc.convert("RGBA"); sc.paste(ol,(x,y),ol.split()[3]); sc=sc.convert("RGB")
        d=ImageDraw.Draw(sc)
    else:
        rr(d,x,y,w,h,14,fill=th.inp); rr(d,x,y,w,h,14,outline=th.sec,width=1)
    r2=21; cx2=x+16+r2; cy2=y+h//2
    d.ellipse([cx2-r2,cy2-r2,cx2+r2,cy2+r2],fill=e["c"])
    lf=F(16,True); bb=d.textbbox((0,0),e["L"],font=lf)
    d.text((cx2-(bb[2]-bb[0])//2,cy2-(bb[3]-bb[1])//2-1),e["L"],font=lf,fill=(255,255,255))
    tx=cx2+r2+12
    d.text((tx,y+10),e["site"],font=F(15,True),fill=th.text)
    d.text((tx,y+32),e["login"],font=F(12),fill=th.sub)
    if e["fa"]:
        bw=34; bx2=x+w-56
        rr(d,bx2,y+27,bw,19,6,fill=dim(th.btn,0.2),outline=dim(th.btn,0.5),width=1)
        d.text((bx2+5,y+29),"2FA",font=F(10,True),fill=th.accent)
    return sc, d

# ═══════════════════════════════════════════════════════════════════════════
# SCREENS
# ═══════════════════════════════════════════════════════════════════════════

def Splash():
    sc=ns(D.bg)
    # Radial glow
    gd=ImageDraw.Draw(sc)
    for r2 in range(220,0,-12):
        a=int((1-r2/220)*35); c=mix(D.bg,D.btn,(1-r2/220)*0.25)
        gd.ellipse([SW//2-r2,SH//2-r2,SW//2+r2,SH//2+r2],outline=(*c,a),width=2)
    d=ImageDraw.Draw(sc); status(d,D)
    cy=SH//2-30
    # Logo (real raw.png, circular)
    logo=get_logo(168)
    cm=Image.new("L",(168,168),0); ImageDraw.Draw(cm).ellipse([0,0,167,167],fill=255)
    lx=(SW-168)//2; ly=cy-84
    sc.paste(logo.convert("RGB"),(lx,ly),cm)
    # Glow ring
    d=ImageDraw.Draw(sc)
    for r2,a2 in [(88,18),(76,32),(62,48)]:
        d.ellipse([SW//2-r2,cy-r2,SW//2+r2,cy+r2],outline=(*D.btn,a2),width=2)
    # ZERO
    y=ly+178; f=F(50,True)
    bb=d.textbbox((0,0),"ZERO",font=f); tw=bb[2]-bb[0]; tx=(SW-tw)//2
    d.text((tx+3,y+3),"ZERO",font=f,fill=dim(D.btn,0.25))
    d.text((tx,y),"ZERO",font=f,fill=D.btn)
    ctext(d,y+64,"Менеджер паролей",F(16),D.sub)
    dy=y+110
    for i in range(3):
        dx=SW//2-22+i*22; r2=5 if i==1 else 4
        d.ellipse([dx-r2,dy-r2,dx+r2,dy+r2],fill=(D.btn if i==1 else D.sec))
    return sc

def Login(th=D):
    sc=ns(th.bg); d=ImageDraw.Draw(sc); status(d,th)
    cy=STATH+50
    icon_box(sc,SW//2,cy+42,80,th)
    d=ImageDraw.Draw(sc)
    # lock symbol
    d.rectangle([SW//2-10,cy+28,SW//2+10,cy+36],outline=(255,255,255),width=2)
    d.rounded_rectangle([SW//2-12,cy+34,SW//2+12,cy+52],radius=3,fill=(255,255,255,180))
    d.ellipse([SW//2-3,cy+40,SW//2+3,cy+46],fill=th.btn)
    y=cy+94; f=F(46,True)
    bb=d.textbbox((0,0),"ZERO",font=f); tx=(SW-(bb[2]-bb[0]))//2
    d.text((tx+2,y+2),"ZERO",font=f,fill=dim(th.btn,0.28)); d.text((tx,y),"ZERO",font=f,fill=th.btn)
    ctext(d,y+62,"Менеджер паролей",F(15),th.sub)
    fx=26; fw=SW-52; fy=y+104
    inp(sc,d,fx,fy,fw,52,"Логин",th,val="user@example.com",icon="@"); fy+=65
    inp(sc,d,fx,fy,fw,52,"Пароль",th,val="password123",pw=True,icon="*"); fy+=65
    btn(sc,d,fx,fy,fw,52,"Войти",th); fy+=66
    ctext(d,fy,"Нет аккаунта? Зарегистрироваться",F(14),th.accent)
    return sc

def Signup(th=D):
    sc=ns(th.bg); d=ImageDraw.Draw(sc); status(d,th)
    cy=STATH+50
    icon_box(sc,SW//2,cy+42,80,th)
    d=ImageDraw.Draw(sc)
    # person+ icon
    d.ellipse([SW//2-12,cy+22,SW//2+12,cy+46],outline=(255,255,255),width=2)
    d.arc([SW//2-20,cy+44,SW//2+20,cy+64],0,180,fill=(255,255,255),width=2)
    d.text((SW//2+8,cy+22),"+",font=F(18,True),fill=(255,255,255))
    y=cy+94; f=F(46,True)
    bb=d.textbbox((0,0),"ZERO",font=f); tx=(SW-(bb[2]-bb[0]))//2
    d.text((tx+2,y+2),"ZERO",font=f,fill=dim(th.btn,0.28)); d.text((tx,y),"ZERO",font=f,fill=th.btn)
    ctext(d,y+62,"Создание аккаунта",F(15),th.sub)
    fx=26; fw=SW-52; fy=y+104
    inp(sc,d,fx,fy,fw,52,"Логин",th,val="new_user",icon="@"); fy+=65
    inp(sc,d,fx,fy,fw,52,"Пароль",th,val="SecurePass!",pw=True,icon="*"); fy+=65
    btn(sc,d,fx,fy,fw,52,"Зарегистрироваться",th); fy+=66
    ctext(d,fy,"Уже есть аккаунт? Войти",F(14),th.accent); fy+=46
    # 2FA hint
    rr(d,fx,fy,fw,62,12,fill=dim(th.btn,0.12),outline=dim(th.btn,0.4),width=1)
    d.text((fx+14,fy+12),"2FA — Настройте после регистрации",font=F(13),fill=th.accent)
    d.text((fx+14,fy+32),"для максимальной защиты аккаунта",font=F(12),fill=th.sub)
    d.text((fx+14,fy+48),"Google Auth / Microsoft Auth / Aegis",font=F(11),fill=th.sec)
    return sc

def Pin(th=D):
    sc=ns(th.bg); d=ImageDraw.Draw(sc); status(d,th)
    cy=SH//2-70
    icon_box(sc,SW//2,cy-52,74,th)
    d=ImageDraw.Draw(sc)
    d.rectangle([SW//2-10,cy-66,SW//2+10,cy-58],outline=(255,255,255),width=2)
    d.rounded_rectangle([SW//2-14,cy-60,SW//2+14,cy-38],radius=3,fill=(255,255,255,200))
    ctext(d,cy+8,"Введите PIN-код",F(24,True),th.text)
    ctext(d,cy+40,"Для доступа к приложению",F(14),th.sub)
    bsz=58; gap=14; total=4*bsz+3*gap; bx0=(SW-total)//2; by=cy+82
    for i in range(4):
        bx=bx0+i*(bsz+gap)
        rr(d,bx,by,bsz,bsz,12,fill=th.inp)
        if i<2:
            rr(d,bx,by,bsz,bsz,12,outline=th.btn,width=2)
            cx2=bx+bsz//2; cy2=by+bsz//2
            d.ellipse([cx2-10,cy2-10,cx2+10,cy2+10],fill=th.btn)
        else:
            rr(d,bx,by,bsz,bsz,12,outline=th.sec,width=1)
    bio_w=242; bio_y=by+bsz+44; bio_x=(SW-bio_w)//2
    btn(sc,d,bio_x,bio_y,bio_w,50,"  Использовать биометрию",th)
    d=ImageDraw.Draw(sc)
    for r2 in [14,10,6]:
        d.arc([bio_x+15-r2,bio_y+25-r2,bio_x+15+r2,bio_y+25+r2],200,340,fill=(255,255,255),width=1)
    ctext(d,bio_y+68,"Выйти",F(15),th.sub)
    return sc

def Passwords(th=D,bg=None):
    if bg:
        ov=Image.new("RGBA",(SW,SH),(*th.bg,210))
        sc=bg.convert("RGBA"); sc=Image.alpha_composite(sc,ov); sc=sc.convert("RGB")
    else:
        sc=ns(th.bg)
    d=ImageDraw.Draw(sc); status(d,th)
    cy=appbar(sc,d,th,"Пароли")
    for ix2,ic in [(SW-108,"⊕"),(SW-70,"⊞"),(SW-34,"⚙")]:
        d.text((ix2,STATH+18),ic,font=F(15,True),fill=th.accent)
    inp(sc,d,14,cy,SW-28,42,"  Поиск паролей…",th,icon="?"); cy+=54
    for e in ENTRIES:
        if cy+78>SH-60: break
        sc,d=draw_card(sc,d,14,cy,SW-28,e,th,glass=bool(bg)); cy+=82
    nav_bar(sc,d,th,0); return sc

def AddPassword(th=D):
    sc=ns(th.bg); d=ImageDraw.Draw(sc)
    cy=appbar(sc,d,th,"Добавление пароля",back=True)
    fx=20; fw=SW-40
    for hint,val,pw,ic in [("Сайт","github.com",False,"🌐"),
                             ("Логин","dev@example.com",False,"@"),
                             ("Пароль","SuperS3cret!",True,"*"),
                             ("Заметки","",False,"#")]:
        h=72 if hint=="Заметки" else 52
        inp(sc,d,fx,cy,fw,h,hint,th,val=val or None,pw=pw,icon=ic)
        if hint=="Пароль":
            rr(d,fx+fw-66,cy+h+4,60,22,8,fill=dim(th.btn,0.18),outline=dim(th.btn,0.4),width=1)
            d.text((fx+fw-60,cy+h+8),"↻ генер.",font=F(10),fill=th.accent)
        cy+=h+12
    cy+=6
    rr(d,fx,cy,fw,52,12,fill=th.inp,outline=th.sec,width=1)
    d.text((fx+14,cy+16),"Двухфакторная аутентификация",font=F(14),fill=th.text)
    toggle(sc,d,fx+fw-54,cy+14,on=True,th=th); d=ImageDraw.Draw(sc); cy+=62
    rr(d,fx,cy,fw,52,12,fill=th.inp,outline=th.sec,width=1)
    d.text((fx+14,cy+16),"Seed-фраза",font=F(14),fill=th.text)
    toggle(sc,d,fx+fw-54,cy+14,on=False,th=th); d=ImageDraw.Draw(sc); cy+=64
    btn(sc,d,fx,cy,fw,52,"Сохранить",th)
    return sc

def Settings(th=D):
    sc=ns(th.bg); d=ImageDraw.Draw(sc)
    cy=appbar(sc,d,th,"Настройки")
    ix=14; iw=SW-28
    SECS=[
        ("БЕЗОПАСНОСТЬ",[
            ("[]","PIN-код","PIN-код установлен",True,True),
            ("/","Скрыть seed-фразы","Включено",True,True),
            ("~","Биометрия","Отпечаток пальца",True,False),
            ("H","История паролей","Просмотреть",False,False),
        ]),
        ("ИНТЕРФЕЙС",[("*","Тема приложения",th.name,False,False)]),
        ("АККАУНТ",[
            ("@","Обновить favicon","Обновить иконки",False,False),
            ("→","Выйти","Завершить сессию",False,False),
        ]),
        ("О ПРИЛОЖЕНИИ",[("i","Версия","0.2.1",False,False)]),
    ]
    for sn,items in SECS:
        if cy+32>SH-70: break
        d.text((ix+4,cy+4),sn,font=F(11,True),fill=th.accent); cy+=26
        for icon,title,sub2,isw,son in items:
            if cy+58>SH-70: break
            rr(d,ix,cy,iw,58,12,fill=th.inp,outline=th.sec,width=1)
            rr(d,ix+10,cy+14,30,30,8,fill=dim(th.btn,0.22))
            d.text((ix+17,cy+18),icon,font=F(12,True),fill=th.btn)
            d.text((ix+50,cy+10),title,font=F(14,True),fill=th.text)
            d.text((ix+50,cy+30),sub2,font=F(12),fill=th.sub)
            if isw: toggle(sc,d,ix+iw-54,cy+17,on=son,th=th); d=ImageDraw.Draw(sc)
            else: d.text((ix+iw-16,cy+20),"›",font=F(20,True),fill=th.sub)
            cy+=66
        cy+=4
    if cy+68<SH-60:
        rr(d,ix,cy,iw,66,16,fill=dim(th.btn,0.08),outline=dim(th.btn,0.3),width=1)
        rr(d,ix+12,cy+12,44,44,10,fill=th.btn)
        d.text((ix+18,cy+21),"</>",font=F(12,True),fill=(255,255,255))
        d.text((ix+66,cy+13),"Создано NK_TRIPLLE",font=F(14,True),fill=th.text)
        d.text((ix+66,cy+34),"С любовью к безопасности",font=F(12),fill=th.sub)
    nav_bar(sc,d,th,1); return sc

def CyberpunkPasswords():
    bg=get_bgc()
    ov_a=dgrad((8,8,8),(16,4,18),(4,14,14),SW,SH)
    ov=Image.fromarray(ov_a.astype(np.uint8))
    sc=Image.blend(bg,ov,0.74)
    d=ImageDraw.Draw(sc); status(d,C)
    cy=appbar(sc,d,C,"Пароли")
    neon_ctext(sc,cy,"◈  CYBERPUNK  THEME  ◈",F(13,True),C.btn,C.accent,gr=8)
    d=ImageDraw.Draw(sc); cy+=28
    inp(sc,d,14,cy,SW-28,42,"  Поиск…",C,icon="?")
    d=ImageDraw.Draw(sc)
    d.rounded_rectangle([14,cy,SW-14,cy+42],radius=12,outline=(*C.btn,180),width=2); cy+=54
    for e in ENTRIES:
        if cy+78>SH-60: break
        h=72; rr(d,14,cy,SW-28,h,14,fill=(12,12,22))
        d.rounded_rectangle([14,cy,SW-14,cy+h],radius=14,outline=(*C.btn,210),width=2)
        d.rectangle([16,cy+8,21,cy+h-8],fill=C.btn)
        r2=21; cx2=32+r2; cy2=cy+h//2
        d.ellipse([cx2-r2,cy2-r2,cx2+r2,cy2+r2],fill=e["c"])
        lf=F(15,True); bb=d.textbbox((0,0),e["L"],font=lf)
        d.text((cx2-(bb[2]-bb[0])//2,cy2-(bb[3]-bb[1])//2-1),e["L"],font=lf,fill=(255,255,255))
        neon_glow(sc,cx2+r2+12,cy+10,e["site"],F(15,True),C.btn,C.btn,gr=4)
        d=ImageDraw.Draw(sc)
        d.text((cx2+r2+12,cy+32),e["login"],font=F(12),fill=C.sub)
        if e["fa"]:
            d.text((SW-52,cy+28),"2FA",font=F(11,True),fill=C.accent)
        cy+=82
    nav_bar(sc,d,C,0); return sc

def GlassPasswords():
    bg=get_bgg().filter(ImageFilter.GaussianBlur(4))
    ov_a=dgrad((25,25,42),(38,32,58),(44,38,68),SW,SH)
    ov=Image.fromarray(ov_a.astype(np.uint8))
    sc=Image.blend(bg,ov,0.58)
    # Decorative blobs
    blob=Image.new("RGBA",(SW,SH),(0,0,0,0))
    bd=ImageDraw.Draw(blob)
    bd.ellipse([20,90,190,290],fill=(137,180,250,45))
    bd.ellipse([SW-200,220,SW-20,430],fill=(180,190,254,35))
    blob=blob.filter(ImageFilter.GaussianBlur(35))
    sc=sc.convert("RGBA"); sc=Image.alpha_composite(sc,blob); sc=sc.convert("RGB")
    d=ImageDraw.Draw(sc); status(d,G)
    cy=appbar(sc,d,G,"Пароли")
    ctext(d,cy,"✦  GLASSMORPHISM  THEME  ✦",F(13,True),G.accent); cy+=28
    inp(sc,d,14,cy,SW-28,42,"  Поиск…",G,icon="?")
    d=ImageDraw.Draw(sc)
    d.rounded_rectangle([14,cy,SW-14,cy+42],radius=12,outline=(255,255,255,90),width=1); cy+=54
    for e in ENTRIES:
        if cy+78>SH-60: break
        sc,d=draw_card(sc,d,14,cy,SW-28,e,G,glass=True); cy+=82
    nav_bar(sc,d,G,0); return sc

# ── Transition ───────────────────────────────────────────────────────────────
def trans(a,b,n=3):
    return [Image.blend(a,b,(i+1)/(n+1)) for i in range(n)]

def to_p(img):
    return img.convert("P",palette=Image.ADAPTIVE,colors=240,dither=0)

# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    print("Rendering screens …")
    screens=dict(
        splash=Splash(), login=Login(), signup=Signup(),
        pin=Pin(), passwords=Passwords(), add=AddPassword(),
        edit=Settings(), settings=Settings(),
        cyberpunk=CyberpunkPasswords(), glass=GlassPasswords()
    )
    print("Building phone frames …")
    frames={k:phone_frame(v) for k,v in screens.items()}

    HOLD=2800; HLNG=3600; TR=70
    order=["splash","login","signup","pin","passwords","add","settings","cyberpunk","glass","splash"]
    seq=[]
    for i in range(len(order)-1):
        a,b=order[i],order[i+1]
        h=HLNG if b in("cyberpunk","glass") else HOLD
        seq+=[(frames[a],h)]+[(f,TR) for f in trans(frames[a],frames[b],3)]
    seq+=[(frames["splash"],HOLD)]

    print(f"Quantizing {len(seq)} frames …")
    gframes=[to_p(f) for f,_ in seq]
    gdurs=[d for _,d in seq]
    os.makedirs("assets",exist_ok=True)
    gframes[0].save("assets/demo.gif",save_all=True,append_images=gframes[1:],
                     duration=gdurs,loop=0,optimize=False)
    kb=os.path.getsize("assets/demo.gif")//1024
    print(f"Done  assets/demo.gif  ({kb} KB, {len(gframes)} frames)")

if __name__=="__main__":
    main()
