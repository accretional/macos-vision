#!/usr/bin/env python3
"""Synthetic-frame tests for the gesture classifier (no camera required).

Builds hand observations with realistic 21-joint geometry for each pose, drives
them through GestureEngine over simulated time, and asserts the expected gesture
events fire. Run via `gesture.py --self-test`.
"""

import io
import json

from gesture import (GestureEngine, classify_pose, hand_features, iter_handpose,
                     WRIST, FINGERS)


class Cfg:
    mirror = False          # deterministic: image-right == "right"
    throw_dist = 0.18
    swipe_dist = 0.22
    swipe_time = 0.5
    swipe_cooldown = 0.7
    clutch_hold = 0.8
    drag_thresh = 8.0
    pointer_rect = (0, 0, 1920, 1080)


def _finger(joints, names, mcp_x, cy, extended):
    mcp, pip, dip, tip = names
    joints[mcp] = {"x": mcp_x, "y": cy, "confidence": 1.0}
    if extended:
        joints[pip] = {"x": mcp_x, "y": cy - 0.05, "confidence": 1.0}
        joints[dip] = {"x": mcp_x, "y": cy - 0.09, "confidence": 1.0}
        joints[tip] = {"x": mcp_x, "y": cy - 0.13, "confidence": 1.0}
    else:  # curled toward the palm
        joints[pip] = {"x": mcp_x, "y": cy + 0.02, "confidence": 1.0}
        joints[dip] = {"x": mcp_x, "y": cy + 0.04, "confidence": 1.0}
        joints[tip] = {"x": mcp_x, "y": cy + 0.06, "confidence": 1.0}


def synth_hand(pose, cx, cy, chirality="right"):
    """Build a raw hand observation positioned at (cx, cy) in the given pose."""
    j = {WRIST: {"x": cx, "y": cy + 0.15, "confidence": 1.0}}
    mcp_x = {"index": cx - 0.07, "middle": cx, "ring": cx + 0.05, "pinky": cx + 0.09}

    ext = {
        "open":  dict(index=True,  middle=True,  ring=True,  pinky=True),
        "fist":  dict(index=False, middle=False, ring=False, pinky=False),
        "point": dict(index=True,  middle=False, ring=False, pinky=False),
        "pinch": dict(index=True,  middle=False, ring=False, pinky=False),
    }[pose]
    for f in ("index", "middle", "ring", "pinky"):
        _finger(j, FINGERS[f], mcp_x[f], cy, ext[f])

    # Thumb
    tcmc, tmp, tip_, ttip = FINGERS["thumb"]
    j[tcmc] = {"x": cx - 0.10, "y": cy + 0.12, "confidence": 1.0}
    if pose == "open":  # thumb out
        j[tmp]  = {"x": cx - 0.13, "y": cy + 0.08, "confidence": 1.0}
        j[tip_] = {"x": cx - 0.16, "y": cy + 0.04, "confidence": 1.0}
        j[ttip] = {"x": cx - 0.19, "y": cy + 0.00, "confidence": 1.0}
    elif pose == "pinch":  # thumb tip meets the (extended) index tip
        itx = mcp_x["index"]
        j[tmp]  = {"x": cx - 0.10, "y": cy - 0.04, "confidence": 1.0}
        j[tip_] = {"x": itx - 0.03, "y": cy - 0.10, "confidence": 1.0}
        j[ttip] = {"x": itx + 0.02, "y": cy - 0.12, "confidence": 1.0}
    else:  # thumb in (fist, point)
        j[tmp]  = {"x": cx - 0.08, "y": cy + 0.09, "confidence": 1.0}
        j[tip_] = {"x": cx - 0.06, "y": cy + 0.07, "confidence": 1.0}
        j[ttip] = {"x": cx - 0.05, "y": cy + 0.05, "confidence": 1.0}

    return {"chirality": chirality, "confidence": 1.0, "joints": j}


def _types(events):
    return [e["type"] for e in events]


def _check(name, cond):
    status = "ok  " if cond else "FAIL"
    print(f"  [{status}] {name}")
    return cond


def _mjpeg_frame(handpose):
    """Frame a hand-pose result exactly as MVMjpegWriter does."""
    jpeg = b"\xff\xd8\xff\xe0FAKEJPEG\xff\xd9"  # body is ignored by the parser
    hp = json.dumps(handpose, separators=(",", ":"))
    hdr = ("--mvboundary\r\n"
           "Content-Type: image/jpeg\r\n"
           f"Content-Length: {len(jpeg)}\r\n"
           f"X-MV-face-hand-pose: {hp}\r\n\r\n").encode("utf-8")
    return hdr + jpeg


