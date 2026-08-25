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
  tests/install-lifecycle.sh tests/fixtures/shell-fixture.json
  tests/fixtures/theme.name tests/fixtures/autostart.lua
  tests/fixtures/autostart-restored.lua
  tests/fixtures/legacy-plugin/manifest.json
  tests/fixtures/legacy-plugin/BarWidget.qml
  tests/fixtures/legacy-plugin/prototype.txt
  tests/fixtures/bin/omarchy tests/fixtures/bin/omarchy-shell
  tests/fixtures/bin/hyprctl tests/fixtures/bin/cava tests/fixtures/bin/mpvpaper
)
for path in "${required[@]}"; do
  [[ -f $path ]] || fail "missing $path"
done

[[ -z $(find . -type l -print -quit) ]] || fail "symlinks are not allowed"
[[ -z $(find . -type f -name shell.json -print -quit) ]] || fail "full shell.json files must not be shipped"
if rg -n --hidden --glob '!.git/**' --glob '!*.png' --glob '!*.jpg' --glob '!*.mp4' '/home/[[:alnum:]_.-]+/' .; then
  fail "found a hard-coded home directory"
fi
if rg -n 'sloth\.cava|"author"[[:space:]]*:[[:space:]]*"sloth"' extras/plugin; then
  fail "found a legacy plugin identity"
fi

jq -e '
  .schemaVersion == 1 and
  .id == "neon-overdrive.cava" and
  .author == "0xsl0th" and
  (.kinds | index("service")) != null and
  (.kinds | index("bar-widget")) != null and
  .barWidget.defaults.wallpaperReactive == true and
  .barWidget.defaults.wallpaperIntensity == 60
' \
  extras/plugin/manifest.json >/dev/null

cava_bars=$(awk -F= '$1 ~ /^[[:space:]]*bars[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print $2 }' extras/plugin/cava.conf)
service_bars=$(sed -n 's/.*readonly property int barCount: \([0-9][0-9]*\).*/\1/p' extras/plugin/Service.qml)
[[ -n $cava_bars && $cava_bars == "$service_bars" ]] || fail "Cava and service bar counts differ"

grep -Fq 'input-ipc-server=$ipc_socket' extras/wallpaper/neon-overdrive-wallpaper || \
  fail "wallpaper IPC socket is not configured"
grep -Fq 'wallpaper_status()' extras/wallpaper/neon-overdrive-wallpaper || \
  fail "wallpaper launcher has no readiness check"
grep -Fq 'ready_file=' extras/wallpaper/neon-overdrive-wallpaper || \
  fail "wallpaper launcher has no post-handoff ready marker"
grep -Fq 'wait_for_wallpaper 10' install.sh || \
  fail "installer does not verify stable wallpaper readiness"
grep -Fq 'Socket {' extras/plugin/Service.qml || fail "reactive service has no persistent wallpaper socket"
grep -Fq 'sendWallpaperGrade(true)' extras/plugin/Service.qml || fail "reactive wallpaper has no neutral reset"
luac -p hyprland.lua
bash -n install.sh uninstall.sh validate.sh extras/wallpaper/neon-overdrive-wallpaper \
  tests/install-lifecycle.sh tests/fixtures/bin/*
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

grep -aFq 'OpenAI Media Service' neon-city-source.png || fail "source C2PA signer is missing"
grep -aFq 'c2pa.claim.v2' neon-city-source.png || fail "source C2PA claim is missing"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh uninstall.sh validate.sh extras/wallpaper/neon-overdrive-wallpaper \
    tests/install-lifecycle.sh tests/fixtures/bin/*
fi

qmlformat_bin=""
command -v qmlformat >/dev/null 2>&1 && qmlformat_bin=$(command -v qmlformat)
[[ -n $qmlformat_bin || ! -x /usr/lib/qt6/bin/qmlformat ]] || qmlformat_bin=/usr/lib/qt6/bin/qmlformat
if [[ -n $qmlformat_bin ]]; then
  "$qmlformat_bin" extras/plugin/Service.qml >/dev/null
  "$qmlformat_bin" extras/plugin/BarWidget.qml >/dev/null
fi

if [[ ${NEON_OVERDRIVE_SKIP_LIFECYCLE_TEST:-false} != true ]]; then
  NEON_OVERDRIVE_SKIP_LIFECYCLE_TEST=true "$repo_dir/tests/install-lifecycle.sh"
fi

printf 'Neon Overdrive validation passed.\n'
