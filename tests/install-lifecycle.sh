#!/usr/bin/env bash

set -Eeuo pipefail
export NEON_OVERDRIVE_SKIP_LIFECYCLE_TEST=true

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture_dir="$repo_dir/tests/fixtures"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fake_home="$test_root/home"
fake_bin="$test_root/bin"
fake_xdg_config="$fake_home/custom-config"
fake_xdg_data="$fake_home/custom-data"
fake_xdg_state="$fake_home/custom-state"
fake_xdg_runtime="$test_root/runtime"

install -d -m 700 \
  "$fake_bin" \
  "$fake_home/.config/omarchy/plugins" \
  "$fake_home/.local/state/omarchy/current" \
  "$fake_xdg_config/hypr" \
  "$fake_xdg_runtime"
install -m 0755 "$fixture_dir/bin/omarchy" "$fake_bin/omarchy"
install -m 0755 "$fixture_dir/bin/omarchy-shell" "$fake_bin/omarchy-shell"
install -m 0755 "$fixture_dir/bin/hyprctl" "$fake_bin/hyprctl"
install -m 0755 "$fixture_dir/bin/cava" "$fake_bin/cava"
install -m 0755 "$fixture_dir/bin/mpvpaper" "$fake_bin/mpvpaper"
install -m 0644 "$fixture_dir/shell-fixture.json" "$fake_home/.config/omarchy/shell.json"
install -m 0644 "$fixture_dir/theme.name" "$fake_home/.local/state/omarchy/current/theme.name"
install -m 0644 "$fixture_dir/autostart.lua" "$fake_xdg_config/hypr/autostart.lua"
sed -i "s|__HOME__|$fake_home|g" "$fake_xdg_config/hypr/autostart.lua"
install -m 0644 "$fixture_dir/autostart-restored.lua" "$test_root/expected-autostart.lua"
sed -i "s|__HOME__|$fake_home|g" "$test_root/expected-autostart.lua"
legacy_line_number=$(awk -v video="$fake_home/.config/omarchy/wallpapers/neon-city-loop.mp4" '
  /^[[:space:]]*o[.]launch_on_start[[:space:]]*\(/ && index($0, video) { print NR; exit }
' "$fake_xdg_config/hypr/autostart.lua")
cp -a "$fixture_dir/legacy-plugin" "$fake_home/.config/omarchy/plugins/sloth.cava"

# Simulate an interruption after the exact legacy line was safely stashed but
# before the live autostart file or install state was updated.
install -d -m 700 "$fake_xdg_state/neon-overdrive"
sed -n "${legacy_line_number}p" "$fake_xdg_config/hypr/autostart.lua" \
  >"$fake_xdg_state/neon-overdrive/legacy-wallpaper-autostart.lua"
chmod 600 "$fake_xdg_state/neon-overdrive/legacy-wallpaper-autostart.lua"

test_env=(
  env
  "HOME=$fake_home"
  "XDG_CONFIG_HOME=$fake_xdg_config"
  "XDG_DATA_HOME=$fake_xdg_data"
  "XDG_STATE_HOME=$fake_xdg_state"
  "XDG_RUNTIME_DIR=$fake_xdg_runtime"
  "PATH=$fake_bin:/usr/bin:/bin"
)

install -m 0644 "$fake_xdg_config/hypr/autostart.lua" "$test_root/preflight-autostart.lua"
mv -- "$fake_home/.config/omarchy/plugins/sloth.cava" "$test_root/legacy-plugin-directory"
install -m 0644 "$fixture_dir/legacy-plugin/prototype.txt" \
  "$fake_home/.config/omarchy/plugins/sloth.cava"
if "${test_env[@]}" "$repo_dir/install.sh" --migrate-legacy --no-start >/dev/null 2>&1; then
  printf 'Non-directory legacy-plugin migration unexpectedly succeeded.\n' >&2
  exit 1
fi
[[ -f $fake_home/.config/omarchy/plugins/sloth.cava ]]
cmp -s "$test_root/preflight-autostart.lua" "$fake_xdg_config/hypr/autostart.lua"
mv -- "$fake_home/.config/omarchy/plugins/sloth.cava" "$test_root/rejected-legacy-plugin-file"
mv -- "$test_root/legacy-plugin-directory" "$fake_home/.config/omarchy/plugins/sloth.cava"

"${test_env[@]}" "$repo_dir/install.sh" --migrate-legacy --no-start >/dev/null

new_plugin="$fake_home/.config/omarchy/plugins/neon-overdrive.cava"
legacy_stash="$fake_xdg_state/neon-overdrive/legacy-sloth.cava"
legacy_autostart_stash="$fake_xdg_state/neon-overdrive/legacy-wallpaper-autostart.lua"
shell_file="$fake_home/.config/omarchy/shell.json"
legacy_video="$fake_home/.config/omarchy/wallpapers/neon-city-loop.mp4"

[[ -f $new_plugin/.neon-overdrive-managed ]]
[[ -f $new_plugin/Service.qml ]]
grep -Fq 'Socket {' "$new_plugin/Service.qml"
[[ ! -e $fake_home/.config/omarchy/plugins/sloth.cava ]]
[[ -f $legacy_stash/prototype.txt ]]
[[ -s $legacy_autostart_stash ]]
[[ -f $fake_xdg_config/hypr/autostart.lua ]]
! grep -Fq -- "$legacy_video" "$fake_xdg_config/hypr/autostart.lua"
managed_line_number=$(grep -nFx -- '-- BEGIN NEON OVERDRIVE MANAGED BLOCK' "$fake_xdg_config/hypr/autostart.lua" | cut -d: -f1)
[[ $managed_line_number == "$legacy_line_number" ]]
[[ $(grep -Fxc -- '-- BEGIN NEON OVERDRIVE MANAGED BLOCK' "$fake_xdg_config/hypr/autostart.lua") == 1 ]]
grep -Fq -- '-- o.launch_on_start([[mpvpaper ALL ' "$fake_xdg_config/hypr/autostart.lua"
grep -Fq -- '/wallpapers/unrelated-loop.mp4' "$fake_xdg_config/hypr/autostart.lua"
[[ -d $fake_home/.config/omarchy/themes/neon-overdrive ]]
[[ ! -d $fake_xdg_config/omarchy/themes/neon-overdrive ]]
jq -e '
  [.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?]
  | any(.id == "neon-overdrive.cava" and .prototypeSetting == 7)
' "$shell_file" >/dev/null
jq -e '
  [.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?]
  | all(.id != "sloth.cava")
' "$shell_file" >/dev/null

install -m 0644 "$fake_xdg_config/hypr/autostart.lua" "$test_root/installed-autostart.lua"
install -m 0600 "$legacy_autostart_stash" "$test_root/installed-legacy-stash.lua"
"${test_env[@]}" "$repo_dir/install.sh" --no-start >/dev/null
cmp -s "$test_root/installed-autostart.lua" "$fake_xdg_config/hypr/autostart.lua"
cmp -s "$test_root/installed-legacy-stash.lua" "$legacy_autostart_stash"

install -m 0644 "$shell_file" "$test_root/installed-shell.json"
shell_tmp=$(mktemp "$shell_file.tmp.XXXXXX")
jq '.bar.layout.left = "not-an-array"' "$shell_file" >"$shell_tmp"
chmod --reference="$shell_file" "$shell_tmp"
mv -- "$shell_tmp" "$shell_file"
if "${test_env[@]}" "$repo_dir/uninstall.sh" >/dev/null 2>&1; then
  printf 'Malformed-layout uninstall unexpectedly succeeded.\n' >&2
  exit 1
fi
[[ -f $new_plugin/.neon-overdrive-managed ]]
[[ -x $fake_home/.local/bin/neon-overdrive-wallpaper ]]
[[ -f $fake_xdg_data/neon-overdrive/.neon-overdrive-managed ]]
[[ -d $legacy_stash ]]
cmp -s "$test_root/installed-autostart.lua" "$fake_xdg_config/hypr/autostart.lua"
install -m 0644 "$test_root/installed-shell.json" "$shell_file"

sed -i \
  -e 's/^-- BEGIN NEON OVERDRIVE MANAGED BLOCK$/-- NEON OVERDRIVE MARKER SWAP/' \
  -e 's/^-- END NEON OVERDRIVE MANAGED BLOCK$/-- BEGIN NEON OVERDRIVE MANAGED BLOCK/' \
  -e 's/^-- NEON OVERDRIVE MARKER SWAP$/-- END NEON OVERDRIVE MANAGED BLOCK/' \
  "$fake_xdg_config/hypr/autostart.lua"
if "${test_env[@]}" "$repo_dir/uninstall.sh" >/dev/null 2>&1; then
  printf 'Malformed-marker uninstall unexpectedly succeeded.\n' >&2
  exit 1
fi
[[ -f $fake_xdg_state/neon-overdrive/install-state.env ]]
[[ -s $legacy_autostart_stash ]]
[[ -f $new_plugin/.neon-overdrive-managed ]]
[[ -x $fake_home/.local/bin/neon-overdrive-wallpaper ]]
[[ -f $fake_xdg_data/neon-overdrive/.neon-overdrive-managed ]]
[[ -d $legacy_stash ]]
[[ ! -e $fake_home/.config/omarchy/plugins/sloth.cava ]]
install -m 0644 "$test_root/installed-autostart.lua" "$fake_xdg_config/hypr/autostart.lua"

"${test_env[@]}" "$repo_dir/uninstall.sh" >/dev/null

[[ ! -e $new_plugin ]]
[[ -f $fake_home/.config/omarchy/plugins/sloth.cava/prototype.txt ]]
[[ ! -e $legacy_stash ]]
cmp -s "$test_root/installed-legacy-stash.lua" "$legacy_autostart_stash"
grep -Fq -- "$legacy_video" "$fake_xdg_config/hypr/autostart.lua"
cmp -s "$test_root/expected-autostart.lua" "$fake_xdg_config/hypr/autostart.lua"
jq -e '
  [.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?]
  | any(.id == "sloth.cava" and .prototypeSetting == 7)
' "$shell_file" >/dev/null
jq -e '
  [.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?]
  | all(.id != "neon-overdrive.cava")
' "$shell_file" >/dev/null
! grep -Fq -- '-- BEGIN NEON OVERDRIVE MANAGED BLOCK' "$fake_xdg_config/hypr/autostart.lua"
[[ ! -e $fake_home/.config/omarchy/themes/neon-overdrive ]]

printf 'Neon Overdrive install lifecycle test passed.\n'
