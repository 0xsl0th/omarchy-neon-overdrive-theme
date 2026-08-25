#!/usr/bin/env bash

set -Eeuo pipefail

theme_name="neon-overdrive"
plugin_id="neon-overdrive.cava"
legacy_plugin_id="sloth.cava"
begin_marker="-- BEGIN NEON OVERDRIVE MANAGED BLOCK"
end_marker="-- END NEON OVERDRIVE MANAGED BLOCK"

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
hypr_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
omarchy_config_dir="$HOME/.config/omarchy"
omarchy_current_dir="$HOME/.local/state/omarchy/current"
theme_dir="$omarchy_config_dir/themes/$theme_name"
plugin_dir="$omarchy_config_dir/plugins/$plugin_id"
legacy_plugin_dir="$omarchy_config_dir/plugins/$legacy_plugin_id"
shell_config_file="$omarchy_config_dir/shell.json"
autostart_file="$hypr_config_home/hypr/autostart.lua"
wallpaper_bin="$HOME/.local/bin/neon-overdrive-wallpaper"
wallpaper_dir="$data_home/neon-overdrive"
wallpaper_file="$wallpaper_dir/neon-city-loop.mp4"
state_dir="$state_home/neon-overdrive"
state_file="$state_dir/install-state.env"
legacy_stash_dir="$state_dir/legacy-sloth.cava"
legacy_wallpaper_file="$omarchy_config_dir/wallpapers/neon-city-loop.mp4"
legacy_autostart_stash="$state_dir/legacy-wallpaper-autostart.lua"
wallpaper_start_log="$state_dir/wallpaper-start.log"

install_deps=false
check_only=false
start_wallpaper=true
migrate_legacy=false
legacy_plugin_stashed=false
legacy_layout_migrated=false
legacy_wallpaper_autostart_migrated=false
background_was_enabled=false
migrate_legacy_plugin_now=false
migrate_legacy_layout_now=false
migrate_legacy_wallpaper_now=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [--check] [--install-deps] [--migrate-legacy] [--no-start]

  --check         Validate the project, runtime, shell, and migration readiness.
  --install-deps  Install missing Cava/mpvpaper packages through the Omarchy CLI.
  --migrate-legacy
                  Back up and replace the early plugin and wallpaper launchers.
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

valid_legacy_autostart_stash() {
  [[ -f $legacy_autostart_stash && ! -L $legacy_autostart_stash ]] || return 1
  [[ $(stat -c %a -- "$legacy_autostart_stash") == 600 ]] || return 1
  [[ $(awk 'END { print NR }' "$legacy_autostart_stash") == 1 ]]
}

legacy_wallpaper_line_is_safe() {
  local line=$1
  local trimmed=""
  local payload=""
  local prefix=""
  local suffix=""

  trimmed=${line#"${line%%[![:space:]]*}"}
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}

  if [[ $trimmed == 'o.launch_on_start("'*'")' ]]; then
    prefix='o.launch_on_start("'
    suffix='")'
  elif [[ $trimmed == 'o.launch_on_start([['*']])' ]]; then
    prefix='o.launch_on_start([['
    suffix=']])'
  else
    return 1
  fi

  payload=${trimmed#"$prefix"}
  payload=${payload%"$suffix"}
  case "$payload" in
    'mpvpaper '* | '/usr/bin/mpvpaper '*) ;;
    *) return 1 ;;
  esac
  case "$payload" in
    *'&'* | *'|'* | *';'* | *'`'* | *'$('* | *'>'* | *'<'*) return 1 ;;
  esac
  [[ $payload == *" $legacy_wallpaper_file" ]]
}

legacy_wallpaper_process_is_ours() {
  local pid=${1:-}
  local process_name=""

  [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/comm && -r /proc/$pid/cmdline ]] || return 1
  read -r process_name <"/proc/$pid/comm" || return 1
  [[ $process_name == mpvpaper ]] || return 1
  grep -Fzqx -- "$legacy_wallpaper_file" "/proc/$pid/cmdline"
}

