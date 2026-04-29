#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$SCRIPT_DIR" "${1:-120}" << 'PYEOF'
import sys, os, struct, json, random

script_dir  = sys.argv[1]
columns     = int(sys.argv[2])
cfg_path    = os.path.join(script_dir, 'config.jsonc')
sprites_dir = os.path.join(script_dir, 'pictures', 'pokemon_sprites')
symlink     = os.path.join(script_dir, 'pictures', 'random.png')

MAX_LOGO_W      = 34
REF_IMG_W       = 512
MIN_LOGO_W      = 10
OFFSET_OVERHEAD = 2  # logo padding (left+right=2) + Kitty rendering overhead (4), -4 for deferred wrap
BOT_PAD         = 1

def png_size(path):
    with open(path, 'rb') as f:
        f.read(16)  # PNG signature (8) + IHDR length (4) + type (4)
        return struct.unpack('>2I', f.read(8))

with open(cfg_path) as f:
    cfg = json.load(f)

box_w      = len(cfg['display']['constants'][0]) + 2
max_logo_w = columns - box_w - OFFSET_OVERHEAD

if max_logo_w < MIN_LOGO_W:
    sys.exit(1)

fitting = []
for name in os.listdir(sprites_dir):
    if not name.endswith('.png'):
        continue
    path = os.path.join(sprites_dir, name)
    img_w, img_h = png_size(path)
    logo_w = max(MIN_LOGO_W, min(MAX_LOGO_W, round(MAX_LOGO_W * img_w / REF_IMG_W)))
    if logo_w <= max_logo_w:
        fitting.append((path, img_w, img_h, logo_w))

if not fitting:
    sys.exit(1)

path, img_w, img_h, logo_w = random.choice(fitting)

if os.path.lexists(symlink):
    os.remove(symlink)
os.symlink(os.path.join('pokemon_sprites', os.path.basename(path)), symlink)

pad_top = cfg['logo']['padding'].get('top', 0)
max_h   = len(cfg['modules']) - pad_top - BOT_PAD
ideal_h = round(logo_w * img_h / (img_w * 2))

cfg['logo']['width']  = logo_w
cfg['logo']['height'] = max(1, min(ideal_h, max_h))

output = json.dumps(cfg, indent=4, ensure_ascii=False)
output = output.replace('\x1b', '\\u001b')
with open(cfg_path, 'w') as f:
    f.write(output)
    f.write('\n')
PYEOF
