#!/bin/sh
# waylandclickpreventionoff - turn off KDE Plasma's Wayland restrictions that stop
# legacy X11 apps (AnyDesk, OBS hotkeys, TeamViewer, macro tools, ...) from reading
# keyboard/mouse input in the background and from sending clicks/keys to the desktop.
#
# Works on any distro running KDE Plasma (Arch, Debian/Ubuntu, Fedora, openSUSE,
# Void, NixOS, ...). Needs only POSIX sh + awk; uses kwriteconfig6/5 when present.

set -eu

GROUP=Xwayland
KWINRC=${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc

# key=value pairs applied by "off"; "on" deletes them so KDE's defaults come back
SETTINGS='XwaylandEavesdrops=All
XwaylandEavesdropsMouse=true
XwaylandEisNoPrompt=true'

usage() {
	cat <<EOF
Usage: $(basename "$0") [off|on|status]

  off     (default) disable the protection: X11 apps can read all keys and mouse
          buttons in the background and send input to the desktop without a prompt
  on      restore KDE's default protection
  status  show the current settings

Settings are per user and live in $KWINRC. Do not run as root.
EOF
}

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

KWRITE=
for c in kwriteconfig6 kwriteconfig5; do
	if have "$c"; then KWRITE=$c; break; fi
done

# Fallback for systems without kwriteconfig: set or delete (empty value) a key in [$GROUP]
ini_edit() {
	key=$1 value=${2-} delete=${3-}
	[ -f "$KWINRC" ] || : >"$KWINRC"
	tmp=$(mktemp "$KWINRC.XXXXXX")
	# blank lines are held back so a new key lands right after the group's last entry
	awk -v grp="[$GROUP]" -v key="$key" -v val="$value" -v del="$delete" '
		function put() { if (!del && !done) print key "=" val; done = 1 }
		function blanks() { for (; held > 0; held--) print "" }
		/^[ \t]*$/ { held++; next }
		/^\[/ { if (ingrp) put(); blanks(); ingrp = ($0 == grp); if (ingrp) seen = 1; print; next }
		ingrp && index($0, key "=") == 1 { blanks(); put(); next }
		{ blanks(); print }
		END {
			if (ingrp) put()
			if (!seen && !del) { if (NR) print ""; print grp; print key "=" val }
			blanks()
		}
	' "$KWINRC" >"$tmp"
	cat "$tmp" >"$KWINRC" # keep the original file's permissions
	rm -f "$tmp"
}

set_key() {
	if [ -n "$KWRITE" ]; then
		"$KWRITE" --file "$KWINRC" --group "$GROUP" --key "$1" "$2"
	else
		ini_edit "$1" "$2"
	fi
}

delete_key() {
	if [ -n "$KWRITE" ]; then
		"$KWRITE" --file "$KWINRC" --group "$GROUP" --key "$1" --delete
	else
		ini_edit "$1" "" 1
	fi
}

read_key() {
	[ -f "$KWINRC" ] || return 0
	awk -v grp="[$GROUP]" -v key="$1" '
		/^\[/ { ingrp = ($0 == grp); next }
		ingrp && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
	' "$KWINRC"
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

status() {
	say "Config: $KWINRC"
	printf '%s\n' "$SETTINGS" | while IFS='=' read -r key _; do
		value=$(read_key "$key")
		say "  $key=${value:-<KDE default>}"
	done
}

preflight() {
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
	if [ "${XDG_SESSION_TYPE:-}" = x11 ]; then
		say "note: you are in an X11 session; these settings only matter under Wayland"
	fi
}

finish() {
	if reload_kwin; then
		say "KWin reloaded, the change is active now."
	else
		say "Could not reach KWin over D-Bus; log out and back in to apply."
	fi
	status
}

action=${1:-off}
case $action in
off | disable)
	preflight
	[ ! -f "$KWINRC" ] || cp "$KWINRC" "$KWINRC.bak-$(date +%Y%m%d-%H%M%S)"
	printf '%s\n' "$SETTINGS" | while IFS='=' read -r key value; do
		set_key "$key" "$value"
	done
	say "Wayland click/keyboard protection for X11 apps is OFF."
	say "Warning: any X11 app can now read everything you type and control your input."
	finish
	;;
on | enable | restore)
	preflight
	printf '%s\n' "$SETTINGS" | while IFS='=' read -r key _; do
		delete_key "$key"
	done
	say "Wayland click/keyboard protection for X11 apps restored to KDE defaults."
	finish
	;;
status) status ;;
-h | --help | help) usage ;;
*) usage >&2; exit 2 ;;
esac