wait_for_wallpaper() {
  local timeout_seconds=$1
  local deadline=$((SECONDS + timeout_seconds))
  local stable_checks=0

  while ((SECONDS < deadline)); do
    if "$wallpaper_bin" status; then
      stable_checks=$((stable_checks + 1))
      ((stable_checks >= 5)) && return 0
    else
      stable_checks=0
    fi
    sleep 0.15
  done
  return 1
}

while (($#)); do
  case "$1" in
    --check) check_only=true ;;
    --install-deps) install_deps=true ;;
    --migrate-legacy) migrate_legacy=true ;;
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
command -v luac >/dev/null 2>&1 || die "luac is required for safe Hyprland updates"
command -v setpriv >/dev/null 2>&1 || die "setpriv is required to supervise Cava"
command -v flock >/dev/null 2>&1 || die "flock is required to serialize wallpaper startup"
"$repo_dir/validate.sh"

legacy_plugin_present=false
legacy_layout_present=false
legacy_wallpaper_autostart_present=false
legacy_wallpaper_autostart_line=""
if [[ -L $legacy_plugin_dir ]]; then
  die "legacy plugin path is an unsupported symlink: $legacy_plugin_dir"
elif [[ -e $legacy_plugin_dir && ! -d $legacy_plugin_dir ]]; then
  die "legacy plugin path is not a directory: $legacy_plugin_dir"
elif [[ -d $legacy_plugin_dir ]]; then
  legacy_plugin_present=true
fi
if [[ -r $shell_config_file ]]; then
  jq -e --arg id "$legacy_plugin_id" '
    [.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?]
    | any(.id == $id)
  ' "$shell_config_file" >/dev/null && legacy_layout_present=true
