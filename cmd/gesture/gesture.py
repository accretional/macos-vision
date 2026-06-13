#!/usr/bin/env python3
"""
Camera-aided live hand-gesture control for macOS.

This is an ORCHESTRATION tool, not a subcommand: it composes existing
macos-vision subcommands rather than wrapping a new macOS API.

    streamcapture video  ──MJPEG──▶  face --operation hand-pose  ──MJPEG+headers──▶  this tool
                                                                                        │
                                              temporal gesture classifier              │
                                                                                        ▼
                                            window / input subcommands  ◀── recognised gestures

Pipeline data path
------------------
`face` runs VNDetectHumanHandPoseRequest per frame and, in stream mode, writes
the result as a per-frame multipart header `X-MV-face-hand-pose: <json>` on the
MJPEG it forwards to stdout. We read that stream, ignore the JPEG payloads, and
feed the 21-joint hand data to the classifier.

Gesture vocabulary (v1)
-----------------------
Pose → mode mapping is conflict-free because each gesture owns a distinct pose:

    two open palms (held)  → CLUTCH       arm / disarm the controller
    fist + fling + release → GRAB & THROW move focused window to another display
                                          (up = maximise, down = minimise)
    one open palm + swipe  → SPACES       switch desktop / Mission Control
    index point            → AIR-MOUSE    move the cursor
    thumb+index pinch      → CLICK / DRAG left click, or drag while held

While DISARMED only the clutch is active, so stray hand motion does nothing.

Run `gesture.py --help` for options, `--self-test` to exercise the classifier
without a camera, and `--dry-run` to print recognised gestures without acting.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from collections import deque

# ── Vision hand-pose joint names (VNHumanHandPoseObservationJointName) ─────────
WRIST = "VNHLKWRI"
# finger letter → (mcp, pip, dip, tip)   [thumb uses cmc, mp, ip, tip]
FINGERS = {
    "thumb":  ("VNHLKTCMC", "VNHLKTMP", "VNHLKTIP",  "VNHLKTTIP"),
    "index":  ("VNHLKIMCP", "VNHLKIPIP", "VNHLKIDIP", "VNHLKITIP"),
    "middle": ("VNHLKMMCP", "VNHLKMPIP", "VNHLKMDIP", "VNHLKMTIP"),
    "ring":   ("VNHLKRMCP", "VNHLKRPIP", "VNHLKRDIP", "VNHLKRTIP"),
    "pinky":  ("VNHLKPMCP", "VNHLKPPIP", "VNHLKPDIP", "VNHLKPTIP"),
}


# ── Geometry helpers ──────────────────────────────────────────────────────────
def _pt(joints, name):
    j = joints.get(name)
    if not j:
        return None
    return (j["x"], j["y"])


def _dist(a, b):
    if a is None or b is None:
        return None
    return math.hypot(a[0] - b[0], a[1] - b[1])


def hand_features(hand):
    """Reduce a raw hand observation to pose-relevant features (image space).

    Returns None if the hand is too occluded to read reliably.
    """
    joints = hand.get("joints", {})
    wrist = _pt(joints, WRIST)
    mid_mcp = _pt(joints, FINGERS["middle"][0])
    if wrist is None or mid_mcp is None:
        return None

    palm = _dist(wrist, mid_mcp) or 1e-6  # scale reference

    extended = {}
    for name, (mcp, pip, dip, tip) in FINGERS.items():
        wp, mcpp, tipp = wrist, _pt(joints, mcp), _pt(joints, tip)
        if name == "thumb":
            # The thumb is lateral: "out" when its tip is far from the index MCP.
            idx_mcp = _pt(joints, FINGERS["index"][0])
            d = _dist(tipp, idx_mcp)
            extended[name] = d is not None and d > 0.7 * palm
        else:
            dw_tip = _dist(tipp, wp)
            dw_mcp = _dist(mcpp, wp)
            # Extended when the tip reaches farther from the wrist than the knuckle.
            extended[name] = (dw_tip is not None and dw_mcp is not None
                              and dw_tip > dw_mcp * 1.05)

    n_ext = sum(1 for f in ("index", "middle", "ring", "pinky") if extended[f])

    thumb_tip = _pt(joints, FINGERS["thumb"][3])
    index_tip = _pt(joints, FINGERS["index"][3])
    pinch_dist = _dist(thumb_tip, index_tip)
    pinch_norm = pinch_dist / palm if pinch_dist is not None else 99.0
    # How far the index tip reaches from the wrist (palm-relative). A curled
    # index (fist) stays low; a pinch reaches out to meet the thumb.
    index_dw = (_dist(wrist, index_tip) or 0.0) / palm

    # Hand anchor: mean of wrist + all knuckles (stable under finger motion).
    anchors = [wrist] + [_pt(joints, FINGERS[f][0]) for f in FINGERS]
    anchors = [a for a in anchors if a is not None]
    cx = sum(a[0] for a in anchors) / len(anchors)
    cy = sum(a[1] for a in anchors) / len(anchors)

    return {
        "chirality": hand.get("chirality", "unknown"),
        "confidence": hand.get("confidence", 0.0),
        "extended": extended,
        "n_ext": n_ext,
        "pinch_norm": pinch_norm,
        "index_dw": index_dw,
        "index_tip": index_tip,
        "centroid": (cx, cy),
        "palm": palm,
    }


def classify_pose(f):
    """Map hand features to a discrete pose."""
    if f is None:
        return "none"
    # Pinch takes priority — thumb and index tips nearly touching AND the index
    # reaching out to meet the thumb (so a closed fist isn't read as a pinch).
    if f["pinch_norm"] < 0.35 and f["index_dw"] > 1.0:
        return "pinch"
    if f["n_ext"] >= 4:
        return "open"
    if f["n_ext"] == 0 and not f["extended"]["thumb"]:
        return "fist"
    if f["extended"]["index"] and f["n_ext"] == 1:
        return "point"
    return "other"


# ── Gesture engine ────────────────────────────────────────────────────────────
class GestureEngine:
    """Stateful temporal classifier. Feed it frames; it yields action events.

    An event is a dict: {"type": ..., ...}. Action-producing types:
      clutch (state), throw (direction), swipe (direction),
      pointer (x,y normalized), click, drag-start, drag-move, drag-end.
    """

    def __init__(self, cfg):
        self.cfg = cfg
        self.armed = False
        self.hist = {"left": deque(maxlen=64), "right": deque(maxlen=64),
                     "unknown": deque(maxlen=64)}
        # grab/throw + pinch/drag are tracked on the primary hand
        self.grab = None          # {"origin": (x,y), "t": t}
        self.pinch = None         # {"start": (x,y), "t": t, "dragging": bool}
        self.swipe_cooldown = 0.0
        self.clutch_hold_start = None
        self.clutch_toggled = False

    # -- helpers ----------------------------------------------------------------
    def _primary(self, feats):
        """Pick the controlling hand (highest confidence)."""
        present = [f for f in feats if f is not None]
        if not present:
            return None
        return max(present, key=lambda f: f["confidence"])

    def _direction(self, dx_img, dy_img):
        # Mirror so physical-right reads as "right" on a front camera.
        dx = -dx_img if self.cfg.mirror else dx_img
        if abs(dx) >= abs(dy_img):
            return "right" if dx > 0 else "left"
        return "up" if dy_img < 0 else "down"   # image y grows downward

    def _map_pointer(self, tip):
        """Map a normalized (x,y) index tip to global screen pixels."""
        d = self.cfg.pointer_rect  # (x, y, w, h)
        ix = 1.0 - tip[0] if self.cfg.mirror else tip[0]
        return (d[0] + ix * d[2], d[1] + tip[1] * d[3])

    # -- main entry -------------------------------------------------------------
    def process(self, hands, t):
        events = []
        feats = [hand_features(h) for h in hands]
        feats = [f for f in feats if f is not None]
        poses = [classify_pose(f) for f in feats]

        # Record history per chirality for velocity tracking (with pose, so a
        # swipe only counts frames where the hand was actually open).
        for f, p in zip(feats, poses):
            self.hist[f["chirality"]].append((t, f["centroid"], p))

        # ── Clutch: two open palms held together toggles armed state ──────────
        two_open = len(feats) >= 2 and all(p == "open" for p in poses[:2])
        if two_open:
            if self.clutch_hold_start is None:
                self.clutch_hold_start = t
            elif (not self.clutch_toggled
                  and t - self.clutch_hold_start >= self.cfg.clutch_hold):
                self.armed = not self.armed
                self.clutch_toggled = True
                self._reset_modes()
                events.append({"type": "clutch",
                               "state": "armed" if self.armed else "disarmed"})
            return events  # while clutching, suppress other gestures
        else:
            self.clutch_hold_start = None
            self.clutch_toggled = False

        if not self.armed:
            return events

        primary = self._primary(feats)
        if primary is None:
            self._reset_modes()
            return events
        pose = classify_pose(primary)

        # ── Grab & throw (fist → fling → release) ─────────────────────────────
        if pose == "fist":
            if self.grab is None:
                self.grab = {"origin": primary["centroid"], "t": t}
            self._cancel_pinch(events)
        else:
            if self.grab is not None:
                ox, oy = self.grab["origin"]
                cx, cy = primary["centroid"]
                disp = math.hypot(cx - ox, cy - oy)
                if disp >= self.cfg.throw_dist:
                    direction = self._direction(cx - ox, cy - oy)
                    events.append({"type": "throw", "direction": direction,
                                   "disp": round(disp, 3)})
                    # The release opens the hand; clear history + cool down so the
                    # fling isn't also read as an open-palm swipe.
                    self.hist[primary["chirality"]].clear()
                    self.swipe_cooldown = t + self.cfg.swipe_cooldown
                self.grab = None

        # ── Open-palm swipe → Spaces ──────────────────────────────────────────
        if pose == "open" and t >= self.swipe_cooldown:
            sw = self._detect_swipe(primary["chirality"], t)
            if sw is not None:
                events.append({"type": "swipe", "direction": sw})
                self.swipe_cooldown = t + self.cfg.swipe_cooldown

        # ── Air-mouse (index point) → move cursor ─────────────────────────────
        if pose == "point" and primary["index_tip"] is not None:
            x, y = self._map_pointer(primary["index_tip"])
            events.append({"type": "pointer", "x": round(x), "y": round(y)})

        # ── Pinch → click / drag ──────────────────────────────────────────────
        if pose == "pinch" and primary["index_tip"] is not None:
            sx, sy = self._map_pointer(primary["index_tip"])
            if self.pinch is None:
                self.pinch = {"start": (sx, sy), "t": t, "dragging": False}
            else:
                msx, msy = self.pinch["start"]
                moved = math.hypot(sx - msx, sy - msy)
                if moved >= self.cfg.drag_thresh:
                    if not self.pinch["dragging"]:
                        self.pinch["dragging"] = True
                        events.append({"type": "drag-start", "x": round(msx), "y": round(msy)})
                    events.append({"type": "drag-move", "x": round(sx), "y": round(sy)})
        else:
            self._cancel_pinch(events)

        return events

    def _cancel_pinch(self, events):
        if self.pinch is not None:
            if self.pinch["dragging"]:
                x, y = self.pinch["start"]
                events.append({"type": "drag-end"})
            else:
                # Quick pinch with little movement → a click.
                x, y = self.pinch["start"]
                events.append({"type": "click", "x": round(x), "y": round(y)})
            self.pinch = None

    def _reset_modes(self):
        self.grab = None
        self.pinch = None

    def _detect_swipe(self, chirality, t):
        """Net horizontal/vertical motion of an open palm within the window."""
        h = self.hist[chirality]
        window = [(ts, c) for (ts, c, p) in h
                  if t - ts <= self.cfg.swipe_time and p == "open"]
        if len(window) < 3:
            return None
        (t0, c0), (t1, c1) = window[0], window[-1]
        dx, dy = c1[0] - c0[0], c1[1] - c0[1]
        if math.hypot(dx, dy) < self.cfg.swipe_dist:
            return None
        return self._direction(dx, dy)


# ── Action dispatch ───────────────────────────────────────────────────────────
class Dispatcher:
    """Turn gesture events into window/input subcommand invocations."""

    # Spaces / Mission Control via the default macOS keyboard shortcuts.
    SWIPE_KEYS = {
        "left":  ("left",  "ctrl"),   # previous desktop
        "right": ("right", "ctrl"),   # next desktop
        "up":    ("up",    "ctrl"),   # Mission Control
        "down":  ("down",  "ctrl"),   # App Exposé
    }

    def __init__(self, binary, dry_run=False, verbose=False):
        self.binary = binary
        self.dry_run = dry_run
        self.verbose = verbose
        self._last_pointer = 0.0

    def _run(self, args):
        if self.dry_run:
            print("    →", " ".join(args))
            return
        try:
            subprocess.Popen([self.binary] + args,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:  # noqa: BLE001
            print(f"    ! action failed: {e}", file=sys.stderr)

    def handle(self, ev):
        kind = ev["type"]
        if kind == "clutch":
            print(f"[{ev['state'].upper()}]")
            return
        print(f"  gesture: {kind} {ev.get('direction', '')}".rstrip())

        if kind == "throw":
            d = ev["direction"]
            if d in ("left", "right"):
                self._run(["window", "move-to-display", "--display", d])
            elif d == "up":
                self._run(["window", "maximize"])
            elif d == "down":
                self._run(["window", "minimize"])
        elif kind == "swipe":
            key, mod = self.SWIPE_KEYS[ev["direction"]]
            self._run(["input", "key", "--key", key, "--modifiers", mod])
        elif kind == "pointer":
            now = time.monotonic()
            if now - self._last_pointer < 0.04:  # throttle to ~25 Hz
                return
            self._last_pointer = now
            self._run(["input", "mouse-move", "--x", str(ev["x"]), "--y", str(ev["y"])])
        elif kind == "click":
            self._run(["input", "mouse-move", "--x", str(ev["x"]), "--y", str(ev["y"])])
            self._run(["input", "click", "--button", "left"])
        elif kind == "drag-start":
            self._run(["input", "mouse-move", "--x", str(ev["x"]), "--y", str(ev["y"])])
            self._run(["input", "mouse-down", "--button", "left"])
        elif kind == "drag-move":
            self._run(["input", "mouse-move", "--x", str(ev["x"]), "--y", str(ev["y"]),
                       "--drag", "left"])
        elif kind == "drag-end":
            self._run(["input", "mouse-up", "--button", "left"])


# ── MJPEG stream parsing ──────────────────────────────────────────────────────
def iter_handpose(stream):
    """Yield the parsed X-MV-face-hand-pose JSON for each MJPEG frame on `stream`.

    Frames are `--mvboundary` delimited with CRLF headers and a Content-Length
    JPEG body (which we skip).
    """
    buf = b""
    boundary = b"--mvboundary\r\n"
    sep = b"\r\n\r\n"
    while True:
        # Find a boundary.
        bi = buf.find(boundary)
        if bi == -1:
            if buf.find(b"--mvboundary--") != -1:
                return
            chunk = stream.read(65536)
            if not chunk:
                return
            buf += chunk
            continue
        # Find end of headers.
        hs = bi + len(boundary)
        si = buf.find(sep, hs)
        if si == -1:
            chunk = stream.read(65536)
            if not chunk:
                return
            buf += chunk
            continue
        header_blob = buf[hs:si].decode("utf-8", "replace")
        headers = {}
        for line in header_blob.split("\r\n"):
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip()] = v.strip()
        clen = int(headers.get("Content-Length", "-1"))
        if clen < 0:
            buf = buf[si + len(sep):]
            continue
        jpeg_start = si + len(sep)
        jpeg_end = jpeg_start + clen
        while len(buf) < jpeg_end:
            chunk = stream.read(65536)
            if not chunk:
                return
            buf += chunk
        # We only need the hand-pose header; the JPEG body is discarded.
        hp = headers.get("X-MV-face-hand-pose")
        if hp:
            try:
                yield json.loads(hp)
            except json.JSONDecodeError:
                pass
        buf = buf[jpeg_end:]


# ── Binary + display resolution ───────────────────────────────────────────────
def resolve_binary(explicit):
    if explicit:
        return explicit
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    for variant in ("debug", "release"):
        cand = os.path.join(root, ".build", variant, "macos-vision")
        if os.path.exists(cand):
            return cand
    found = shutil.which("macos-vision")
    if found:
        return found
    sys.exit("error: could not find macos-vision binary; pass --binary <path>")


def pointer_rect(binary, index):
    """Return (x, y, w, h) of the chosen display in global pixels."""
    try:
        out = subprocess.check_output([binary, "window", "list-displays"],
                                      stderr=subprocess.DEVNULL)
        displays = json.loads(out)["displays"]
        d = next((x for x in displays if x["index"] == index), displays[0])
        f = d["frame"]
        return (f["x"], f["y"], f["w"], f["h"])
    except Exception:  # noqa: BLE001
        return (0, 0, 1920, 1080)


# ── CLI ───────────────────────────────────────────────────────────────────────
def build_config(args, binary):
    class C:
        pass
    c = C()
    c.mirror = not args.no_mirror
    c.throw_dist = args.throw_dist
    c.swipe_dist = args.swipe_dist
    c.swipe_time = args.swipe_time
    c.swipe_cooldown = args.swipe_cooldown
    c.clutch_hold = args.clutch_hold
    c.drag_thresh = args.drag_thresh
    c.pointer_rect = pointer_rect(binary, args.pointer_display)
    return c


def drive(stream, engine, disp, time_fn):
    """Read hand-pose frames from an MJPEG `stream` and dispatch gestures.

    `time_fn(index)` supplies the timestamp for each frame: wall-clock for the
    live camera, or a virtual fps-based clock when replaying a recording.
    """
    try:
        for i, result in enumerate(iter_handpose(stream)):
            hands = result.get("hands", [])
            for ev in engine.process(hands, time_fn(i)):
                disp.handle(ev)
    except KeyboardInterrupt:
        pass


def run_source(args, binary):
    """Replay a recorded hand-pose MJPEG stream (file or '-' for stdin).

    Record one with:
        macos-vision streamcapture video --fps 15 --no-audio \\
            | macos-vision face --operation hand-pose > session.mjpeg
    """
    cfg = build_config(args, binary)
    engine = GestureEngine(cfg)
    disp = Dispatcher(binary, dry_run=args.dry_run, verbose=args.debug)
    fps = max(1, args.fps)
    virtual_clock = lambda i: i / fps  # noqa: E731
    print(f"replaying: {args.source}  fps={fps}  mirror={cfg.mirror}  dry-run={args.dry_run}")
    if args.source == "-":
        drive(sys.stdin.buffer, engine, disp, virtual_clock)
    else:
        with open(args.source, "rb") as fh:
            drive(fh, engine, disp, virtual_clock)
    return 0


def run_live(args, binary):
    cfg = build_config(args, binary)
    engine = GestureEngine(cfg)
    disp = Dispatcher(binary, dry_run=args.dry_run, verbose=args.debug)

    cap = [binary, "streamcapture", "video", "--fps", str(args.fps),
           "--device-index", str(args.device), "--no-audio"]
    face = [binary, "face", "--operation", "hand-pose"]

    print(f"binary: {binary}")
    print(f"pipeline: {' '.join(cap)} | {' '.join(face)}")
    print(f"pointer display rect: {cfg.pointer_rect}  mirror={cfg.mirror}")
    print("Show two open palms (~1s) to ARM. Ctrl+C to quit.\n")

    p_cap = subprocess.Popen(cap, stdout=subprocess.PIPE)
    p_face = subprocess.Popen(face, stdin=p_cap.stdout, stdout=subprocess.PIPE)
    p_cap.stdout.close()  # allow p_cap to receive SIGPIPE if p_face exits

    try:
        drive(p_face.stdout, engine, disp, lambda i: time.monotonic())
    finally:
        for p in (p_face, p_cap):
            try:
                p.terminate()
            except Exception:  # noqa: BLE001
                pass
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="Live hand-gesture control for macOS.")
    ap.add_argument("--binary", help="path to macos-vision (auto-detected by default)")
    ap.add_argument("--source", help="replay a recorded hand-pose MJPEG stream "
                    "(file path, or '-' for stdin) instead of the live camera")
    ap.add_argument("--fps", type=int, default=15, help="camera frame rate (default 15)")
    ap.add_argument("--device", type=int, default=0, help="camera device index")
    ap.add_argument("--pointer-display", type=int, default=0,
                    help="display index the air-mouse maps onto (default 0)")
    ap.add_argument("--no-mirror", action="store_true",
                    help="do not mirror horizontal direction (raw camera space)")
    ap.add_argument("--dry-run", action="store_true",
                    help="print recognised gestures and the commands they would run")
    ap.add_argument("--debug", action="store_true", help="verbose output")
    ap.add_argument("--self-test", action="store_true",
                    help="run the classifier on synthetic frames and exit")
    # Tunables (normalized image units, seconds).
    ap.add_argument("--throw-dist", type=float, default=0.18)
    ap.add_argument("--swipe-dist", type=float, default=0.22)
    ap.add_argument("--swipe-time", type=float, default=0.5)
    ap.add_argument("--swipe-cooldown", type=float, default=0.7)
    ap.add_argument("--clutch-hold", type=float, default=0.8)
    ap.add_argument("--drag-thresh", type=float, default=8.0)
    args = ap.parse_args(argv)

    if args.self_test:
        from selftest import run_self_test  # noqa: E402
        return run_self_test()

    binary = resolve_binary(args.binary)
    if args.source:
        return run_source(args, binary)
    return run_live(args, binary)


if __name__ == "__main__":
    sys.exit(main())
