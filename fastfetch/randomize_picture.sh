#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICTURES_DIR="$SCRIPT_DIR/pictures"
SPRITES_DIR="$PICTURES_DIR/pokemon_sprites"
SYMLINK="$PICTURES_DIR/random.png"

# Find all PNG files and select one at random
RANDOM_SPRITE=$(find "$SPRITES_DIR" -maxdepth 1 -name "*.png" -type f | shuf -n 1)

# Remove old symlink if it exists
rm -f "$SYMLINK"

# Create new symlink
ln -s "pokemon_sprites/$(basename "$RANDOM_SPRITE")" "$SYMLINK"

# Adjust logo height to match sprite aspect ratio, capped to info box height
python3 - "$RANDOM_SPRITE" "$SCRIPT_DIR/config.jsonc" << 'PYEOF'
import sys, struct, json

def png_size(path):
    with open(path, 'rb') as f:
        f.read(16)  # PNG signature (8) + IHDR length (4) + type (4)
        w = struct.unpack('>I', f.read(4))[0]
        h = struct.unpack('>I', f.read(4))[0]
    return w, h

img_path, cfg_path = sys.argv[1], sys.argv[2]
img_w, img_h = png_size(img_path)

with open(cfg_path) as f:
    cfg = json.load(f)

MAX_LOGO_W = 34   # display chars for a full-size sprite
REF_IMG_W  = 512  # pixel width that maps to MAX_LOGO_W chars
MIN_LOGO_W = 10

pad_top  = cfg['logo']['padding'].get('top', 0)
bot_pad  = 1  # empty rows to leave below the logo
max_h    = len(cfg['modules']) - pad_top - bot_pad

# scale display width proportionally to pixel size
logo_w  = max(MIN_LOGO_W, min(MAX_LOGO_W, round(MAX_LOGO_W * img_w / REF_IMG_W)))
# derive height from scaled width + aspect ratio, capped to box height
ideal_h = round(logo_w * img_h / (img_w * 2))

cfg['logo']['width']  = logo_w
cfg['logo']['height'] = max(1, min(ideal_h, max_h))

with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=4, ensure_ascii=False)
    f.write('\n')
PYEOF