fi
if [[ -r $autostart_file ]]; then
  legacy_wallpaper_autostart_count=0
  while IFS= read -r autostart_line || [[ -n $autostart_line ]]; do
    trimmed_line=${autostart_line#"${autostart_line%%[![:space:]]*}"}
    if [[ $trimmed_line == o.launch_on_start* &&
          $trimmed_line == *mpvpaper* &&
          $trimmed_line == *"$legacy_wallpaper_file"* ]]; then
      legacy_wallpaper_line_is_safe "$autostart_line" || \
        die "the legacy wallpaper launcher is not a known safe form; migrate it manually"
      legacy_wallpaper_autostart_count=$((legacy_wallpaper_autostart_count + 1))
      legacy_wallpaper_autostart_line=$autostart_line
    fi
  done <"$autostart_file"
  ((legacy_wallpaper_autostart_count <= 1)) || \
    die "multiple legacy wallpaper launchers in $autostart_file are ambiguous; remove duplicates manually"
  if ((legacy_wallpaper_autostart_count == 1)); then
    legacy_wallpaper_autostart_present=true
  fi

  luac -p "$autostart_file" || die "current autostart configuration is invalid: $autostart_file"
  preflight_begin_count=$(grep -Fxc -- "$begin_marker" "$autostart_file" || true)
  preflight_end_count=$(grep -Fxc -- "$end_marker" "$autostart_file" || true)
  [[ $preflight_begin_count == "$preflight_end_count" && $preflight_begin_count -le 1 ]] || \
    die "managed markers in $autostart_file are malformed"
  if ((preflight_begin_count == 1)); then
    awk -v begin="$begin_marker" -v end="$end_marker" '
      $0 == begin { begin_line = NR }
      $0 == end { end_line = NR }
      END { exit !(begin_line > 0 && end_line > begin_line) }
    ' "$autostart_file" || die "managed markers in $autostart_file are out of order"
  fi
fi

if $legacy_plugin_present || $legacy_layout_present || $legacy_wallpaper_autostart_present; then
  if ! $migrate_legacy && [[ -t 0 ]] && ! $check_only; then
    read -r -p 'Migrate the legacy Neon Overdrive plugin and wallpaper launcher? [y/N] ' answer
    [[ $answer =~ ^[Yy]$ ]] && migrate_legacy=true
  fi
  if ! $migrate_legacy; then
    warn "legacy Neon Overdrive installation detected"
    $check_only && exit 1
    die "rerun with --migrate-legacy to back it up and preserve its settings"
  fi
fi
$migrate_legacy && $legacy_plugin_present && migrate_legacy_plugin_now=true
$migrate_legacy && $legacy_layout_present && migrate_legacy_layout_now=true
$migrate_legacy && $legacy_wallpaper_autostart_present && migrate_legacy_wallpaper_now=true
$migrate_legacy_plugin_now && [[ -e $legacy_stash_dir || -L $legacy_stash_dir ]] && \
  die "legacy plugin recovery stash already exists: $legacy_stash_dir"
legacy_autostart_stash_reused=false
if $migrate_legacy_wallpaper_now && [[ -e $legacy_autostart_stash || -L $legacy_autostart_stash ]]; then
  stashed_legacy_line=""
  if valid_legacy_autostart_stash; then
    IFS= read -r stashed_legacy_line <"$legacy_autostart_stash" || true
  fi
  if [[ $stashed_legacy_line == "$legacy_wallpaper_autostart_line" ]]; then
    legacy_autostart_stash_reused=true
  else
    die "legacy wallpaper recovery stash conflicts with $autostart_file: $legacy_autostart_stash"
  fi
fi
legacy_plugin_stashed=$migrate_legacy_plugin_now
legacy_layout_migrated=$migrate_legacy_layout_now
legacy_wallpaper_autostart_migrated=$migrate_legacy_wallpaper_now

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

plugin_json=""
if ! plugin_json=$(omarchy plugin list --json 2>/dev/null); then
  warn "the Omarchy shell is not reachable"
  $check_only && exit 1
  die "start an Omarchy desktop session, then rerun the installer"
fi

if $check_only; then
  ((${#missing[@]} == 0)) || exit 1
  printf 'Neon Overdrive preflight passed.\n'
  exit 0
fi

command -v cava >/dev/null 2>&1 || die "cava is still unavailable"
command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper is still unavailable"

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

repo_real=$(realpath -m -- "$repo_dir")
theme_real=$(realpath -m -- "$theme_dir")
theme_needs_copy=true
[[ $repo_real == "$theme_real" ]] && theme_needs_copy=false

if $theme_needs_copy && [[ -e $theme_dir && ! -f $theme_dir/.neon-overdrive-managed ]]; then
  theme_matches=true
  for file in "${theme_files[@]}"; do
    cmp -s -- "$repo_dir/$file" "$theme_dir/$file" || theme_matches=false
  done
  cmp -s -- "$repo_dir/backgrounds/neon-city-poster.jpg" "$theme_dir/backgrounds/neon-city-poster.jpg" || theme_matches=false
  if $theme_matches; then
    theme_needs_copy=false
  else
    die "$theme_dir already exists, differs from this checkout, and is not managed by this installer"
  fi
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
backup_path config/omarchy/shell.json "$shell_config_file"
backup_path config/omarchy/plugins/neon-overdrive.cava "$plugin_dir"
backup_path config/omarchy/plugins/sloth.cava "$legacy_plugin_dir"
backup_path local/bin/neon-overdrive-wallpaper "$wallpaper_bin"
backup_path local/share/neon-overdrive "$wallpaper_dir"
$theme_needs_copy && backup_path config/omarchy/themes/neon-overdrive "$theme_dir"

if [[ -f $state_file ]]; then
  grep -Fxq 'LEGACY_PLUGIN_STASHED=true' "$state_file" && legacy_plugin_stashed=true
  grep -Fxq 'LEGACY_LAYOUT_MIGRATED=true' "$state_file" && legacy_layout_migrated=true
  grep -Fxq 'LEGACY_WALLPAPER_AUTOSTART_MIGRATED=true' "$state_file" && \
    legacy_wallpaper_autostart_migrated=true
  recorded_background=$(awk -F= '
    $1 == "BACKGROUND_WAS_ENABLED" { value = $2 }
    END { print value }
  ' "$state_file")
  if [[ $recorded_background == true || $recorded_background == false ]]; then
    background_was_enabled=$recorded_background
  fi
fi

if $migrate_legacy_wallpaper_now && ! $legacy_autostart_stash_reused; then
  legacy_autostart_tmp=$(mktemp "$state_dir/legacy-wallpaper-autostart.lua.tmp.XXXXXX")
  printf '%s\n' "$legacy_wallpaper_autostart_line" >"$legacy_autostart_tmp"
  chmod 600 "$legacy_autostart_tmp"
  mv -- "$legacy_autostart_tmp" "$legacy_autostart_stash"
fi

if [[ ! -f $state_file ]]; then
  previous_theme=""
  [[ -r $omarchy_current_dir/theme.name ]] && read -r previous_theme <"$omarchy_current_dir/theme.name"
  background_was_enabled=$(jq -r 'map(select(.id == "omarchy.background"))[0].enabled // false' <<<"$plugin_json")
  {
    printf 'PREVIOUS_THEME=%q\n' "$previous_theme"
    printf 'BACKGROUND_WAS_ENABLED=%q\n' "$background_was_enabled"
    printf 'THEME_WAS_COPIED=%q\n' "$theme_needs_copy"
    printf 'LEGACY_PLUGIN_STASHED=%q\n' "$legacy_plugin_stashed"
    printf 'LEGACY_LAYOUT_MIGRATED=%q\n' "$legacy_layout_migrated"
    printf 'LEGACY_WALLPAPER_AUTOSTART_MIGRATED=%q\n' "$legacy_wallpaper_autostart_migrated"
  } >"$state_file"
  chmod 600 "$state_file"
fi

state_tmp=$(mktemp "$state_file.tmp.XXXXXX")
awk '
  !/^LEGACY_PLUGIN_STASHED=/ &&
  !/^LEGACY_LAYOUT_MIGRATED=/ &&
  !/^LEGACY_WALLPAPER_AUTOSTART_MIGRATED=/
' "$state_file" >"$state_tmp"
{
  printf 'LEGACY_PLUGIN_STASHED=%q\n' "$legacy_plugin_stashed"
  printf 'LEGACY_LAYOUT_MIGRATED=%q\n' "$legacy_layout_migrated"
  printf 'LEGACY_WALLPAPER_AUTOSTART_MIGRATED=%q\n' "$legacy_wallpaper_autostart_migrated"
} >>"$state_tmp"
chmod 600 "$state_tmp"
mv -- "$state_tmp" "$state_file"

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

if $migrate_legacy_plugin_now; then
  mv -- "$legacy_plugin_dir" "$legacy_stash_dir"
fi

if $migrate_legacy_layout_now; then
  shell_tmp=$(mktemp "$shell_config_file.tmp.XXXXXX")
  jq --arg old "$legacy_plugin_id" --arg new "$plugin_id" '
    def migrate($old; $new):
      if any(.[]; .id == $new) then
        map(select(.id != $old))
      else
        map(if .id == $old then .id = $new else . end)
      end;
    .bar.layout.left = ((.bar.layout.left // []) | migrate($old; $new))
    | .bar.layout.center = ((.bar.layout.center // []) | migrate($old; $new))
    | .bar.layout.right = ((.bar.layout.right // []) | migrate($old; $new))
  ' "$shell_config_file" >"$shell_tmp"
  chmod --reference="$shell_config_file" "$shell_tmp"
  mv -- "$shell_tmp" "$shell_config_file"
fi

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
awk -v begin="$begin_marker" -v end="$end_marker" \
  -v replace_legacy="$migrate_legacy_wallpaper_now" -v legacy_stash="$legacy_autostart_stash" '
  function add_managed_block(quote) {
    lines[++count] = begin
    lines[++count] = "-- Live wallpaper; the stock background is disabled after this launcher is ready."
    quote = sprintf("%c", 39)
    lines[++count] = "o.launch_on_start([[bash -lc " quote "exec \"$HOME/.local/bin/neon-overdrive-wallpaper\"" quote "]])"
    lines[++count] = end
  }
  BEGIN {
    if (replace_legacy == "true") {
      getline legacy_line < legacy_stash
      close(legacy_stash)
    }
  }
  $0 == begin {
    if (replace_legacy != "true" && !inserted) {
      add_managed_block()
      inserted = 1
    }
    managed = 1
    next
  }
  $0 == end { managed = 0; next }
  managed { next }
  replace_legacy == "true" && $0 == legacy_line {
    add_managed_block()
    inserted = 1
    next
  }
  { lines[++count] = $0 }
  END {
    while (count > 0 && lines[count] == "") count--
    for (i = 1; i <= count; i++) print lines[i]
    if (!inserted) {
      print ""
      add_managed_block()
      for (i = count - 3; i <= count; i++) print lines[i]
    }
  }
' "$autostart_file" >"$autostart_tmp"
if ! luac -p "$autostart_tmp"; then
  rm -f -- "$autostart_tmp"
  die "generated autostart configuration is invalid; leaving $autostart_file unchanged"
fi
chmod --reference="$autostart_file" "$autostart_tmp"
mv -- "$autostart_tmp" "$autostart_file"

omarchy theme set "$theme_name"
omarchy-shell shell rescanPlugins >/dev/null

plugin_discovered=false
for _ in {1..30}; do
  if plugin_json=$(omarchy plugin list --json 2>/dev/null) && \
    jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugin_json" >/dev/null; then
    plugin_discovered=true
    break
  fi
  sleep 0.1
done
$plugin_discovered || die "the Omarchy shell did not discover $plugin_id after rescan"

clock_in_layout=false
if [[ -r $shell_config_file ]]; then
  jq -e '
    [.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?]
    | any(.id == "omarchy.clock")
  ' "$shell_config_file" >/dev/null && clock_in_layout=true
fi
if $clock_in_layout; then
  omarchy plugin enable "$plugin_id" --before omarchy.clock
else
  omarchy plugin enable "$plugin_id"
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1; then
  config_errors=$(hyprctl configerrors)
  [[ -z $config_errors ]] || die "Hyprland rejected the updated config: $config_errors"
else
  warn "Hyprland is not reachable; the autostart block will apply next login"
fi

if $start_wallpaper; then
  "$wallpaper_bin" stop || die "the existing managed wallpaper did not stop"
  if $legacy_wallpaper_autostart_migrated; then
    valid_legacy_autostart_stash || \
      die "cannot safely retire the legacy wallpaper process without its valid recovery stash"
    for process_dir in /proc/[0-9]*; do
      legacy_pid=${process_dir##*/}
      legacy_wallpaper_process_is_ours "$legacy_pid" || continue
      if ! kill "$legacy_pid" 2>/dev/null; then
        legacy_wallpaper_process_is_ours "$legacy_pid" && \
          die "could not stop legacy wallpaper process $legacy_pid"
        continue
      fi
      for _ in {1..80}; do
        legacy_wallpaper_process_is_ours "$legacy_pid" || break
        sleep 0.05
      done
      legacy_wallpaper_process_is_ours "$legacy_pid" && \
        die "legacy wallpaper process $legacy_pid did not stop"
    done
  fi

  [[ -n ${XDG_RUNTIME_DIR:-} ]] || die "XDG_RUNTIME_DIR is unavailable"
  : >"$wallpaper_start_log"
  chmod 600 "$wallpaper_start_log"
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- "$wallpaper_bin" >"$wallpaper_start_log" 2>&1 &
    launched_with_uwsm=true
  else
    "$wallpaper_bin" >"$wallpaper_start_log" 2>&1 &
    launched_with_uwsm=false
  fi

  if ! wait_for_wallpaper 12 && $launched_with_uwsm; then
    "$wallpaper_bin" stop || true
    printf '%s\n' 'uwsm-app did not produce a ready wallpaper; retrying in a detached session.' >>"$wallpaper_start_log"
    if command -v setsid >/dev/null 2>&1; then
      if ! setsid -f "$wallpaper_bin" >>"$wallpaper_start_log" 2>&1; then
        warn "could not submit the detached wallpaper fallback"
      fi
    else
      "$wallpaper_bin" >>"$wallpaper_start_log" 2>&1 &
    fi
  fi

  if ! wait_for_wallpaper 10; then
    "$wallpaper_bin" stop || true
    omarchy plugin enable omarchy.background >/dev/null 2>&1 || \
      warn "could not enable the stock background after wallpaper startup failed"
    tail -n 20 "$wallpaper_start_log" >&2 || true
    die "the live wallpaper failed its readiness check"
  fi
fi

printf 'Neon Overdrive installed. Backup: %s\n' "$backup_dir"
