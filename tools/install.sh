#!/bin/sh
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Required Notice: Copyright (c) 2026 nanaisu - NBT-AAD (https://github.com/Sq00ky/Supra-iDrive6-Android-Auto)
#
# NBT-AAD installer for the head unit (QNX 6.5 sh / ksh: POSIX sh only). Run it from the release folder on the USB
# stick, in the head unit's shell (see install.md for getting there):
#
#   sh /mnt/umassXXXXX/install.sh
#
# Release folder layout:
#   nbt-aad             the daemon
#   Releases/           the iDrive app files (libNbtAad.so, NbtAad.manifest, NbtAad*.xml, NbtAad_ALL_*.zip)
#   SHA256SUMS          `sha256sum nbt-aad Releases/*` made when the release is built (checked when the car has a
#                       SHA-256 tool: sha256sum, sha256 or openssl)
#   CKSUMS              `cksum nbt-aad Releases/*` (POSIX cksum: only used when no SHA-256 tool exists; a CRC catches a
#                       damaged copy, not a deliberately changed one)
#
# What it does: checks every file against the sums (stops if one does not match or nothing can check them), remounts
# /fs/sda0 read-write, backs up everything it changes to /opt/aa-backup/<time> (pf.conf, /opt/aa, the app folder,
# the autostart flags), installs, writes /opt/aa/nbt-aad.env with safe defaults (Bluetooth audio, cluster arrows off),
# turns Start automatically off, installs and checks the packet filter rules (nbt-aad --pf-install --load,
# --pf-check), and remounts /fs/sda0 read-only. tools/uninstall.sh puts the backup back.
#
# NBT_ROOT=<dir> prefixes every head-unit path and skips mount / pf steps (host tests only); MOUNT / SLAY override
# those commands.

R=${NBT_ROOT:-}
MOUNT=${MOUNT:-mount}
SLAY=${SLAY:-slay}
SRC=$(cd "$(dirname "$0")" && pwd)
AA=$R/opt/aa
APP=$R/opt/hmi/ID5/data/ro/Plugins/NbtAad
PF=$R/fs/sda0/etc/pf.conf
VARAA=$R/var/opt/aa
BACKUPS=$R/opt/aa-backup
MNT=/fs/sda0
REMOUNTED=0

say() { echo "install: $*"; }
die() {
    echo "install: ERROR: $*" >&2
    if [ "$REMOUNTED" = 1 ]; then $MOUNT -ur $MNT || echo "install: run by hand: mount -ur $MNT" >&2; fi
    exit 1
}

# ---- 1. the files and their sums ----------------------------------------------------------------------------------
[ -f "$SRC/nbt-aad" ] || die "$SRC/nbt-aad not found: run this script from the release folder"
[ -d "$SRC/Releases" ] || die "$SRC/Releases (the iDrive app files) not found"

sha_of() {
    if command -v sha256sum > /dev/null 2>&1; then sha256sum "$1" | sed 's/ .*//'
    elif command -v sha256 > /dev/null 2>&1; then sha256 -q "$1"
    elif command -v openssl > /dev/null 2>&1; then openssl dgst -sha256 "$1" | sed 's/.*= *//'
    else return 1
    fi
}

checked=0
cd "$SRC" || die "cannot cd to $SRC"
if [ -f SHA256SUMS ] && sha_of nbt-aad > /dev/null 2>&1; then
    say "checking SHA-256 sums"
    while read -r want name; do
        [ -n "$name" ] || continue
        name=${name#\*}
        [ -f "$name" ] || die "$name is listed in SHA256SUMS but missing"
        got=$(sha_of "$name") || die "cannot hash $name"
        [ "$got" = "$want" ] || die "$name: SHA-256 does not match (damaged or changed copy): nothing installed"
        checked=$((checked + 1))
    done < SHA256SUMS
elif [ -f CKSUMS ] && command -v cksum > /dev/null 2>&1; then
    say "no SHA-256 tool on this unit: checking POSIX cksum (CRC) sums instead"
    while read -r crc size name; do
        [ -n "$name" ] || continue
        [ -f "$name" ] || die "$name is listed in CKSUMS but missing"
        set -- $(cksum "$name")
        [ "$1" = "$crc" ] && [ "$2" = "$size" ] || die "$name: cksum does not match (damaged copy): nothing installed"
        checked=$((checked + 1))
    done < CKSUMS
else
    die "no SHA256SUMS + SHA-256 tool and no CKSUMS + cksum: cannot check the files, nothing installed"
fi
[ "$checked" -gt 0 ] || die "the sums file lists no files"
for f in nbt-aad Releases/*; do
    grep -q " \*\{0,1\}$f\$" SHA256SUMS CKSUMS 2>/dev/null || die "$f is not in the sums file: nothing installed"
done
say "$checked files checked"

# ---- 2. read-write, backup ----------------------------------------------------------------------------------------
if [ -z "$R" ]; then
    $MOUNT -uw $MNT || die "mount -uw $MNT failed"
    REMOUNTED=1
fi
$SLAY -f nbt-aad > /dev/null 2>&1   # a running daemon keeps its binary busy; "not found" is fine

STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null)-$$
B=$BACKUPS/$STAMP
mkdir -p "$B" || die "cannot create $B"
say "backing up to $B"
[ -f "$PF" ] && { cp -p "$PF" "$B/pf.conf" || die "backup of $PF failed"; }
[ -d "$AA" ] && { cp -Rp "$AA" "$B/aa" || die "backup of $AA failed"; }
[ -d "$APP" ] && { cp -Rp "$APP" "$B/NbtAad" || die "backup of $APP failed"; }
for f in autostart autostart-failed; do
    [ -f "$VARAA/$f" ] && { cp -p "$VARAA/$f" "$B/var-$f" || die "backup of $VARAA/$f failed"; }
done
# What existed before, so uninstall.sh removes what this run created.
{ [ -f "$PF" ] && echo pf.conf; [ -d "$AA" ] && echo aa; [ -d "$APP" ] && echo NbtAad; } > "$B/existed"
sync

# ---- 3. install ---------------------------------------------------------------------------------------------------
mkdir -p "$AA" "$APP" "$VARAA" || die "cannot create the install folders"
cp "$SRC/nbt-aad" "$AA/nbt-aad.new" && chmod 755 "$AA/nbt-aad.new" && mv -f "$AA/nbt-aad.new" "$AA/nbt-aad" \
    || die "installing $AA/nbt-aad failed (backup in $B)"
cp "$SRC"/Releases/* "$APP/" || die "installing the iDrive app to $APP failed (backup in $B)"
chmod 644 "$APP"/* 2>/dev/null

# Safe defaults: Bluetooth audio, no cluster/HUD arrows; Start automatically off (flag files, not env settings).
cat > "$AA/nbt-aad.env" <<'ENV'
# Written by tools/install.sh. One NAME=value per line; see the readme's Configuration section.
# Safe defaults. These lines win over the iDrive Settings checkboxes ("Use Native Audio instead of Bluetooth",
# "Turn arrows in cluster/HUD"): delete a line to control that setting from iDrive instead.
NBT_AUDIO_MODE=bt
NBT_KOMBI_NAV=0
ENV
chmod 644 "$AA/nbt-aad.env"
rm -f "$VARAA/autostart" "$AA/autostart"
say "nbt-aad.env written (Bluetooth audio, cluster arrows off); Start automatically is off"

# ---- 4. packet filter rules (required for wireless Android Auto; the filter is never switched off) ---------------
if [ -z "$R" ]; then
    "$AA/nbt-aad" --pf-install --load || die "nbt-aad --pf-install --load failed (backup in $B; uninstall.sh restores it)"
    "$AA/nbt-aad" --pf-check || die "nbt-aad --pf-check reports a problem (see above; backup in $B)"
fi
sync

# ---- 5. read-only again -------------------------------------------------------------------------------------------
if [ "$REMOUNTED" = 1 ]; then
    $MOUNT -ur $MNT || { echo "install: WARNING: mount -ur $MNT failed: run it by hand" >&2; exit 1; }
fi
say "done. Backup: $B. Restart the HMI (OnOffDSICommander appreset) or the head unit, then Media -> Android Auto."
exit 0
