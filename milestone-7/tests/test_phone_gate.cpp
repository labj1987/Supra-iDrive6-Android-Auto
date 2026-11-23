// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: Copyright (c) 2026 nanaisu - NBT-AAD (https://github.com/Sq00ky/Supra-iDrive6-Android-Auto)
// Host test for src/phone_gate.hpp: only the phone that just got the Wi-Fi details over Bluetooth may connect, and the
// binding is tentative (replaceable) until an Android Auto session confirms it.

#include "phone_gate.hpp"
#include <assert.h>
#include <stdio.h>

using nbt::PhoneGate;

static const uint32_t kPhone = 0xac10e064u;   // 172.16.224.100
static const uint32_t kOther = 0xac10e065u;   // 172.16.224.101

int main() {
    // 1. No Bluetooth hand-off: nobody gets in.
    PhoneGate g;
    assert(g.check(kPhone, 1000) == PhoneGate::kRejectNotArmed);

    // 2. Hand-off, phone connects within the window: accepted and bound. The binding is tentative until a session
    //    starts (confirm()); after that another client is refused and the same phone (a reconnect) is accepted again
    //    while the link is up.
    g.arm(1000);
    g.linkAlive(5000);
    assert(g.check(kPhone, 6000) == PhoneGate::kAccept);
    assert(g.boundIp() == kPhone);
    g.confirm();                                                        // Android Auto session started for the phone
    assert(g.confirmed());
    assert(g.check(kOther, 7000) == PhoneGate::kRejectOtherPhone);
    for (uint32_t t = 8000; t < 600000; t += 1000) g.linkAlive(t);      // a 10 min session, link kept open
    assert(g.check(kPhone, 600000) == PhoneGate::kAccept);
    assert(g.check(kOther, 600000) == PhoneGate::kRejectOtherPhone);

    // 3. Link closed: the same phone has kGraceMs, then the gate is shut.
    g.linkClosed(600000);
    assert(g.check(kPhone, 600000 + PhoneGate::kGraceMs - 1) == PhoneGate::kAccept);
    assert(g.check(kPhone, 600000 + PhoneGate::kGraceMs) == PhoneGate::kRejectNotArmed);
    assert(!g.armed());

    // 4. Phone drops Bluetooth before its TCP connect (usual): still accepted within the grace.
    g.newLink();
    g.arm(1000000);
    g.linkClosed(1002000);
    assert(g.check(kPhone, 1002000 + PhoneGate::kGraceMs - 1) == PhoneGate::kAccept);

    // 5. Phone never joins: the window ends after kJoinWindowMs even with the link open; an intruder later is refused.
    g.newLink();
    g.arm(2000000);
    g.linkAlive(2000000 + PhoneGate::kJoinWindowMs - 1);
    g.linkAlive(2000000 + PhoneGate::kJoinWindowMs);
    assert(g.check(kOther, 2000000 + PhoneGate::kJoinWindowMs) == PhoneGate::kRejectNotArmed);

    // 6. A squatter on the hotspot connects first but never becomes a session: the real phone replaces the tentative
    //    binding instead of being locked out. Once the phone's session is confirmed, the squatter is refused.
    g.newLink();
    g.arm(2500000);
    assert(g.check(kOther, 2500100) == PhoneGate::kAccept);             // squatter: tentative bind
    assert(g.boundIp() == kOther && !g.confirmed());
    assert(g.check(kPhone, 2500200) == PhoneGate::kAccept);             // real phone takes over the unconfirmed bind
    assert(g.boundIp() == kPhone);
    g.confirm();
    assert(g.check(kOther, 2500300) == PhoneGate::kRejectOtherPhone);

    // 7. Details asked again on the same link keep the binding; a new Bluetooth link clears it.
    g.newLink();
    g.arm(3000000);
    assert(g.check(kPhone, 3000100) == PhoneGate::kAccept);
    g.confirm();
    g.arm(3000200);
    assert(g.check(kOther, 3000300) == PhoneGate::kRejectOtherPhone);
    g.newLink();                                                        // a new hand-off clears everything
    assert(!g.confirmed());
    assert(g.check(kPhone, 3000400) == PhoneGate::kRejectNotArmed);
    g.arm(3100000);
    assert(g.check(kOther, 3100100) == PhoneGate::kAccept);
    g.confirm();
    assert(g.check(kPhone, 3100200) == PhoneGate::kRejectOtherPhone);

    // 8. Clock wrap (32-bit ms): works across it.
    g.newLink();
    g.arm(0xfffff000u);
    g.linkClosed(0xfffff000u);
    assert(g.check(kPhone, 0x00000100u) == PhoneGate::kAccept);

    printf("test_phone_gate: all passed\n");
    return 0;
}
