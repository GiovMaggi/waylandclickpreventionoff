#!/bin/sh
# waylandclickpreventionoff - turn off KDE Plasma's Wayland restrictions that stop
# legacy X11 apps (AnyDesk, OBS hotkeys, TeamViewer, macro tools, ...) from reading
# keyboard/mouse input in the background and from sending clicks/keys to the desktop.
#
# Works on any distro running KDE Plasma (Arch, Debian/Ubuntu, Fedora, openSUSE,
# Void, NixOS, Alpine, Gentoo, ...). Needs only POSIX sh + awk; uses
# kwriteconfig6/5 when present. Just run it, there are no options.

set -eu

GROUP=Xwayland
KWINRC=${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root (the settings are per user)"

# NixOS / home-manager + plasma-manager: config is a read-only link into the Nix store
if [ -L "$KWINRC" ] && case $(readlink "$KWINRC") in /nix/store/*) true ;; *) false ;; esac; then
	die "$KWINRC is managed by Nix (plasma-manager/home-manager). Set it declaratively instead:
  programs.plasma.configFile.kwinrc.Xwayland = {
    XwaylandEavesdrops = \"All\";
    XwaylandEavesdropsMouse = true;
    XwaylandEisNoPrompt = true;
  };"
fi

case ${XDG_CURRENT_DESKTOP:-} in
*KDE*) ;;
*) say "warning: this does not look like a KDE Plasma session; writing the config anyway" ;;
esac

KWRITE=
for c in kwriteconfig6 kwriteconfig5; do
	if have "$c"; then KWRITE=$c; break; fi
done

set_key() {
	if [ -n "$KWRITE" ]; then
		"$KWRITE" --file "$KWINRC" --group "$GROUP" --key "$1" "$2"
		return
	fi
	# no kwriteconfig: edit the INI file directly. Blank lines are held back so a
	# new key lands right after the group's last entry.
	mkdir -p "$(dirname "$KWINRC")"
	[ -f "$KWINRC" ] || : >"$KWINRC"
	tmp=$(mktemp "$KWINRC.XXXXXX")
	awk -v grp="[$GROUP]" -v key="$1" -v val="$2" '
		function put() { if (!done) print key "=" val; done = 1 }
		function blanks() { for (; held > 0; held--) print "" }
		/^[ \t]*$/ { held++; next }
		/^\[/ { if (ingrp) put(); blanks(); ingrp = ($0 == grp); if (ingrp) seen = 1; print; next }
		ingrp && index($0, key "=") == 1 { blanks(); put(); next }
		{ blanks(); print }
		END {
			if (ingrp) put()
			if (!seen) { if (NR) print ""; print grp; print key "=" val }
			blanks()
		}
	' "$KWINRC" >"$tmp"
	cat "$tmp" >"$KWINRC" # keep the original file's permissions
	rm -f "$tmp"
}

# Ask the running KWin to reload its config; no logout needed
reload_kwin() {
	if have dbus-send && dbus-send --session --print-reply --dest=org.kde.KWin \
		/KWin org.kde.KWin.reconfigure >/dev/null 2>&1; then
		return 0
	fi
	if have gdbus && gdbus call --session --dest org.kde.KWin --object-path /KWin \
		--method org.kde.KWin.reconfigure >/dev/null 2>&1; then
		return 0
	fi
	for q in qdbus6 qdbus-qt6 qdbus-qt5 qdbus; do
		if have "$q" && "$q" org.kde.KWin /KWin reconfigure >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

[ ! -f "$KWINRC" ] || cp "$KWINRC" "$KWINRC.bak-$(date +%Y%m%d-%H%M%S)"

set_key XwaylandEavesdrops All        # X11 apps see every key, even unfocused
set_key XwaylandEavesdropsMouse true  # ... and mouse buttons
set_key XwaylandEisNoPrompt true      # X11 apps may send input without a prompt

say "Wayland click/keyboard protection for X11 apps is OFF ($KWINRC)."
say "Warning: any X11 app can now read everything you type and control your input."
if reload_kwin; then
	say "KWin reloaded, the change is active now."
else
	say "Could not reach KWin over D-Bus; log out and back in to apply."
fi
