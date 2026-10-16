#!/bin/sh
# Test suite, run inside a distro container as a normal user.
#   check.sh fallback  no KDE packages installed: tests the plain awk INI editor
#   check.sh full      kwriteconfig + a real headless KWin: tests the KDE tools
#                      and the live D-Bus reload
set -eu

SCRIPT=$(cd "$(dirname "$0")/.." && pwd)/waylandclickpreventionoff.sh
mode=${1:?usage: check.sh fallback|full}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok:   %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

mkdir -p "$HOME"
WORK=$(mktemp -d)

# value of key $3 in group $2 of file $1
get() {
	awk -v grp="[$2]" -v key="$3" '
		/^\[/ { ingrp = ($0 == grp); next }
		ingrp && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
	' "$1"
}

count() { grep -c "^$2=" "$1" || true; }

assert_off() { # kwinrc
	[ "$(get "$1" Xwayland XwaylandEavesdrops)" = All ] || fail "XwaylandEavesdrops not All in $1"
	[ "$(get "$1" Xwayland XwaylandEavesdropsMouse)" = true ] || fail "XwaylandEavesdropsMouse not true in $1"
	[ "$(get "$1" Xwayland XwaylandEisNoPrompt)" = true ] || fail "XwaylandEisNoPrompt not true in $1"
	for k in XwaylandEavesdrops XwaylandEavesdropsMouse XwaylandEisNoPrompt; do
		[ "$(count "$1" "$k")" = 1 ] || fail "$k appears more than once in $1"
	done
}

run() { # config-dir -> prints script output
	XDG_CONFIG_HOME=$1 XDG_CURRENT_DESKTOP=KDE sh "$SCRIPT"
}

file_tests() {
	# 1. brand new user: no ~/.config at all
	run "$WORK/fresh" >"$WORK/out"
	assert_off "$WORK/fresh/kwinrc"
	ok "creates kwinrc from nothing"

	# 2. existing config with other groups and the KDE default value
	mkdir -p "$WORK/existing"
	cat >"$WORK/existing/kwinrc" <<-EOF
		[Compositing]
		Backend=OpenGL

		[Xwayland]
		Scale=1
		XwaylandEavesdrops=Combinations

		[Windows]
		Foo=1
	EOF
	chmod 600 "$WORK/existing/kwinrc"
	run "$WORK/existing" >"$WORK/out"
	assert_off "$WORK/existing/kwinrc"
	[ "$(get "$WORK/existing/kwinrc" Compositing Backend)" = OpenGL ] || fail "lost [Compositing] Backend"
	[ "$(get "$WORK/existing/kwinrc" Windows Foo)" = 1 ] || fail "lost [Windows] Foo"
	[ "$(get "$WORK/existing/kwinrc" Xwayland Scale)" = 1 ] || fail "lost [Xwayland] Scale"
	[ "$(ls -l "$WORK/existing/kwinrc" | cut -c1-10)" = "-rw-------" ] || fail "file permissions changed"
	ok "updates existing kwinrc, keeps other settings and permissions"

	# 3. running twice changes nothing and leaves backups
	sleep 1 # backups are named by the second
	cp "$WORK/existing/kwinrc" "$WORK/before"
	run "$WORK/existing" >"$WORK/out"
	assert_off "$WORK/existing/kwinrc"
	cmp -s "$WORK/before" "$WORK/existing/kwinrc" || fail "second run changed the file"
	[ "$(ls "$WORK/existing" | grep -c '^kwinrc\.bak-')" = 2 ] || fail "expected 2 backups"
	ok "idempotent, makes a backup on every run"

	# 4. NixOS + plasma-manager: kwinrc is a link into the Nix store -> refuse
	mkdir -p "$WORK/nix"
	ln -s /nix/store/00000000000000000000000000000000-home-manager-files/kwinrc "$WORK/nix/kwinrc"
	if run "$WORK/nix" >"$WORK/out" 2>&1; then fail "did not refuse a Nix-managed kwinrc"; fi
	grep -q 'programs.plasma.configFile' "$WORK/out" || fail "no plasma-manager hint printed"
	[ -L "$WORK/nix/kwinrc" ] || fail "replaced the Nix-managed symlink"
	ok "refuses Nix-managed kwinrc and prints the plasma-manager snippet"
}

case $mode in
fallback)
	for c in kwriteconfig6 kwriteconfig5; do
		! have "$c" || fail "$c is installed, fallback path would not be tested"
	done
	file_tests
	run "$WORK/fresh" | grep -q 'Could not reach KWin' || fail "did not report missing KWin"
	ok "reports when KWin is not running"
	;;
full)
	have kwriteconfig6 || have kwriteconfig5 || fail "no kwriteconfig installed"
	file_tests
	exec dbus-run-session -- sh "$0" live "$WORK"
	;;
live)
	# internal: inside a private D-Bus session, start a real headless KWin and
	# check the script reconfigures it live
	WORK=$2
	export XDG_CONFIG_HOME="$WORK/live" XDG_RUNTIME_DIR="$(mktemp -d /tmp/wcpo.XXXXXX)" # short: socket paths max 108 bytes
	mkdir -p "$XDG_CONFIG_HOME" && chmod 700 "$XDG_RUNTIME_DIR"
	KWIN_COMPOSE=Q QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 \
		kwin_wayland --virtual --no-lockscreen >"$WORK/kwin.log" 2>&1 &
	kwin=$!
	i=0
	until dbus-send --session --print-reply --dest=org.freedesktop.DBus / \
		org.freedesktop.DBus.NameHasOwner string:org.kde.KWin 2>/dev/null | grep -q 'boolean true'; do
		i=$((i + 1))
		if [ $i -gt 120 ] || ! kill -0 $kwin 2>/dev/null; then
			cat "$WORK/kwin.log" >&2
			fail "KWin did not start"
		fi
		sleep 0.5
	done
	ok "headless KWin $(kwin_wayland --version 2>/dev/null | awk '{print $NF}') is running"
	XDG_CURRENT_DESKTOP=KDE sh "$SCRIPT" >"$WORK/out"
	cat "$WORK/out"
	assert_off "$XDG_CONFIG_HOME/kwinrc"
	grep -q 'KWin reloaded' "$WORK/out" || { cat "$WORK/kwin.log" >&2; fail "KWin was not reloaded"; }
	sleep 1
	kill -0 $kwin 2>/dev/null || { cat "$WORK/kwin.log" >&2; fail "KWin died after reload"; }
	ok "running KWin accepted the reload and is still alive"
	kill $kwin
	rm -rf "$XDG_RUNTIME_DIR"
	;;
*) fail "unknown mode $mode" ;;
esac
echo "ALL TESTS PASSED ($mode)"
