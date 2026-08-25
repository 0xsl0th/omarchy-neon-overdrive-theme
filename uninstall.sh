#!/usr/bin/env bash

set -Eeuo pipefail

theme_name="neon-overdrive"
plugin_id="neon-overdrive.cava"
legacy_plugin_id="sloth.cava"
begin_marker="-- BEGIN NEON OVERDRIVE MANAGED BLOCK"
end_marker="-- END NEON OVERDRIVE MANAGED BLOCK"

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
state_dir="$state_home/neon-overdrive"
state_file="$state_dir/install-state.env"
legacy_stash_dir="$state_dir/legacy-sloth.cava"
legacy_autostart_stash="$state_dir/legacy-wallpaper-autostart.lua"

die() {
  printf 'Neon Overdrive uninstaller: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Neon Overdrive uninstaller: warning: %s\n' "$*" >&2
}

valid_legacy_autostart_stash() {
  [[ -f $legacy_autostart_stash && ! -L $legacy_autostart_stash ]] || return 1
  [[ $(stat -c %a -- "$legacy_autostart_stash") == 600 ]] || return 1
  [[ $(awk 'END { print NR }' "$legacy_autostart_stash") == 1 ]]
}

preflight_recovery() {
  local preflight_begin_count=0
  local preflight_end_count=0
  local legacy_already_present=false
  local preflight_tmp=""

  if [[ $LEGACY_PLUGIN_STASHED == true ]]; then
    if [[ -L $legacy_plugin_dir ]]; then
      die "legacy plugin recovery path is an unexpected symlink: $legacy_plugin_dir"
    elif [[ -e $legacy_plugin_dir ]]; then
      if [[ -e $legacy_stash_dir || -L $legacy_stash_dir ]] || ! \
        jq -e --arg id "$legacy_plugin_id" '.id == $id' \
          "$legacy_plugin_dir/manifest.json" >/dev/null 2>&1; then
        die "legacy plugin recovery path conflicts with its stash: $legacy_plugin_dir"
      fi
    elif [[ ! -d $legacy_stash_dir || -L $legacy_stash_dir ]]; then
      die "legacy plugin recovery stash is missing: $legacy_stash_dir"
    fi
  fi

  if [[ $LEGACY_LAYOUT_MIGRATED == true ]]; then
    [[ -r $shell_config_file ]] || \
      die "legacy bar position cannot be restored because $shell_config_file is missing"
    jq -e '
      def valid_section:
        . == null or (
          type == "array" and
          all(.[]; type == "object" and (.id | type == "string"))
        );
      (.bar.layout | type == "object") and
      (.bar.layout.left | valid_section) and
      (.bar.layout.center | valid_section) and
      (.bar.layout.right | valid_section)
    ' "$shell_config_file" >/dev/null || \
      die "legacy bar position cannot be restored because $shell_config_file is invalid"
  fi

  if [[ ! -f $autostart_file ]]; then
    [[ $LEGACY_WALLPAPER_AUTOSTART_MIGRATED != true ]] || \
      die "legacy wallpaper launcher cannot be restored because $autostart_file is missing"
    return 0
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

  if [[ $LEGACY_WALLPAPER_AUTOSTART_MIGRATED == true ]]; then
    valid_legacy_autostart_stash || \
      die "legacy wallpaper launcher recovery stash is missing or invalid: $legacy_autostart_stash"
    grep -Fqxf "$legacy_autostart_stash" "$autostart_file" && legacy_already_present=true
    if ((preflight_begin_count == 0)) && ! $legacy_already_present; then
      die "legacy wallpaper launcher cannot be restored because the managed block is missing"
    fi
  fi

  if ((preflight_begin_count == 1)); then
    preflight_tmp=$(mktemp "${TMPDIR:-/tmp}/neon-overdrive-autostart.XXXXXX")
    awk -v begin="$begin_marker" -v end="$end_marker" \
      -v restore="$LEGACY_WALLPAPER_AUTOSTART_MIGRATED" \
      -v already_present="$legacy_already_present" \
      -v stash="$legacy_autostart_stash" '
      $0 == begin {
        if (restore == "true" && already_present != "true") {
          while ((getline restored_line < stash) > 0)
            print restored_line
          close(stash)
        }
        managed = 1
        next
      }
      $0 == end { managed = 0; next }
      !managed { print }
    ' "$autostart_file" >"$preflight_tmp"
    if ! luac -p "$preflight_tmp"; then
      rm -f -- "$preflight_tmp"
      die "restored autostart configuration would be invalid; no files were changed"
    fi
    rm -f -- "$preflight_tmp"
  fi
}

