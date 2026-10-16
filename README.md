# waylandclickpreventionoff

One script that turns off KDE Plasma's Wayland protection that blocks legacy X11 apps from
**reading input in the background** and **sending clicks/keys to the desktop**.

Fixes things like:

- **AnyDesk / TeamViewer**: people can see your screen but can't control it
- **OBS global hotkeys** not working when OBS isn't focused (run OBS through XWayland, see below)
- Macro tools, auto-clickers, and other X11 apps that send input or listen for hotkeys

## Usage

```sh
git clone https://github.com/GiovMaggi/waylandclickpreventionoff
cd waylandclickpreventionoff
sh waylandclickpreventionoff.sh          # turn the protection off
sh waylandclickpreventionoff.sh status   # show current settings
sh waylandclickpreventionoff.sh on       # restore KDE defaults
```

Run it as your normal user, **not** with `sudo`. The settings are per user. It applies
immediately by asking KWin to reload its config. If that fails, log out and back in.
A timestamped backup of `~/.config/kwinrc` is made every time you run `off`.

## Supported distros

Anything running KDE Plasma on Wayland: Arch, Manjaro, EndeavourOS, CachyOS, Debian, Ubuntu,
Kubuntu, KDE neon, Fedora, openSUSE, Void, Gentoo, NixOS, and others.

The script only needs POSIX `sh` and `awk`, so no packages need to be installed. It uses
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

## Security warning

This removes a real protection. With it off, **any** X11 app on your system (games, chat apps,
launchers, anything running through XWayland) can log everything you type, including
passwords, and control your mouse and keyboard. Run `sh waylandclickpreventionoff.sh on` to undo.
