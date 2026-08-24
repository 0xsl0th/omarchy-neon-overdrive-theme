#!/usr/bin/env bash

set -Eeuo pipefail

theme_name="neon-overdrive"
plugin_id="neon-overdrive.cava"
begin_marker="-- BEGIN NEON OVERDRIVE MANAGED BLOCK"
end_marker="-- END NEON OVERDRIVE MANAGED BLOCK"

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
theme_dir="$config_home/omarchy/themes/$theme_name"
plugin_dir="$config_home/omarchy/plugins/$plugin_id"
autostart_file="$config_home/hypr/autostart.lua"
wallpaper_bin="$HOME/.local/bin/neon-overdrive-wallpaper"
wallpaper_dir="$data_home/neon-overdrive"
wallpaper_file="$wallpaper_dir/neon-city-loop.mp4"
state_dir="$state_home/neon-overdrive"
state_file="$state_dir/install-state.env"

install_deps=false
check_only=false
start_wallpaper=true

usage() {
  cat <<'EOF'
Usage: ./install.sh [--check] [--install-deps] [--no-start]

  --check         Validate the project and report missing runtime dependencies.
  --install-deps  Install missing Cava/mpvpaper packages through the Omarchy CLI.
  --no-start      Install everything but start the live wallpaper on next login.
EOF
}

die() {
  printf 'Neon Overdrive installer: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Neon Overdrive installer: warning: %s\n' "$*" >&2
}

while (($#)); do
  case "$1" in
    --check) check_only=true ;;
    --install-deps) install_deps=true ;;
    --no-start) start_wallpaper=false ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

((EUID != 0)) || die "run this as your desktop user, not root"
command -v omarchy >/dev/null 2>&1 || die "Omarchy is required"
command -v jq >/dev/null 2>&1 || die "jq is required by Omarchy"
"$repo_dir/validate.sh"

missing=()
command -v cava >/dev/null 2>&1 || missing+=(cava)
command -v mpvpaper >/dev/null 2>&1 || missing+=(mpvpaper)

