#!/bin/bash

# Get the directory where this script is located
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
