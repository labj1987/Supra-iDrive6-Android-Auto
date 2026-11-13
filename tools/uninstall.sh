#!/bin/sh
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Required Notice: Copyright (c) 2026 nanaisu - NBT-AAD (https://github.com/Sq00ky/Supra-iDrive6-Android-Auto)
#
# NBT-AAD uninstaller for the head unit (QNX 6.5 sh / ksh: POSIX sh only): puts back what tools/install.sh backed up.
#
#   sh /mnt/umassXXXXX/uninstall.sh                      the newest backup in /opt/aa-backup
#   sh /mnt/umassXXXXX/uninstall.sh /opt/aa-backup/<time> that one
#
# Restores pf.conf, /opt/aa and the iDrive app folder as they were before the install (removes them if they did not
# exist), puts the autostart flags back, loads the restored pf.conf into the running filter with the filter left ON,
# and remounts /fs/sda0 read-only. The backup itself is kept.
#
# NBT_ROOT=<dir> prefixes every head-unit path and skips mount / pf steps (host tests only); MOUNT / PFCTL / SLAY
# override those commands.

R=${NBT_ROOT:-}
MOUNT=${MOUNT:-mount}
PFCTL=${PFCTL:-pfctl}
SLAY=${SLAY:-slay}
AA=$R/opt/aa
APP=$R/opt/hmi/ID5/data/ro/Plugins/NbtAad
PF=$R/fs/sda0/etc/pf.conf
VARAA=$R/var/opt/aa
BACKUPS=$R/opt/aa-backup
MNT=/fs/sda0
REMOUNTED=0

say() { echo "uninstall: $*"; }
die() {
    echo "uninstall: ERROR: $*" >&2
    if [ "$REMOUNTED" = 1 ]; then $MOUNT -ur $MNT || echo "uninstall: run by hand: mount -ur $MNT" >&2; fi
    exit 1
}

if [ -n "$1" ]; then
    B=$1
else
    B=$(ls -d "$BACKUPS"/*/ 2>/dev/null | sort | tail -1)
    B=${B%/}
fi
[ -n "$B" ] && [ -f "$B/existed" ] || die "no install backup found (${B:-$BACKUPS/*}): nothing changed"
say "restoring from $B"
existed() { grep -qx "$1" "$B/existed"; }
if existed pf.conf; then [ -f "$B/pf.conf" ] || die "$B/pf.conf missing: nothing changed"; fi

if [ -z "$R" ]; then
    $MOUNT -uw $MNT || die "mount -uw $MNT failed"
    REMOUNTED=1
fi
$SLAY -f nbt-aad > /dev/null 2>&1   # stop the daemon before its files go

# pf.conf: written in place (same file, as pf_aa does), only if a backup of it exists.
if existed pf.conf; then
    cat "$B/pf.conf" > "$PF" || die "restoring $PF failed: cp $B/pf.conf $PF"
    cmp -s "$B/pf.conf" "$PF" 2>/dev/null || [ "$(cat "$B/pf.conf")" = "$(cat "$PF")" ] || die "$PF does not read back as the backup"
fi

restore_dir() {   # $1 = target dir, $2 = name in the backup
    rm -rf "$1" || die "cannot remove $1"
    if existed "$2"; then
        cp -Rp "$B/$2" "$1" || die "restoring $1 failed: cp -R $B/$2 $1"
    fi
}
restore_dir "$AA" aa
restore_dir "$APP" NbtAad

for f in autostart autostart-failed; do
    rm -f "$VARAA/$f"
    [ -f "$B/var-$f" ] && cp -p "$B/var-$f" "$VARAA/$f"
done
sync

# The restored rules into the running filter; the filter stays on.
if [ -z "$R" ] && existed pf.conf; then
    $PFCTL -f "$PF" || echo "uninstall: WARNING: pfctl -f $PF failed: reboot the head unit" >&2
    $PFCTL -e > /dev/null 2>&1   # "already enabled" is fine
fi

if [ "$REMOUNTED" = 1 ]; then
    $MOUNT -ur $MNT || { echo "uninstall: WARNING: mount -ur $MNT failed: run it by hand" >&2; exit 1; }
fi
say "done (backup kept in $B). Restart the HMI (OnOffDSICommander appreset) or the head unit."
exit 0