if ((${#missing[@]})); then
  printf 'Missing runtime dependencies: %s\n' "${missing[*]}" >&2
  printf '  cava:     omarchy pkg add cava\n' >&2
  printf '  mpvpaper: omarchy pkg aur add mpvpaper\n' >&2

  if ! $install_deps && [[ -t 0 ]]; then
    read -r -p 'Install the missing dependencies now? [y/N] ' answer
    [[ $answer =~ ^[Yy]$ ]] && install_deps=true
  fi

  if $install_deps; then
    for dependency in "${missing[@]}"; do
      case "$dependency" in
        cava) omarchy pkg add cava ;;
        mpvpaper) omarchy pkg aur add mpvpaper ;;
      esac
    done
  elif ! $check_only; then
    die "dependencies are missing; rerun with --install-deps"
  fi
fi

if $check_only; then
  ((${#missing[@]} == 0)) || exit 1
  printf 'Neon Overdrive preflight passed.\n'
  exit 0
fi

command -v cava >/dev/null 2>&1 || die "cava is still unavailable"
command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper is still unavailable"

repo_real=$(realpath -m -- "$repo_dir")
theme_real=$(realpath -m -- "$theme_dir")
theme_needs_copy=true
[[ $repo_real == "$theme_real" ]] && theme_needs_copy=false

if $theme_needs_copy && [[ -e $theme_dir && ! -f $theme_dir/.neon-overdrive-managed ]]; then
  die "$theme_dir already exists and is not managed by this installer"
fi
if [[ -e $plugin_dir && ! -f $plugin_dir/.neon-overdrive-managed ]]; then
  die "$plugin_dir already exists and is not managed by this installer"
fi
if [[ -e $wallpaper_bin ]] && ! grep -Fq 'Managed by Neon Overdrive' "$wallpaper_bin"; then
  die "$wallpaper_bin already exists and is not managed by this installer"
fi
if [[ -e $wallpaper_file && ! -f $wallpaper_dir/.neon-overdrive-managed ]]; then
  die "$wallpaper_file already exists and is not managed by this installer"
fi

install -d -m 700 -- "$state_dir" "$state_dir/backups"
backup_dir="$state_dir/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
install -d -m 700 -- "$backup_dir"

backup_path() {
  local label=$1
  local path=$2
  [[ -e $path || -L $path ]] || return 0
  install -d -m 700 -- "$backup_dir/$(dirname -- "$label")"
  cp -a -- "$path" "$backup_dir/$label"
}

backup_path config/hypr/autostart.lua "$autostart_file"
backup_path config/omarchy/shell.json "$config_home/omarchy/shell.json"
backup_path config/omarchy/plugins/neon-overdrive.cava "$plugin_dir"
backup_path local/bin/neon-overdrive-wallpaper "$wallpaper_bin"
backup_path local/share/neon-overdrive "$wallpaper_dir"
$theme_needs_copy && backup_path config/omarchy/themes/neon-overdrive "$theme_dir"

if [[ ! -f $state_file ]]; then
  previous_theme=""
  [[ -r $state_home/omarchy/current/theme.name ]] && read -r previous_theme <"$state_home/omarchy/current/theme.name"
  background_was_enabled=$(omarchy plugin list --json | jq -r 'map(select(.id == "omarchy.background"))[0].enabled // false')
  {
    printf 'PREVIOUS_THEME=%q\n' "$previous_theme"
    printf 'BACKGROUND_WAS_ENABLED=%q\n' "$background_was_enabled"
    printf 'THEME_WAS_COPIED=%q\n' "$theme_needs_copy"
  } >"$state_file"
  chmod 600 "$state_file"
fi

theme_files=(
  colors.toml
  hyprland.lua
  icons.theme
  neon-city-source.png
  preview.png
  preview-unlock.png
  unlock.png
  shell.bar.toml
  shell.launcher.toml
  shell.lock.toml
  shell.menu.toml
  shell.notifications.toml
  shell.popups.toml
  shell.tooltip.toml
)

if $theme_needs_copy; then
  install -d -m 755 -- "$theme_dir/backgrounds"
  for file in "${theme_files[@]}"; do
    install -m 0644 -- "$repo_dir/$file" "$theme_dir/$file"
  done
  install -m 0644 -- "$repo_dir/backgrounds/neon-city-poster.jpg" "$theme_dir/backgrounds/neon-city-poster.jpg"
  printf 'Managed by Neon Overdrive install.sh\n' >"$theme_dir/.neon-overdrive-managed"
fi

install -d -m 755 -- "$plugin_dir" "$wallpaper_dir" "$(dirname -- "$wallpaper_bin")"
install -m 0644 -- "$repo_dir/extras/plugin/BarWidget.qml" "$plugin_dir/BarWidget.qml"
install -m 0644 -- "$repo_dir/extras/plugin/Service.qml" "$plugin_dir/Service.qml"
install -m 0644 -- "$repo_dir/extras/plugin/cava.conf" "$plugin_dir/cava.conf"
install -m 0644 -- "$repo_dir/extras/plugin/manifest.json" "$plugin_dir/manifest.json"
printf 'Managed by Neon Overdrive install.sh\n' >"$plugin_dir/.neon-overdrive-managed"

install -m 0644 -- "$repo_dir/assets/neon-city-loop.mp4" "$wallpaper_file"
printf 'Managed by Neon Overdrive install.sh\n' >"$wallpaper_dir/.neon-overdrive-managed"
install -m 0755 -- "$repo_dir/extras/wallpaper/neon-overdrive-wallpaper" "$wallpaper_bin"

install -d -m 755 -- "$(dirname -- "$autostart_file")"
if [[ ! -e $autostart_file ]]; then
  printf '%s\n' '-- Extra autostart processes.' >"$autostart_file"
fi

begin_count=$(grep -Fxc -- "$begin_marker" "$autostart_file" || true)
end_count=$(grep -Fxc -- "$end_marker" "$autostart_file" || true)
[[ $begin_count == "$end_count" && $begin_count -le 1 ]] || die "managed markers in $autostart_file are malformed"
if ((begin_count == 1)); then
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { begin_line = NR }
    $0 == end { end_line = NR }
    END { exit !(begin_line > 0 && end_line > begin_line) }
  ' "$autostart_file" || die "managed markers in $autostart_file are out of order"
fi

autostart_tmp=$(mktemp "$autostart_file.tmp.XXXXXX")
awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin { managed = 1; next }
  $0 == end { managed = 0; next }
  !managed { lines[++count] = $0 }
  END {
    while (count > 0 && lines[count] == "") count--
    for (i = 1; i <= count; i++) print lines[i]
  }
' "$autostart_file" >"$autostart_tmp"
cat >>"$autostart_tmp" <<'EOF'

-- BEGIN NEON OVERDRIVE MANAGED BLOCK
-- Live wallpaper; the Omarchy background service is disabled by install.sh.
o.launch_on_start([[bash -lc 'exec "$HOME/.local/bin/neon-overdrive-wallpaper"']])
-- END NEON OVERDRIVE MANAGED BLOCK
EOF
if ! luac -p "$autostart_tmp"; then
  rm -f -- "$autostart_tmp"
  die "generated autostart configuration is invalid; leaving $autostart_file unchanged"
fi
chmod --reference="$autostart_file" "$autostart_tmp"
mv -- "$autostart_tmp" "$autostart_file"

omarchy theme set "$theme_name"
omarchy-shell shell rescanPlugins >/dev/null
omarchy plugin enable "$plugin_id" --before omarchy.clock
omarchy plugin disable omarchy.background

if command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1; then
  config_errors=$(hyprctl configerrors)
  [[ -z $config_errors ]] || die "Hyprland rejected the updated config: $config_errors"
else
  warn "Hyprland is not reachable; the autostart block will apply next login"
fi

if $start_wallpaper; then
  "$wallpaper_bin" stop || true
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- "$wallpaper_bin" >/dev/null 2>&1 &
  else
    "$wallpaper_bin" >/dev/null 2>&1 &
  fi
fi

printf 'Neon Overdrive installed. Backup: %s\n' "$backup_dir"