def test_mjpeg_parser():
    print("mjpeg stream parser:")
    f1 = {"operation": "hand-pose", "hands": [synth_hand("fist", 0.5, 0.5)]}
    f2 = {"operation": "hand-pose", "hands": [synth_hand("open", 0.6, 0.5)]}
    stream = io.BytesIO(_mjpeg_frame(f1) + _mjpeg_frame(f2) + b"--mvboundary--\r\n")
    got = list(iter_handpose(stream))
    ok = _check("parsed 2 frames", len(got) == 2)
    ok &= _check("frame 1 hand count", got and len(got[0]["hands"]) == 1)
    ok &= _check("frame 1 pose recovers as fist",
                 got and classify_pose(hand_features(got[0]["hands"][0])) == "fist")
    return ok


def run_self_test():
    print("gesture classifier self-test\n")
    ok = True

    ok &= test_mjpeg_parser()
    print()

    # ── 1. Pose classification ────────────────────────────────────────────────
    print("pose classification:")
    for pose in ("open", "fist", "point", "pinch"):
        got = classify_pose(hand_features(synth_hand(pose, 0.5, 0.5)))
        ok &= _check(f"{pose:6s} -> {got}", got == pose)

    eng = GestureEngine(Cfg())

    # ── 2. Clutch: two open palms held ~1s arms the controller ────────────────
    print("\nclutch (two open palms held):")
    armed_event = None
    t = 0.0
    while t <= 1.0 + 1e-9:
        evs = eng.process([synth_hand("open", 0.3, 0.5, "left"),
                           synth_hand("open", 0.7, 0.5, "right")], t)
        for e in evs:
            if e["type"] == "clutch":
                armed_event = e
        t += 0.1
    ok &= _check("clutch armed", armed_event is not None and armed_event["state"] == "armed")
    ok &= _check("engine is armed", eng.armed)

    # Drop to a single neutral (point) hand to clear the clutch latch.
    eng.process([synth_hand("point", 0.5, 0.5)], 1.5)

    # ── 3. Grab & throw right ─────────────────────────────────────────────────
    print("\ngrab & throw:")
    eng.process([synth_hand("fist", 0.50, 0.5)], 2.0)   # grab
    eng.process([synth_hand("fist", 0.72, 0.5)], 2.1)   # fling right
    evs = eng.process([synth_hand("open", 0.75, 0.5)], 2.2)  # release
    throw = next((e for e in evs if e["type"] == "throw"), None)
    ok &= _check("throw fired", throw is not None)
    ok &= _check("throw direction right", throw and throw["direction"] == "right")
    ok &= _check("release did not double-fire a swipe", "swipe" not in _types(evs))

    # ── 4. Open-palm swipe right → Spaces ─────────────────────────────────────
    print("\nopen-palm swipe:")
    swipe = None
    for ti, cx in [(3.0, 0.30), (3.1, 0.40), (3.2, 0.50), (3.3, 0.58)]:
        evs = eng.process([synth_hand("open", cx, 0.5)], ti)
        swipe = swipe or next((e for e in evs if e["type"] == "swipe"), None)
    ok &= _check("swipe fired", swipe is not None)
    ok &= _check("swipe direction right", swipe and swipe["direction"] == "right")

    # ── 5. Air-mouse pointer (index point) ────────────────────────────────────
    print("\nair-mouse pointer:")
    evs = eng.process([synth_hand("point", 0.5, 0.5)], 5.0)
    ptr = next((e for e in evs if e["type"] == "pointer"), None)
    ok &= _check("pointer fired", ptr is not None)
    ok &= _check("pointer within screen",
                 ptr and 0 <= ptr["x"] <= 1920 and 0 <= ptr["y"] <= 1080)

    # ── 6. Pinch click ────────────────────────────────────────────────────────
    print("\npinch click:")
    eng.process([synth_hand("pinch", 0.5, 0.5)], 6.0)        # pinch down
    evs = eng.process([synth_hand("open", 0.5, 0.5)], 6.1)   # release, no move
    ok &= _check("click fired", "click" in _types(evs))

    # ── 7. Pinch drag ─────────────────────────────────────────────────────────
    print("\npinch drag:")
    eng.process([synth_hand("pinch", 0.50, 0.5)], 7.0)       # pinch down
    evs1 = eng.process([synth_hand("pinch", 0.62, 0.5)], 7.1)  # move while held
    evs2 = eng.process([synth_hand("open", 0.62, 0.5)], 7.2)   # release
    ok &= _check("drag-start fired", "drag-start" in _types(evs1))
    ok &= _check("drag-move fired", "drag-move" in _types(evs1))
    ok &= _check("drag-end fired", "drag-end" in _types(evs2))

    # ── 8. Disarm gate ────────────────────────────────────────────────────────
    print("\ndisarm gate:")
    t = 8.0
    while t <= 9.0 + 1e-9:  # two palms again → toggle back to disarmed
        eng.process([synth_hand("open", 0.3, 0.5, "left"),
                     synth_hand("open", 0.7, 0.5, "right")], t)
        t += 0.1
    ok &= _check("engine disarmed", not eng.armed)
    evs = eng.process([synth_hand("point", 0.5, 0.5)], 9.5)
    ok &= _check("no actions while disarmed", evs == [])

    print("\n" + ("ALL PASSED" if ok else "SOME TESTS FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(run_self_test())
