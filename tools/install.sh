#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
source_dir="$(cd -- "$script_dir/../addon/npc_sitter" && pwd -P)"
if [[ $# -gt 0 ]]; then
    gmod_dir="$1"
else
    gmod_dir="$HOME/.local/share/Steam/steamapps/common/GarrysMod/garrysmod"
fi
if [[ ! -d "$source_dir/lua" ]]; then echo "Addon source not found: $source_dir" >&2; exit 1; fi
if [[ ! -d "$gmod_dir/addons" ]]; then echo "Invalid Garrys Mod folder: $gmod_dir" >&2; exit 1; fi
gmod_dir="$(cd -- "$gmod_dir" && pwd -P)"
if [[ "$(basename -- "$gmod_dir")" != "garrysmod" ]]; then echo "Expected the garrysmod directory" >&2; exit 1; fi
dest="$gmod_dir/addons/npc_sitter"
if [[ "$source_dir" == "$dest" ]]; then echo "Source and destination must be different" >&2; exit 1; fi
if [[ -e "$dest" || -L "$dest" ]]; then
    echo "Removing old NPC Sitter..."
    rm -rf -- "$dest"
fi
mkdir -p -- "$dest"
cp -a -- "$source_dir/." "$dest/"
echo "NPC Sitter installed to: $dest"
