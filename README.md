# waylandclickpreventionoff

[![test](https://github.com/GiovMaggi/waylandclickpreventionoff/actions/workflows/test.yml/badge.svg)](https://github.com/GiovMaggi/waylandclickpreventionoff/actions/workflows/test.yml)

One script that turns off KDE Plasma's Wayland protection that blocks legacy X11 apps from
**reading input in the background** and **sending clicks/keys to the desktop**.

Fixes things like:

- **AnyDesk / TeamViewer**: people can see your screen but can't control it
- **OBS global hotkeys** not working when OBS isn't focused (run OBS through XWayland, see below)
- Macro tools, auto-clickers, and other X11 apps that send input or listen for hotkeys

## Usage

```sh
git clone https://github.com/GiovMaggi/waylandclickpreventionoff
sh waylandclickpreventionoff/waylandclickpreventionoff.sh
```

That's it. There are no options: running it turns the protection off.

Run it as your normal user, **not** with `sudo`. The settings are per user. It applies
immediately by asking KWin to reload its config. If that fails, log out and back in.
A timestamped backup of `~/.config/kwinrc` is made every time you run it.

## Supported distros

Anything running KDE Plasma on Wayland. Every push is tested automatically on GitHub Actions
against real containers of:

| Distro | Tested |
|---|---|
| Arch Linux | plain-sh fallback, kwriteconfig6 (live KWin reload verified on a real Arch desktop: Arch's KWin segfaults in GPU-less CI containers) |
| Debian 12 (Plasma 5.27) | plain-sh fallback, kwriteconfig5 + live KWin |
| Debian 13 | plain-sh fallback, kwriteconfig6 + live KWin |
| Ubuntu 24.04 (Plasma 5.27) | plain-sh fallback, kwriteconfig5 + live KWin |
| Ubuntu latest | plain-sh fallback, kwriteconfig6 + live KWin |
| Fedora | plain-sh fallback, kwriteconfig6 + live KWin |
| openSUSE Tumbleweed | plain-sh fallback, kwriteconfig6 + live KWin |
| Void Linux | plain-sh fallback, kwriteconfig6 + live KWin |
| Alpine (busybox sh) | plain-sh fallback, kwriteconfig6 + live KWin |
| Nix (nixpkgs KDE packages) | plain-sh fallback, kwriteconfig6 + live KWin |
| Gentoo | plain-sh fallback (building KWin from source takes too long for CI) |

Derivatives (Manjaro, EndeavourOS, CachyOS, Kubuntu, KDE neon, Mint, Nobara, ...) use the same
packages as their base distro.

The script only needs a POSIX `sh`, so no packages need to be installed. It uses
`kwriteconfig6`/`kwriteconfig5` if available and edits the file directly otherwise. KWin is
reloaded through `dbus-send`, `gdbus` or `qdbus`, whichever exists.

- **Plasma 6.1+**: all settings apply (including the input-injection prompt).
- **Plasma 5.27 / 6.0**: the background key/mouse reading settings apply. The no-prompt setting is
  ignored because those versions don't have the prompt.

### NixOS

On a normal NixOS install the script works as-is. If your Plasma config is managed
declaratively with [plasma-manager](https://github.com/nix-community/plasma-manager), the script
will detect it and refuse to edit. Add this to your home-manager config instead:

```nix
programs.plasma.configFile.kwinrc.Xwayland = {
  XwaylandEavesdrops = "All";
  XwaylandEavesdropsMouse = true;
  XwaylandEisNoPrompt = true;
};
```

## What it changes

In `~/.config/kwinrc`, group `[Xwayland]`:

| Key | Value | Effect |
|---|---|---|
| `XwaylandEavesdrops` | `All` | X11 apps can see every key press, even when not focused |
| `XwaylandEavesdropsMouse` | `true` | X11 apps can see mouse buttons, even when not focused |
| `XwaylandEisNoPrompt` | `true` | X11 apps can send mouse/keyboard input without asking |

These are the same options as *System Settings → Security & Privacy → Legacy X11 App Support*,
plus the hidden no-prompt switch.

## OBS hotkeys

Native Wayland apps can't get global hotkeys this way. Run OBS through XWayland so the setting
above applies to it:

```sh
QT_QPA_PLATFORM=xcb obs
```

To make that permanent, copy OBS's `.desktop` file to `~/.local/share/applications/` and change
its `Exec=` line to `Exec=env QT_QPA_PLATFORM=xcb obs`. For the Flatpak version, use
`flatpak override --user --env=QT_QPA_PLATFORM=xcb com.obsproject.Studio`.

## Undo

Restore one of the `~/.config/kwinrc.bak-*` backups, or delete the three keys above from the
`[Xwayland]` group of `~/.config/kwinrc`. You can also set *Legacy X11 App Support* back to
"Only Meta, Control, Alt and Shift keys" in System Settings. Then log out and back in.

## Running the tests yourself

With Docker installed: `sh tests/ci.sh fedora` (or any distro from the table, e.g. `arch`,
`debian-13`, `nixos`).

## Security warning

This removes a real protection. With it off, **any** X11 app on your system (games, chat apps,
launchers, anything running through XWayland) can log everything you type, including
passwords, and control your mouse and keyboard.
