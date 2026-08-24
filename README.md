# Neon Overdrive for Omarchy

![Neon Overdrive preview](preview.png)

Neon Overdrive is a magenta-and-cyan Omarchy theme with animated Hyprland
transitions, translucent shell surfaces, a matching lock screen, an optional
audio-reactive Cava bar widget, and an optional animated `mpvpaper` wallpaper.

The standard Omarchy theme files live at the repository root, so a repository
named `omarchy-neon-overdrive-theme` installs with the slug `neon-overdrive`.
The installer changes only user-owned paths and never writes to
`/usr/share/omarchy`.

## Requirements

- Omarchy 4.0 or newer (tested with 4.0.0)
- Hyprland and the Omarchy Quickshell shell
- `cava` with PipeWire support for the spectrum widget
- `mpvpaper` for the animated desktop
- `jq`, `luac`, Bash, and standard Omarchy commands

`cava` is in the Arch repositories. `mpvpaper` is normally installed from the
AUR. The installer checks both and offers to install them through the Omarchy
package commands.

## Install

For a private GitHub repository, install the core theme over SSH:

```bash
omarchy theme install git@github.com:0xsl0th/omarchy-neon-overdrive-theme.git
cd ~/.config/omarchy/themes/neon-overdrive
./install.sh
```

You can also run `./install.sh` from any checkout. In that case it copies the
curated theme files into the user theme directory before applying them.

Useful modes:

```bash
./install.sh --check
./install.sh --install-deps
./install.sh --no-start
```

The full installer:

1. validates the repository and checks dependencies;
2. makes timestamped backups under the user's XDG state directory;
3. installs and enables `neon-overdrive.cava` before the clock;
4. installs the silent 12-second video and its launcher;
5. adds one clearly marked block to `~/.config/hypr/autostart.lua`;
6. applies `neon-overdrive` with `omarchy theme set`;
7. disables `omarchy.background` through the Omarchy plugin CLI so the live
   wallpaper is visible; and
8. reloads and checks Hyprland when a session is available.

For the static theme only, use `omarchy theme install` and do not run
`install.sh`.

## Uninstall

```bash
./uninstall.sh
```

The uninstaller stops only the managed wallpaper process, disables and stashes
only the managed plugin, removes only the marked Hyprland block, restores the
previous background-plugin state, and switches back to the recorded previous
theme when it is still available. Removed files are retained in a timestamped
recovery backup. A Git-managed theme checkout is preserved.

## Validation

```bash
./validate.sh
```

Validation is repository-only: it does not apply the theme, reload Hyprland, or
touch live configuration.

## Assets and provenance

The city artwork was generated with OpenAI image generation and the original
PNG retains its signed C2PA manifest. Derived previews, poster, lock image, and
video are documented with SHA-256 checksums in [ASSETS.md](ASSETS.md). Those
derived files may not retain the embedded C2PA manifest, so keep the original
source and checksum file with any copy of the theme.
