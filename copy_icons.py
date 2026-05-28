from PIL import Image
import os
import shutil

SRC = r'C:\Users\acer\Downloads\lakadiya-icons'

ANDROID_BASE = r'c:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\mobile\android\app\src\main\res'
IOS_BASE     = r'c:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\mobile\ios\Runner\Assets.xcassets\AppIcon.appiconset'

# Load available source icons (keyed by size)
available = {}
for f in os.listdir(SRC):
    if f.startswith('icon-') and f.endswith('.png'):
        try:
            sz = int(f[5:-4])
            available[sz] = os.path.join(SRC, f)
        except ValueError:
            pass

print('Available source sizes:', sorted(available.keys()))

master = Image.open(available[1024]).convert('RGBA')


def best_source(target_sz):
    """Pick the smallest available source >= target, else 1024."""
    candidates = [s for s in available if s >= target_sz]
    if candidates:
        return Image.open(available[min(candidates)]).convert('RGBA')
    return master.copy()


def resize_and_save(target_sz, out_path):
    src_img = best_source(target_sz)
    out = src_img.resize((target_sz, target_sz), Image.LANCZOS)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path)


# ── Android ───────────────────────────────────────────────────────────────────
android_map = {
    'mipmap-mdpi':    48,
    'mipmap-hdpi':    72,
    'mipmap-xhdpi':   96,
    'mipmap-xxhdpi':  144,
    'mipmap-xxxhdpi': 192,
}

print('\n=== Android ===')
for folder, sz in android_map.items():
    out = os.path.join(ANDROID_BASE, folder, 'ic_launcher.png')
    if sz in available:
        shutil.copy2(available[sz], out)
        print(f'  {folder}: copied icon-{sz}.png')
    else:
        resize_and_save(sz, out)
        print(f'  {folder}: resized from master → {sz}x{sz}')

# ── iOS ───────────────────────────────────────────────────────────────────────
ios_map = {
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

print('\n=== iOS ===')
for filename, sz in ios_map.items():
    out = os.path.join(IOS_BASE, filename)
    if sz in available:
        # iOS icons must be RGB (no alpha)
        src_img = Image.open(available[sz]).convert('RGB')
        src_img.save(out)
        print(f'  {filename}: copied icon-{sz}.png')
    else:
        src_img = best_source(sz)
        out_img = src_img.resize((sz, sz), Image.LANCZOS).convert('RGB')
        out_img.save(out)
        print(f'  {filename}: resized -> {sz}x{sz}')

print('\nAll icons installed.')