((EUID != 0)) || die "run this as your desktop user, not root"
command -v omarchy >/dev/null 2>&1 || die "Omarchy is required"
command -v jq >/dev/null 2>&1 || die "jq is required by Omarchy"
command -v luac >/dev/null 2>&1 || die "luac is required for safe Hyprland updates"
plugin_json=$(omarchy plugin list --json 2>/dev/null) || \
  die "start an Omarchy desktop session, then rerun the uninstaller"

PREVIOUS_THEME=""
BACKGROUND_WAS_ENABLED=""
THEME_WAS_COPIED="false"
LEGACY_PLUGIN_STASHED="false"
LEGACY_LAYOUT_MIGRATED="false"
LEGACY_WALLPAPER_AUTOSTART_MIGRATED="false"
if [[ -r $state_file ]]; then
  # This file is generated by install.sh, owned by the current user, and mode 0600.
  # shellcheck disable=SC1090
  source "$state_file"
else
  warn "install state is missing; prior theme/background choices will be left alone"
fi

preflight_recovery

install -d -m 700 -- "$state_dir" "$state_dir/backups"
backup_dir="$state_dir/backups/uninstall-$(date -u +%Y%m%dT%H%M%SZ)-$$"
install -d -m 700 -- "$backup_dir"

backup_path() {
  local label=$1
  local path=$2
  [[ -e $path || -L $path ]] || return 0
  install -d -m 700 -- "$backup_dir/$(dirname -- "$label")"
  cp -a -- "$path" "$backup_dir/$label"
}

stash_managed() {
  local label=$1
  local path=$2
  local marker=$3
  [[ -e $path || -L $path ]] || return 0
  [[ -f $marker ]] || {
    warn "leaving unmanaged path in place: $path"
    return 0
  }
  install -d -m 700 -- "$backup_dir/removed/$(dirname -- "$label")"
  mv -- "$path" "$backup_dir/removed/$label"
}

backup_path config/hypr/autostart.lua "$autostart_file"
backup_path config/omarchy/shell.json "$shell_config_file"

if [[ -x $wallpaper_bin ]] && grep -Fq 'Managed by Neon Overdrive' "$wallpaper_bin"; then
  "$wallpaper_bin" stop || die "the managed wallpaper did not stop"
fi

plugin_is_managed=false
[[ -f $plugin_dir/.neon-overdrive-managed ]] && plugin_is_managed=true
legacy_plugin_restored=false
legacy_layout_restored=false

if [[ $LEGACY_PLUGIN_STASHED == true ]]; then
  if [[ -e $legacy_plugin_dir || -L $legacy_plugin_dir ]]; then
    if [[ ! -e $legacy_stash_dir ]] && jq -e --arg id "$legacy_plugin_id" \
      '.id == $id' "$legacy_plugin_dir/manifest.json" >/dev/null 2>&1; then
      legacy_plugin_restored=true
    else
      warn "cannot restore the legacy plugin over an existing path: $legacy_plugin_dir"
    fi
  elif [[ -d $legacy_stash_dir ]]; then
    mv -- "$legacy_stash_dir" "$legacy_plugin_dir"
    legacy_plugin_restored=true
  else
    warn "legacy plugin recovery stash is missing: $legacy_stash_dir"
  fi
