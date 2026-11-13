#!/bin/sh
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Required Notice: Copyright (c) 2026 nanaisu - NBT-AAD (https://github.com/Sq00ky/Supra-iDrive6-Android-Auto)
# Host smoke test of the pf_aa tool (tools/pf_aa.cpp) against a fake pfctl: the packet filter is never switched off
# (no `pfctl -d` in any mode), --activate loads pf.conf and switches the filter on, --check / --install / --uninstall
# do what they say, and NBT_KEEP_PF is never written. Usage: test_pf_aa_tool.sh <host c++ compiler> (from milestone-7).
set -e
CXX=${1:-g++}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# Fake pfctl: state in $T/pf (status, loaded rules), every call logged to $T/pfctl.log.
cat > "$T/pfctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/pfctl.log"
case "\$1" in
  -n) exit 0 ;;
  -f) cp "\$2" "$T/loaded"; exit 0 ;;
  -e) echo Enabled > "$T/status"; exit 0 ;;
  -d) echo Disabled > "$T/status"; exit 0 ;;
  -s) if [ "\$2" = info ]; then echo "Status: \$(cat "$T/status")"; else cat "$T/loaded"; fi; exit 0 ;;
esac
exit 1
EOF
chmod +x "$T/pfctl"
$CXX -std=gnu++0x -Wall -DNBT_PFCTL="\"$T/pfctl\"" -DNBT_PF_CHECKFILE="\"$T/check.conf\"" -o "$T/pf_aa" tools/pf_aa.cpp

STOCK='block all
pass in quick on uap0 proto tcp from 172.16.224/24 to 172.16.224.1 port {5000,7000}
anchor route_USB'
printf '%s\n' "$STOCK" > "$T/pf.conf"
printf '%s\n' "$STOCK" > "$T/loaded"
echo Enabled > "$T/status"
printf 'NBT_LOG_FILE=/x\nNBT_KEEP_PF=1\n' > "$T/env"
P="--pf $T/pf.conf --env $T/env --backup $T/pf.bak"

# 1. Stock file: --check says missing (7), --activate refuses to load anything (7).
rc=0; "$T/pf_aa" --check $P > "$T/out" || rc=$?
[ $rc = 7 ] || fail "check on stock: rc $rc"
rc=0; "$T/pf_aa" --activate $P > "$T/out" || rc=$?
[ $rc = 7 ] || fail "activate on stock: rc $rc"
grep -q '^-f' "$T/pfctl.log" && fail "activate on stock loaded something"

# 2. --install writes the rules and the backup, does not touch the env file.
"$T/pf_aa" --install $P > "$T/out" || fail "install rc $?"
grep -q 'port 5277' "$T/pf.conf" || fail "rules not written"
[ "$(cat "$T/pf.bak")" = "$STOCK" ] || fail "backup is not the stock file"
[ "$(cat "$T/env")" = "$(printf 'NBT_LOG_FILE=/x\nNBT_KEEP_PF=1')" ] || fail "install changed the env file"

# 3. Rules in pf.conf, not loaded, filter off: --check 9, --activate loads + enables (0), then --check 0.
echo Disabled > "$T/status"
rc=0; "$T/pf_aa" --check $P > "$T/out" || rc=$?
[ $rc = 9 ] || fail "check not active: rc $rc"
"$T/pf_aa" --activate $P > "$T/out" || fail "activate rc $?"
[ "$(cat "$T/status")" = Enabled ] || fail "activate did not switch the filter on"
"$T/pf_aa" --check $P > "$T/out" || fail "check after activate rc $?"

# 4. --uninstall --load: stock rules back, filter stays ON, old NBT_KEEP_PF line removed.
"$T/pf_aa" --uninstall --load $P > "$T/out" || fail "uninstall rc $?"
[ "$(cat "$T/pf.conf")" = "$STOCK" ] || fail "pf.conf not restored"
[ "$(cat "$T/status")" = Enabled ] || fail "uninstall switched the filter off"
[ "$(cat "$T/env")" = "NBT_LOG_FILE=/x" ] || fail "NBT_KEEP_PF not removed"

# 5. Never `pfctl -d`, in any mode.
grep -qx -- '-d' "$T/pfctl.log" && fail "pfctl -d was run"
grep -rq "NBT_KEEP_PF=1" "$T/env" && fail "NBT_KEEP_PF written"
echo "test_pf_aa_tool: all passed"
