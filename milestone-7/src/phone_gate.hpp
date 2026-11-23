// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: Copyright (c) 2026 nanaisu - NBT-AAD (https://github.com/Sq00ky/Supra-iDrive6-Android-Auto)
#ifndef NBT_PHONE_GATE_HPP
#define NBT_PHONE_GATE_HPP

// Which TCP client on 5277 may start a wireless Android Auto session: only the phone that has just been handed the
// Wi-Fi details over Bluetooth in this run.
//
// Before, the listener took the first client from the hotspot / Wi-Fi Direct subnet, at any time, so anything else on
// the car's Wi-Fi (another phone that once learned the CarPlay passphrase, a laptop) could open a session. What the
// protocol gives us to tie the TCP client to the Bluetooth phone:
//   - the phone's Wi-Fi MAC is not its Bluetooth address (Android randomises it per network), and the Wi-Fi start
//     messages carry no phone address or token we could check on the TCP side;
//   - Android Auto's TLS has the head unit as the TLS client; the phone's certificate only proves "some Android Auto
//     phone", not which one, and checking it needs Google's CA (not in this repo).
// So the binding is in time and address: handing the Wi-Fi details to the phone over Bluetooth (WifiInfoResponse
// written) arms the gate; the first client from the Android Auto subnets while it is armed is accepted and the gate
// binds to its IPv4 address. That binding is only TENTATIVE until an Android Auto session actually starts for it
// (confirm()): until then a later client may replace it, so a squatter already on the hotspot that connects first but
// cannot speak Android Auto cannot hold the slot and lock the real phone out. Once confirmed, while the Bluetooth link
// of that hand-off stays open (the phone keeps it up during the session), and for a short grace after it closes, only
// that address may connect again (a reconnect of the same phone). Anything else is refused and logged. Without a
// hand-off, nothing is accepted. NBT_AA_GATE=0 turns it off (old behaviour).
//
// Pure logic, no I/O, times in ms from any monotonic clock: host test tests/test_phone_gate.cpp.

#include <stdint.h>

namespace nbt {

class PhoneGate {
public:
    enum Verdict { kAccept, kRejectNotArmed, kRejectOtherPhone };

    // From the first TCP connect after a hand-off: how long the phone gets to join the Wi-Fi and connect. The
    // wireless thread waits 90 s for it; a little more here so the gate is never the stricter one.
    static const uint32_t kJoinWindowMs = 100000;
    // After the hand-off's Bluetooth link closed: a session that is still up, or a quick reconnect of the same phone.
    static const uint32_t kGraceMs = 30000;

    PhoneGate() : armed_(false), linkOpen_(false), confirmed_(false), until_(0), boundIp_(0) {}

    // A new Bluetooth link opened: whatever an earlier link allowed ends here.
    void newLink() { disarm(); }
    // The Wi-Fi details were written to the phone on the current link. Again on the same link (the phone asks a second
    // time) keeps the phone already bound; the first time opens the join window.
    void arm(uint32_t now) {
        linkOpen_ = true;
        if (armed_ && boundIp_) {
            until_ = now + kGraceMs;
            return;
        }
        armed_ = true;
        until_ = now + kJoinWindowMs;
    }
    // The hand-off's Bluetooth link is still open (wireless thread, every second). Keeps a bound phone's window open.
    void linkAlive(uint32_t now) {
        if (!armed_) return;
        linkOpen_ = true;
        if (boundIp_ && (int32_t)(now + kGraceMs - until_) > 0) until_ = now + kGraceMs;
    }
    // The Bluetooth link closed: the window ends kGraceMs from now at the latest (never extends a join window).
    void linkClosed(uint32_t now) {
        if (!armed_) return;
        linkOpen_ = false;
        if (boundIp_ || (int32_t)(until_ - (now + kGraceMs)) > 0) until_ = now + kGraceMs;
    }
    void disarm() { armed_ = false; linkOpen_ = false; confirmed_ = false; boundIp_ = 0; }

    // An Android Auto session actually started for the bound client: lock the binding to it. Until this, the binding
    // is tentative and a later client may replace it in check(), so a hotspot squatter that connects first but never
    // becomes an Android Auto session cannot keep the real phone out.
    void confirm() { if (armed_ && boundIp_) confirmed_ = true; }

    // A client from the Android Auto subnets (host-order IPv4). kAccept binds the gate to it; the binding is tentative
    // (replaceable) until confirm(). A confirmed binding refuses any other address.
    Verdict check(uint32_t ip, uint32_t now) {
        if (armed_ && !linkOpen_ && (int32_t)(now - until_) >= 0) disarm();
        if (armed_ && linkOpen_ && !boundIp_ && (int32_t)(now - until_) >= 0) disarm();   // never joined
        if (!armed_) return kRejectNotArmed;
        if (boundIp_ && ip != boundIp_) {
            if (confirmed_) return kRejectOtherPhone;   // a live Android Auto session owns the gate
            // tentative binding only: the earlier client never became a session, so this one takes it over
        }
        boundIp_ = ip;
        return kAccept;
    }

    bool armed() const { return armed_; }
    bool confirmed() const { return confirmed_; }
    uint32_t boundIp() const { return boundIp_; }

private:
    bool armed_;
    bool linkOpen_;
    bool confirmed_;
    uint32_t until_;
    uint32_t boundIp_;
};

}  // namespace nbt

#endif
