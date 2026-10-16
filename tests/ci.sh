#!/bin/sh
# Run the test suite for one distro in a Docker container (used by GitHub Actions).
#   sh tests/ci.sh <distro>
# Each distro is tested twice: once on the bare image (no KDE packages, so the
# script's plain-sh fallback is used), then again after installing that distro's
# own kwriteconfig, KWin and D-Bus packages with a real headless KWin running.
set -eu

distro=${1:?usage: ci.sh <distro>}
NIX='nix --extra-experimental-features nix-command --extra-experimental-features flakes'
APT='apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends'
PATH_EXTRA=

case $distro in
arch)
	image=archlinux:latest
	install='pacman -Syu --noconfirm --needed kconfig kwin dbus mesa' ;;
debian-12) # Plasma 5.27
	image=debian:12
	install="$APT libkf5config-bin kwin-wayland dbus" ;;
debian-13) # Plasma 6
	image=debian:13
	install="$APT libkf6config-bin kwin-wayland dbus" ;;
ubuntu-24.04) # Plasma 5.27
	image=ubuntu:24.04
	install="$APT libkf5config-bin kwin-wayland dbus" ;;
ubuntu-latest) # Plasma 6
	image=ubuntu:latest
	install="$APT libkf6config-bin kwin-wayland dbus" ;;
fedora)
	image=fedora:latest
	install='dnf install -y /usr/bin/kwriteconfig6 /usr/bin/kwin_wayland /usr/bin/dbus-run-session /usr/bin/dbus-send' ;;
opensuse-tumbleweed)
	image=opensuse/tumbleweed:latest
	install='zypper -n in kwin6 dbus-1 && { command -v kwriteconfig6 || zypper -n in kf6-kconfig-tools || zypper -n in kf6-kconfig; } &&
		for p in dbus-1-daemon dbus-1-tools dbus-1-x11; do command -v dbus-run-session || zypper -n in $p || true; done &&
		command -v dbus-run-session' ;;
void)
	image=ghcr.io/void-linux/void-glibc-full:latest
	install='xbps-install -Syu xbps && xbps-install -Syu && xbps-install -y kf6-kconfig kwin dbus' ;;
alpine)
	image=alpine:latest
	install='apk add --no-cache kconfig kwin dbus' ;;
nixos)
	image=nixos/nix:latest
	install="$NIX profile install --profile /nix/var/nix/profiles/kde nixpkgs#kdePackages.kconfig nixpkgs#kdePackages.kwin nixpkgs#dbus"
	PATH_EXTRA=/nix/var/nix/profiles/kde/bin: ;;
gentoo) # building KWin from source takes hours, so only the fallback path
	image=gentoo/stage3:latest
	install= ;;
*) echo "unknown distro $distro" >&2; exit 2 ;;
esac

name=wcpo-$distro
docker rm -f "$name" >/dev/null 2>&1 || true
# privileged: distros ship kwin_wayland with file capabilities, and exec fails
# with EPERM if the container may not grant them
docker run -d --name "$name" --privileged -v "$PWD:/src:ro" "$image" sleep infinity >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1' EXIT

# a normal user (uid 4242 is free on every image); written directly so it works
# on images without useradd
docker exec "$name" sh -c 'echo "tester:x:4242:4242::/home/tester:/bin/sh" >>/etc/passwd &&
	echo "tester:x:4242:" >>/etc/group && mkdir -p /home/tester && chown 4242:4242 /home/tester'
# Qt D-Bus aborts without a machine id, and containers often have none
fix_machine_id() {
	docker exec "$name" sh -c '[ -s /etc/machine-id ] ||
		tr -d - </proc/sys/kernel/random/uuid >/etc/machine-id'
}
fix_machine_id

as_user() {
	docker exec -u 4242:4242 -e HOME=/home/tester -e LANG=C.UTF-8 \
		-e PATH="$PATH_EXTRA$(docker exec "$name" sh -c 'echo $PATH')" "$name" "$@"
}

echo "=== $distro: refuses to run as root"
if docker exec "$name" sh /src/waylandclickpreventionoff.sh >/dev/null 2>&1; then
	echo "FAIL: script ran as root" >&2; exit 1
fi
echo "ok:   refused"

echo "=== $distro: bare image, fallback path"
as_user sh /src/tests/check.sh fallback

[ -n "$install" ] || exit 0
echo "=== $distro: installing KDE packages"
docker exec "$name" sh -c "$install" >/tmp/install-$distro.log 2>&1 || {
	tail -50 /tmp/install-$distro.log; exit 1; }
fix_machine_id

echo "=== $distro: kwriteconfig + live KWin"
as_user sh /src/tests/check.sh full
