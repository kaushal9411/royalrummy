from PIL import Image, ImageDraw, ImageFont
import os

# ── Color Palette ─────────────────────────────────────────────────────────────
CARD_TOP   = (135, 8,   8)
CARD_MID   = (88,  4,   4)
CARD_BOT   = (42,  2,   2)
FIRE_TINT  = (110, 18,  0)
GOLD       = (200, 152, 8)
GOLD_L     = (255, 222, 88)
GOLD_B     = (255, 244, 165)
GOLD_D     = (115, 82,  2)
SPADE_C    = (8,   8,   14)
SPADE_SH   = (205, 215, 232)   # Bright silver — visible on dark red
FIRE_Y     = (255, 238, 28)
FIRE_O     = (255, 132, 0)
FIRE_R     = (215, 32,  0)
FIRE_DR    = (118, 8,   0)
TEXT_G     = (232, 185, 58)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_icon(size):
    img  = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = max(3, int(size * 0.035))
    r   = int(size * 0.13)
    cx, cy = size // 2, size // 2
    bw  = max(2, size // 52)

    x1, y1 = pad, pad
    x2, y2 = size - pad, size - pad
    card_w  = x2 - x1

    fire_base = y2 + int(size * 0.04)
    fire_h    = int(size * 0.34)
    fire_w    = int(card_w * 0.92)

    # ── Flame drawing helper ───────────────────────────────────────────────────
    def draw_flames(alpha_mult=1.0):
        tongues = [
            (-0.40, 0.55, 0.16),
            (-0.22, 0.80, 0.20),
            (-0.08, 0.97, 0.24),
            ( 0.00, 1.00, 0.28),
            ( 0.10, 0.96, 0.24),
            ( 0.24, 0.78, 0.20),
            ( 0.38, 0.58, 0.16),
        ]
        for tx, th, tw in tongues:
            tcx  = cx + int(fire_w * tx)
            t_h  = int(fire_h * th)
            t_w  = int(fire_w * tw)
            steps = max(12, t_h // 3)
            for j in range(steps, 0, -1):
                frac = (steps - j) / steps
                y    = fire_base - int(t_h * frac)
                w    = max(2, int(t_w * (1 - frac * 0.90)))
                if frac < 0.15:
                    c, a = FIRE_Y, 250
                elif frac < 0.42:
                    c, a = FIRE_O, 235
                elif frac < 0.70:
                    c, a = FIRE_R, 215
                else:
                    c = FIRE_DR
                    a = max(0, int(185 * (1 - (frac - 0.70) / 0.30)))
                a = int(a * alpha_mult)
                eh = max(3, t_h // steps * 4)
                draw.ellipse([tcx - w//2, y - eh//2, tcx + w//2, y + eh//2],
                             fill=(*c, a))

        # Wide base glow strip
        bs = max(8, int(size * 0.05))
        for i in range(bs, 0, -1):
            t = (bs - i) / bs
            w = int(fire_w * (1 - t * 0.22))
            a = int(240 * (1 - t * 0.55) * alpha_mult)
            c = FIRE_Y if t < 0.20 else (FIRE_O if t < 0.52 else FIRE_R)
            yb = fire_base - int(fire_h * 0.14 * t)
            eh = max(2, size // 44)
            draw.ellipse([cx - w//2, yb - eh, cx + w//2, yb + eh], fill=(*c, a))

    # ── PASS 1: flames behind card ─────────────────────────────────────────────
    draw_flames(0.50)

    # ── Card gradient background ───────────────────────────────────────────────
    grad = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd   = ImageDraw.Draw(grad)
    for y in range(y1, y2 + 1):
        t = (y - y1) / max(1, y2 - y1)
        if t < 0.42:
            c = lerp(CARD_TOP, CARD_MID, t / 0.42)
        elif t < 0.76:
            c = lerp(CARD_MID, CARD_BOT, (t - 0.42) / 0.34)
        else:
            # Fire tint near bottom
            c = lerp(CARD_BOT, FIRE_TINT, (t - 0.76) / 0.24 * 0.70)
        gd.line([(x1, y), (x2, y)], fill=(*c, 255))

    mask = Image.new('L', (size, size), 0)
    md   = ImageDraw.Draw(mask)
    md.rounded_rectangle([x1, y1, x2, y2], radius=r, fill=255)
    img.paste(grad, (0, 0), mask=mask)
    draw = ImageDraw.Draw(img)

    # Subtle top-center highlight (stays inside card)
    hl_r = int(size * 0.28)
    for i in range(hl_r, 0, -max(1, hl_r // 16)):
        t = i / hl_r
        a = int(26 * t * t)
        ey0 = y1 + int(size * 0.01)
        ey1 = y1 + max(int(size * 0.015), int(i * 0.52))
        draw.ellipse([cx - i, ey0, cx + i, ey1], fill=(190, 50, 50, a))

    # ── Card borders ───────────────────────────────────────────────────────────
    # Outer gold glow
    gs = min(7, max(2, size // 38))
    for i in range(gs, 0, -1):
        t = i / gs
        a = int(58 * t)
        draw.rounded_rectangle(
            [x1 - i, y1 - i, x2 + i, y2 + i],
            radius=r + i, outline=(*GOLD_D, a), width=1
        )
    # Dark shadow border
    draw.rounded_rectangle([x1, y1, x2, y2], radius=r, outline=GOLD_D, width=bw + 1)
    # Main gold border
    draw.rounded_rectangle([x1+1, y1+1, x2-1, y2-1], radius=r-1, outline=GOLD, width=bw)
    # Inner bright highlight
    ih_x1, ih_y1, ih_x2, ih_y2 = x1+bw+2, y1+bw+2, x2-bw-2, y2-bw-2
    if ih_x1 < ih_x2 and ih_y1 < ih_y2:
        draw.rounded_rectangle([ih_x1, ih_y1, ih_x2, ih_y2],
                               radius=max(1, r-bw-2), outline=(*GOLD_B, 130), width=1)
    # Thin inner frame (authentic playing-card style)
    ip = bw + int(size * 0.024)
    if x1+ip < x2-ip and y1+ip < y2-ip:
        draw.rounded_rectangle(
            [x1+ip, y1+ip, x2-ip, y2-ip],
            radius=max(1, r - ip),
            outline=(255, 255, 255, 30), width=1
        )

    # ── Fonts ──────────────────────────────────────────────────────────────────
    sym_big = int(size * 0.37)
    sym_sm  = int(size * 0.096)
    ace_sz  = int(size * 0.155)

    try:
        fb = ImageFont.truetype('C:/Windows/Fonts/seguisym.ttf', sym_big)
        fs = ImageFont.truetype('C:/Windows/Fonts/seguisym.ttf', sym_sm)
    except Exception as e:
        print(f'Symbol font: {e}')
        return img

    fa = None
    for name in ('georgiab.ttf', 'timesbd.ttf', 'arialbd.ttf', 'calibrib.ttf', 'arial.ttf'):
        try:
            fa = ImageFont.truetype(f'C:/Windows/Fonts/{name}', ace_sz)
            break
        except:
            pass
    if fa is None:
        fa = ImageFont.load_default()

    # ── Central Spade ─────────────────────────────────────────────────────────
    hero_y = int(cy - size * 0.06)   # Slightly above centre, gives room top + bottom
    bb     = draw.textbbox((0, 0), '♠', font=fb)
    sw, sh = bb[2] - bb[0], bb[3] - bb[1]
    tx, ty = cx - sw // 2, hero_y - sh // 2

    # Drop shadow (subtle)
    sd = max(2, size // 100)
    draw.text((tx + sd, ty + sd), '♠', font=fb, fill=(0, 0, 0, 80))

    # Bright silver metallic outline
    ow = max(2, size // 65)
    for dx in range(-ow, ow + 1):
        for dy in range(-ow, ow + 1):
            if dx * dx + dy * dy <= ow * ow + 1:
                draw.text((tx + dx, ty + dy), '♠', font=fb, fill=(*SPADE_SH, 210))

    # Main dark spade on top
    draw.text((tx, ty), '♠', font=fb, fill=SPADE_C)

    # ── "A" corner labels ─────────────────────────────────────────────────────
    def render_corner(rotated=False):
        sub_w = int(size * 0.195)
        sub_h = int(size * 0.250)
        sub   = Image.new('RGBA', (sub_w, sub_h), (0, 0, 0, 0))
        sd    = ImageDraw.Draw(sub)

        # "A"
        bb2 = sd.textbbox((0, 0), 'A', font=fa)
        aw, ah = bb2[2] - bb2[0], bb2[3] - bb2[1]
        atx = sub_w // 2 - aw // 2
        aty = int(sub_h * 0.08)

        # Gold outline
        ov = max(1, size // 215)
        for ddx in range(-ov - 1, ov + 2):
            for ddy in range(-ov - 1, ov + 2):
                if abs(ddx) + abs(ddy) <= ov + 1:
                    sd.text((atx + ddx, aty + ddy), 'A', font=fa, fill=(*GOLD_D, 200))
        sd.text((atx, aty), 'A', font=fa, fill=TEXT_G)

        # Small spade below
        bb3  = sd.textbbox((0, 0), '♠', font=fs)
        sw2, sh2 = bb3[2] - bb3[0], bb3[3] - bb3[1]
        stx = sub_w // 2 - sw2 // 2
        sty = aty + ah + int(sub_h * 0.05)
        sd.text((stx, sty), '♠', font=fs, fill=TEXT_G)

        if rotated:
            sub = sub.rotate(180)
        return sub

    if size >= 60:
        # Top-left
        corner_tl = render_corner(rotated=False)
        cw, ch = corner_tl.size
        tl_x = x1 + int(size * 0.050)
        tl_y = y1 + int(size * 0.048)
        img.paste(corner_tl, (tl_x, tl_y), mask=corner_tl)

        # Bottom-right (rotated)
        corner_br = render_corner(rotated=True)
        br_x = x2 - int(size * 0.050) - cw
        br_y = y2 - int(size * 0.048) - ch
        img.paste(corner_br, (br_x, br_y), mask=corner_br)

    draw = ImageDraw.Draw(img)

    # ── PASS 2: flames in front ────────────────────────────────────────────────
    draw_flames(1.0)

    # ── Ember sparks ───────────────────────────────────────────────────────────
    if size >= 72:
        import random
        random.seed(7)
        for _ in range(max(4, size // 28)):
            sx = cx + random.randint(-int(fire_w * 0.42), int(fire_w * 0.42))
            sy = fire_base - random.randint(int(fire_h * 0.10), int(fire_h * 0.82))
            sr = max(1, random.randint(1, max(2, size // 85)))
            sc = random.choice([FIRE_Y, FIRE_O, FIRE_R])
            a  = random.randint(145, 235)
            draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(*sc, a))

    return img


def make_ios_icon(size):
    rgba = make_icon(size)
    bg   = Image.new('RGBA', (size, size), (0, 0, 0, 255))
    return Image.alpha_composite(bg, rgba).convert('RGB')


# ── Android ───────────────────────────────────────────────────────────────────
android_sizes = {
    'mipmap-mdpi':    48,
    'mipmap-hdpi':    72,
    'mipmap-xhdpi':   96,
    'mipmap-xxhdpi':  144,
    'mipmap-xxxhdpi': 192,
}
android_base = r'c:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\mobile\android\app\src\main\res'

print('Rendering master at 1024px …')
master = make_icon(1024)

print('\n=== Android ===')
for folder, sz in android_sizes.items():
    out     = os.path.join(android_base, folder, 'ic_launcher.png')
    resized = master.resize((sz, sz), Image.LANCZOS)
    bg      = Image.new('RGBA', (sz, sz), (0, 0, 0, 255))
    final   = Image.alpha_composite(bg, resized)
    final.convert('RGB').save(out)
    print(f'  {folder}: {sz}x{sz}')

# ── iOS ───────────────────────────────────────────────────────────────────────
ios_sizes = {
    'Icon-App-20x20@1x.png':      20,
    'Icon-App-20x20@2x.png':      40,
    'Icon-App-20x20@3x.png':      60,
    'Icon-App-29x29@1x.png':      29,
    'Icon-App-29x29@2x.png':      58,
    'Icon-App-29x29@3x.png':      87,
    'Icon-App-40x40@1x.png':      40,
    'Icon-App-40x40@2x.png':      80,
    'Icon-App-40x40@3x.png':     120,
    'Icon-App-60x60@2x.png':     120,
    'Icon-App-60x60@3x.png':     180,
    'Icon-App-76x76@1x.png':      76,
    'Icon-App-76x76@2x.png':     152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
}
ios_base = r'c:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\mobile\ios\Runner\Assets.xcassets\AppIcon.appiconset'

print('\n=== iOS ===')
for filename, sz in ios_sizes.items():
    out  = os.path.join(ios_base, filename)
    icon = make_ios_icon(sz)
    icon.save(out)
    print(f'  {filename}: {sz}x{sz}')

print('\nDone — trump card icons generated.')
