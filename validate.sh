#!/usr/bin/env bash

set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd -- "$repo_dir"

fail() {
  printf 'Validation failed: %s\n' "$*" >&2
  exit 1
}

required=(
  colors.toml hyprland.lua icons.theme
  preview.png preview-unlock.png unlock.png
  shell.bar.toml shell.launcher.toml shell.lock.toml shell.menu.toml
  shell.notifications.toml shell.popups.toml shell.tooltip.toml
  backgrounds/neon-city-poster.jpg neon-city-source.png
  assets/neon-city-loop.mp4 extras/plugin/manifest.json
  extras/plugin/Service.qml extras/plugin/BarWidget.qml extras/plugin/cava.conf
  extras/wallpaper/neon-overdrive-wallpaper
)
for path in "${required[@]}"; do
  [[ -f $path ]] || fail "missing $path"
done

[[ -z $(find . -type l -print -quit) ]] || fail "symlinks are not allowed"
[[ -z $(find . -type f -name shell.json -print -quit) ]] || fail "full shell.json files must not be shipped"
if rg -n --hidden --glob '!*.png' --glob '!*.jpg' --glob '!*.mp4' '/home/[[:alnum:]_.-]+/' .; then
  fail "found a hard-coded home directory"
fi
if rg -n --hidden --glob '!*.png' --glob '!*.jpg' --glob '!*.mp4' 'sloth\.cava|"author"[[:space:]]*:[[:space:]]*"sloth"' .; then
  fail "found a legacy plugin identity"
fi

jq -e '.schemaVersion == 1 and .id == "neon-overdrive.cava" and .author == "0xsl0th"' \
  extras/plugin/manifest.json >/dev/null
luac -p hyprland.lua
bash -n install.sh uninstall.sh validate.sh extras/wallpaper/neon-overdrive-wallpaper
sha256sum -c ASSETS.sha256

# Guard the non-destructive autostart update invariant: managed markers must be
# ordered, and generated Lua must be checked before it replaces the live file.
for script in install.sh uninstall.sh; do
  grep -Fq 'end_line > begin_line' "$script" || fail "$script does not reject reversed autostart markers"
  validation_line=$(grep -nF 'luac -p "$autostart_tmp"' "$script" | head -n 1 | cut -d: -f1)
  replacement_line=$(grep -nF 'mv -- "$autostart_tmp" "$autostart_file"' "$script" | head -n 1 | cut -d: -f1)
  [[ -n $validation_line && -n $replacement_line && $validation_line -lt $replacement_line ]] || \
    fail "$script does not validate staged autostart Lua before replacement"
done

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate extras/plugin
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$repo_dir" <<'PY'
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
for path in sorted(root.glob("*.toml")):
    with path.open("rb") as handle:
        tomllib.load(handle)
PY
fi

if command -v ffprobe >/dev/null 2>&1; then
  video_json=$(ffprobe -v error -show_entries stream=codec_name,codec_type,width,height,r_frame_rate -show_entries format=duration -of json assets/neon-city-loop.mp4)
  jq -e '
    (.streams | length) == 1 and
    .streams[0].codec_type == "video" and
    .streams[0].codec_name == "h264" and
    .streams[0].width == 960 and
    .streams[0].height == 600 and
    .streams[0].r_frame_rate == "6/1" and
    ((.format.duration | tonumber) == 12)
  ' <<<"$video_json" >/dev/null || fail "unexpected wallpaper encoding"
fi

if command -v strings >/dev/null 2>&1; then
  strings -a neon-city-source.png | grep -Fq 'OpenAI Media Service' || fail "source C2PA signer is missing"
  strings -a neon-city-source.png | grep -Fq 'c2pa.claim.v2' || fail "source C2PA claim is missing"
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh uninstall.sh validate.sh extras/wallpaper/neon-overdrive-wallpaper
fi

printf 'Neon Overdrive validation passed.\n'