fi

if [[ $LEGACY_LAYOUT_MIGRATED == true ]]; then
  if [[ -r $shell_config_file ]]; then
    if jq -e --arg old "$legacy_plugin_id" --arg new "$plugin_id" '
      [.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?] as $layout
      | any($layout[]; .id == $old) and all($layout[]; .id != $new)
    ' "$shell_config_file" >/dev/null; then
      legacy_layout_restored=true
    else
      shell_tmp=$(mktemp "$shell_config_file.tmp.XXXXXX")
      jq --arg old "$plugin_id" --arg new "$legacy_plugin_id" '
        def restore($old; $new):
          if any(.[]; .id == $new) then
            map(select(.id != $old))
          else
            map(if .id == $old then .id = $new else . end)
          end;
        .bar.layout.left = ((.bar.layout.left // []) | restore($old; $new))
        | .bar.layout.center = ((.bar.layout.center // []) | restore($old; $new))
        | .bar.layout.right = ((.bar.layout.right // []) | restore($old; $new))
      ' "$shell_config_file" >"$shell_tmp"
      chmod --reference="$shell_config_file" "$shell_tmp"
      mv -- "$shell_tmp" "$shell_config_file"
      legacy_layout_restored=true
    fi
  else
    warn "cannot restore the legacy bar position because $shell_config_file is missing"
  fi
fi

if $plugin_is_managed && ! $legacy_layout_restored && \
  jq -e --arg id "$plugin_id" 'any(.[]; .id == $id and .enabled == true)' <<<"$plugin_json" >/dev/null; then
  omarchy plugin disable "$plugin_id"
fi

if [[ $BACKGROUND_WAS_ENABLED == true ]]; then
  omarchy plugin enable omarchy.background
fi

if $plugin_is_managed; then
  install -d -m 700 -- "$backup_dir/removed/config/omarchy/plugins"
  mv -- "$plugin_dir" "$backup_dir/removed/config/omarchy/plugins/neon-overdrive.cava"
  omarchy-shell shell rescanPlugins >/dev/null
fi

legacy_autostart_restore=false
if [[ $LEGACY_WALLPAPER_AUTOSTART_MIGRATED == true ]]; then
  if valid_legacy_autostart_stash; then
    legacy_autostart_restore=true
  else
    warn "legacy wallpaper launcher recovery stash is missing or invalid: $legacy_autostart_stash"
  fi
fi

legacy_autostart_restored=false
if [[ -f $autostart_file ]]; then
  begin_count=$(grep -Fxc -- "$begin_marker" "$autostart_file" || true)
  end_count=$(grep -Fxc -- "$end_marker" "$autostart_file" || true)
  if [[ $begin_count == "$end_count" && $begin_count -le 1 ]]; then
    markers_ordered=true
    if ((begin_count == 1)); then
      if ! awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { begin_line = NR }
        $0 == end { end_line = NR }
        END { exit !(begin_line > 0 && end_line > begin_line) }
      ' "$autostart_file"; then
        markers_ordered=false
        warn "managed markers in $autostart_file are out of order; leaving the file unchanged"
      fi
    fi
    if $markers_ordered && ((begin_count == 1)); then
      legacy_autostart_already_present=false
      if $legacy_autostart_restore && grep -Fqxf "$legacy_autostart_stash" "$autostart_file"; then
        legacy_autostart_already_present=true
      fi
      autostart_tmp=$(mktemp "$autostart_file.tmp.XXXXXX")
      awk -v begin="$begin_marker" -v end="$end_marker" \
        -v restore="$legacy_autostart_restore" \
        -v already_present="$legacy_autostart_already_present" \
        -v stash="$legacy_autostart_stash" '
        $0 == begin {
          if (restore == "true" && already_present != "true") {
            while ((getline restored_line < stash) > 0)
              lines[++count] = restored_line
            close(stash)
          }
          managed = 1
          next
        }
        $0 == end { managed = 0; next }
        !managed { lines[++count] = $0 }
        END {
          while (count > 0 && lines[count] == "") count--
          for (i = 1; i <= count; i++) print lines[i]
        }
      ' "$autostart_file" >"$autostart_tmp"
      if luac -p "$autostart_tmp"; then
        chmod --reference="$autostart_file" "$autostart_tmp"
        mv -- "$autostart_tmp" "$autostart_file"
        if $legacy_autostart_restore; then
          legacy_autostart_restored=true
        fi
      else
        rm -f -- "$autostart_tmp"
        warn "updated autostart configuration would be invalid; leaving $autostart_file unchanged"
      fi
    elif $markers_ordered && $legacy_autostart_restore; then
      if grep -Fqxf "$legacy_autostart_stash" "$autostart_file"; then
        legacy_autostart_restored=true
      else
        warn "cannot restore the legacy wallpaper launcher because the managed block is missing"
      fi
    fi
  else
    warn "managed markers in $autostart_file are malformed; leaving the file unchanged"
  fi
elif $legacy_autostart_restore; then
  warn "cannot restore the legacy wallpaper launcher because $autostart_file is missing"
fi

if [[ -e $wallpaper_bin ]] && grep -Fq 'Managed by Neon Overdrive' "$wallpaper_bin"; then
  install -d -m 700 -- "$backup_dir/removed/local/bin"
  mv -- "$wallpaper_bin" "$backup_dir/removed/local/bin/neon-overdrive-wallpaper"
fi
stash_managed local/share/neon-overdrive "$wallpaper_dir" "$wallpaper_dir/.neon-overdrive-managed"

current_theme=""
[[ -r $omarchy_current_dir/theme.name ]] && read -r current_theme <"$omarchy_current_dir/theme.name"
if [[ $current_theme == "$theme_name" && -n $PREVIOUS_THEME && $PREVIOUS_THEME != "$theme_name" ]]; then
  if [[ -d $omarchy_config_dir/themes/$PREVIOUS_THEME || -d /usr/share/omarchy/themes/$PREVIOUS_THEME ]]; then
    omarchy theme set "$PREVIOUS_THEME"
    current_theme="$PREVIOUS_THEME"
  else
    warn "previous theme '$PREVIOUS_THEME' is unavailable; keeping Neon Overdrive active"
  fi
fi

if [[ $THEME_WAS_COPIED == true && -f $theme_dir/.neon-overdrive-managed ]]; then
  if [[ $current_theme == "$theme_name" ]]; then
    warn "keeping the copied theme because it is still active"
  else
    install -d -m 700 -- "$backup_dir/removed/config/omarchy/themes"
    mv -- "$theme_dir" "$backup_dir/removed/config/omarchy/themes/neon-overdrive"
  fi
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1; then
  config_errors=$(hyprctl configerrors)
  [[ -z $config_errors ]] || die "Hyprland rejected the updated config: $config_errors"
fi

recovery_complete=true
[[ $LEGACY_PLUGIN_STASHED != true || $legacy_plugin_restored == true ]] || recovery_complete=false
[[ $LEGACY_LAYOUT_MIGRATED != true || $legacy_layout_restored == true ]] || recovery_complete=false
[[ $LEGACY_WALLPAPER_AUTOSTART_MIGRATED != true || $legacy_autostart_restored == true ]] || recovery_complete=false
if [[ -f $state_file ]]; then
  if $recovery_complete; then
    mv -- "$state_file" "$backup_dir/install-state.env"
  else
    warn "legacy recovery is incomplete; keeping install state for a safe retry: $state_file"
    omarchy plugin enable omarchy.background >/dev/null 2>&1 || \
      warn "could not enable the stock background after incomplete recovery"
    die "legacy recovery is incomplete; resolve the warnings and retry"
  fi
fi

printf 'Neon Overdrive extras removed. Recovery backup: %s\n' "$backup_dir"
