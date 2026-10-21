#!/usr/bin/env bash
# Records the data behind the site's two replays of a real Marionette run:
#
#   THE LOOP (landing hero)  web/images/loop/NN.webp  demo/loop.json
#   X-RAY (docs, Concepts)   web/images/xray/screen.webp  demo/xray.json
#
# It boots an Android emulator, runs the repo's example app with
# `flutter run --debug`, and drives it through the real MCP server
# (packages/marionette_mcp) with a minimal stdio MCP client, so one `connect`
# opens one session and the server writes one steps.md for the whole run (the
# CLI would open a session per command). Phone frames come from
# `adb exec-out screencap` after each beat that changes the screen, so they
# include the system bars and never show up in steps.md.
#
# Re-run it after a release that changes tool names, results or the example
# app, so the site never replays a tool that no longer exists.
#
# What stays manual: the scenario, the observations ("what the agent read
# from this result") and report.md are written for THIS scenario in the
# builder below. If you change the calls, rewrite them, following "The
# report contract" in
# packages/marionette_flutter/skills/marionette-flutter-drive-app/SKILL.md.
# The builder asserts that every call succeeded and that steps.md has one
# line per call, so a broken run fails instead of publishing.
#
# Needs: fvm (the repo's Flutter, see .fvmrc), the Android SDK (emulator,
# adb), an AVD, python3, and ImageMagick 7 (`magick`) with WebP support.
#
# Usage, from website/:
#   bash tool/record_demo.sh            # AVD Medium_Phone_API_36.1
#   AVD=Pixel_9 bash tool/record_demo.sh
set -euo pipefail

AVD="${AVD:-Medium_Phone_API_36.1}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
WEBSITE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$WEBSITE/.." && pwd)"
WORK="$(mktemp -d)"
FLUTTER_PID=""
EMULATOR_PID=""

cleanup() {
  [ -n "$FLUTTER_PID" ] && pkill -P "$FLUTTER_PID" 2>/dev/null || true
  [ -n "$FLUTTER_PID" ] && kill "$FLUTTER_PID" 2>/dev/null || true
  pkill -f "flutter_tools.snapshot run -d $DEVICE" 2>/dev/null || true
  if [ -n "$EMULATOR_PID" ]; then
    adb -s "$DEVICE" emu kill >/dev/null 2>&1 || kill "$EMULATOR_PID" 2>/dev/null || true
  fi
  echo "Scratch files kept in $WORK"
}
DEVICE=""
trap cleanup EXIT

# 1. A booted emulator: reuse a running one, or boot $AVD.
DEVICE="$(adb devices | awk '/^emulator-[0-9]+\tdevice$/ {print $1; exit}')"
if [ -z "$DEVICE" ]; then
  echo "Booting $AVD…"
  "$SDK/emulator/emulator" -avd "$AVD" -no-snapshot-save -no-boot-anim \
    >"$WORK/emulator.log" 2>&1 &
  EMULATOR_PID=$!
  adb wait-for-device
  DEVICE="$(adb devices | awk '/^emulator-[0-9]+\t/ {print $1; exit}')"
fi
until [ "$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
  sleep 2
done
export ANDROID_SERIAL="$DEVICE"
read -r PHYS_W PHYS_H < <(adb shell wm size | sed -E 's/.*: ([0-9]+)x([0-9]+).*/\1 \2/' | tail -1)
DENSITY="$(adb shell wm density | sed -E 's/.*: ([0-9]+).*/\1/' | tail -1)"
export PHYS_W PHYS_H DENSITY
export DEVICE_NAME="Android emulator · ${AVD//_/ }"
echo "Device $DEVICE: ${PHYS_W}x${PHYS_H} @ $DENSITY dpi"

# 2. The example app in debug mode; its VM service URI comes from the log.
(cd "$REPO/example" && tail -f /dev/null | fvm flutter run -d "$DEVICE" --debug \
  >"$WORK/flutter_run.log" 2>&1) &
FLUTTER_PID=$!
echo "Waiting for the app…"
until grep -q "A Dart VM Service on .* is available at" "$WORK/flutter_run.log"; do
  if ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
    tail -30 "$WORK/flutter_run.log"
    exit 1
  fi
  sleep 3
done
HTTP_URI="$(grep -oE 'A Dart VM Service on .* is available at: http://[^ ]+' "$WORK/flutter_run.log" | head -1 | grep -oE 'http://[^ ]+')"
URI="ws://${HTTP_URI#http://}"
URI="${URI%/}/ws"
echo "VM service: $URI"
sleep 5 # let the first frames settle

# 3. The two scripted sessions, from a fresh app state.
cat >"$WORK/mcp_client.py" <<'PY'
"""Minimal MCP stdio client: runs a JSON list of tool calls against marionette_mcp.

usage: mcp_client.py <repo_root> <calls.json> <out.json> [session_dir]
Each call: {"name": "...", "arguments": {...}, "pause": seconds_before}
Writes every raw result (content blocks; images saved as PNG next to out.json).
"""
import base64, json, os, subprocess, sys, time

repo, calls_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
session_dir = sys.argv[4] if len(sys.argv) > 4 else None
env = dict(os.environ)
if session_dir:
    env["MARIONETTE_SESSION_DIR"] = session_dir
proc = subprocess.Popen(
    ["fvm", "dart", "run", "packages/marionette_mcp/bin/marionette_mcp.dart"],
    cwd=repo, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open(out_path + ".stderr", "w"),
    env=env, text=True, bufsize=1,
)
next_id = [0]

def send(method, params=None, notify=False):
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        msg["params"] = params
    if not notify:
        next_id[0] += 1
        msg["id"] = next_id[0]
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    if notify:
        return None
    while True:
        line = proc.stdout.readline()
        if not line:
            raise SystemExit("server closed stdout")
        try:
            resp = json.loads(line)
        except json.JSONDecodeError:
            continue
        if resp.get("id") == msg["id"]:
            return resp

send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "demo-recorder", "version": "1"}})
send("notifications/initialized", notify=True)
tools = send("tools/list", {})
calls = json.load(open(calls_path))
results = []
img_dir = os.path.dirname(os.path.abspath(out_path))
for i, call in enumerate(calls):
    time.sleep(call.get("pause", 0.8))
    t0 = time.time()
    resp = send("tools/call", {"name": call["name"], "arguments": call.get("arguments", {})})
    dt = time.time() - t0
    blocks = []
    for j, block in enumerate(resp.get("result", {}).get("content", [])):
        if block.get("type") == "image":
            p = os.path.join(img_dir, f"call{i:02d}_img{j}.png")
            open(p, "wb").write(base64.b64decode(block["data"]))
            blocks.append({"type": "image", "path": p})
        else:
            blocks.append(block)
    if call.get("frame"):
        time.sleep(call.get("frame_delay", 0.9))
        frame_path = os.path.join(img_dir, f"frame_{call['frame']}.png")
        with open(frame_path, "wb") as fh:
            subprocess.run(["adb", "exec-out", "screencap", "-p"], stdout=fh, check=True)
    results.append({"call": call, "isError": resp.get("result", {}).get("isError"), "error": resp.get("error"), "content": blocks, "seconds": round(dt, 2)})
    print(f"[{i}] {call['name']} {json.dumps(call.get('arguments', {}))[:80]} -> {(blocks[0].get('text', '') if blocks else '')[:160]!r}", flush=True)
json.dump({"tools": [t["name"] for t in tools.get("result", {}).get("tools", [])], "results": results}, open(out_path, "w"), indent=2)
proc.stdin.close()
proc.wait(timeout=20)
PY

cat >"$WORK/build_json.py" <<'PY'
"""Builds website/demo/loop.json and xray.json from the recorded runs.

usage: build_json.py <scratch> <website_dir>
"""
import datetime, glob, json, os, re, sys

# Device facts, passed in by record_demo.sh (defaults: the AVD it was first recorded on).
DEVICE_NAME = os.environ.get("DEVICE_NAME", "Android emulator · Medium Phone API 36.1")
PHYS_W = int(os.environ.get("PHYS_W", "1080"))
PHYS_H = int(os.environ.get("PHYS_H", "2400"))
RATIO = int(os.environ.get("DENSITY", "420")) / 160
IMG_W = int(os.environ.get("IMG_W", "900"))
IMG_H = int(os.environ.get("IMG_H", "2000"))

scratch, website = sys.argv[1], sys.argv[2]
loop = json.load(open(f"{scratch}/loop/out.json"))
session = glob.glob(f"{scratch}/loop_sessions/.marionette/sessions/*/")[0].rstrip("/")
session_rel = ".marionette/sessions/" + os.path.basename(session)
steps = [l.rstrip("\n") for l in open(f"{session}/steps.md") if l.startswith("- [")]
results = loop["results"]
assert len(steps) == len(results), (len(steps), len(results))

def first_line(r):
    return r["content"][0]["text"].splitlines()[0] if r["content"] and r["content"][0].get("type") == "text" else ""

def listing_line(r, *needles):
    """The listing's header plus a terse pick of the lines an agent acts on."""
    text = r["content"][0]["text"]
    picked = []
    for l in text.splitlines():
        if not any(n in l for n in needles):
            continue
        key = re.search(r'Key: "([^"]*)"', l)
        enabled = re.search(r'enabled: "([^"]*)"', l)
        label = re.search(r'Text: "([^"]*)"', l)
        type_ = l[len("Type: "):].split(",")[0]
        if key:
            picked.append(key.group(1))
        elif enabled:
            picked.append(f'{type_} enabled: "{enabled.group(1)}"')
        elif label:
            picked.append(f'Text "{label.group(1)}"')
    return text.splitlines()[0].rstrip(":") + " · " + ", ".join(picked)

uri_display = re.sub(r"(ws://[^/]+)/.*", r"\1/…/ws", results[0]["call"]["arguments"]["uri"])
beats_spec = [
    # (tool, call, phase, result override or None, frame, observation)
    ("connect", f'connect(uri: "{uri_display}", session_title: "profile email validation")', "connect",
     f"Successfully connected to app · Opened session: {session_rel}", "00.webp", None),
    ("hot_reload", "hot_reload()", "iterate", None, None, None),
    ("tap", 'tap(text: "Profile")', "act", None, "01.webp", None),
    ("get_interactive_elements", "get_interactive_elements()", "see",
     listing_line(results[3], 'Key: "name_field"', 'Key: "email_field"', 'Key: "bio_field"', "FilledButton"), None,
     "Three fields; the FilledButton (Submit) is disabled."),
    ("enter_text", 'enter_text(key: "name_field", input: "Ada Lovelace")', "act", None, "02.webp", None),
    ("enter_text", 'enter_text(key: "email_field", input: "ada@example")', "act", None, "03.webp", None),
    ("take_screenshots", "take_screenshots()", "see", "1 screenshot, returned inline", None,
     "The email field shows “Enter a valid email”."),
    ("get_interactive_elements", "get_interactive_elements()", "verify",
     listing_line(results[7], "FilledButton"), None, "Submit stays disabled."),
    ("enter_text", 'enter_text(key: "email_field", input: "ada@example.com")', "act", None, "04.webp", None),
    ("enter_text", 'enter_text(key: "bio_field", input: "Writes programs")', "act", None, "05.webp", None),
    ("tap", 'tap(text: "Submit")', "act", None, "06.webp", None),
    ("get_interactive_elements", "get_interactive_elements()", "verify",
     listing_line(results[11], "FilledButton", "Form submitted"), None,
     "Submit is enabled and the “Form submitted” snackbar is on screen."),
    ("take_screenshots", "take_screenshots(inline: false)", "verify", "Saved 1 screenshot(s): screenshots/01.png", None, None),
    ("get_logs", "get_logs()", "verify", None, None, "Nothing logged, so no errors."),
    ("disconnect", "disconnect()", "report",
     f"Successfully disconnected from app · Session: {session_rel} · Write report.md now.", None, None),
]
assert len(beats_spec) == len(results)
beats = []
for i, ((tool, call, phase, result, frame, obs), r, step) in enumerate(zip(beats_spec, results, steps)):
    assert r["call"]["name"] == tool, (i, tool, r["call"]["name"])
    assert not r["isError"], (i, r)
    beat = {"tool": tool, "call": call, "phase": phase,
            "result": result or first_line(r), "step": step, "frame": frame}
    if obs:
        beat["observation"] = obs
    beats.append(beat)

prompt = ("Hot reload the app, then check the Profile form: a malformed email must show an error "
          "and keep Submit disabled, and a valid one must submit. Write a report.")
n_steps = len(steps)
shots = len(glob.glob(f"{session}/screenshots/*.png"))
report = f"""✅ Marionette report — no issues · Profile email validation
Tested: hot reload, Profile form — name, malformed email, valid email, bio, submit ({n_steps} steps, {shots} screenshot)
Checks: "ada@example" shows "Enter a valid email" and Submit stays disabled (steps 6–8); a valid email and a bio enable Submit, and submitting shows "Form submitted" (steps 9–12, screenshots/01.png); get_logs collected nothing, so no errors were logged (step 14)
"""
verdict = (f"Marionette · Profile email validation — PASS: validation and submit work\n"
           f"✓ malformed email rejected, Submit disabled until the form is valid, form submits\n"
           f"→ {session_rel}/report.md · {n_steps} steps, {shots} screenshot")
open(f"{session}/report.md", "w").write(report)

loop_json = {
    "device": {"name": DEVICE_NAME,
               "physicalWidth": PHYS_W, "physicalHeight": PHYS_H,
               "logicalWidth": round(PHYS_W / RATIO, 2), "logicalHeight": round(PHYS_H / RATIO, 2), "pixelRatio": RATIO,
               "frameWidth": 360, "frameHeight": 800, "frameSource": "adb exec-out screencap (includes system bars)"},
    "app": "example/ (marionette_mcp repo), flutter run --debug",
    "recordedAt": datetime.date.today().isoformat(),
    "prompt": prompt,
    "sessionDir": session_rel,
    "beats": beats,
    "stepsMd": "\n".join(steps) + "\n",
    "report": report,
    "verdict": verdict,
}
json.dump(loop_json, open(f"{website}/demo/loop.json", "w"), indent=2, ensure_ascii=False)
open(f"{website}/demo/loop.json", "a").write("\n")

# X-RAY
xr = json.load(open(f"{scratch}/xray/out.json"))["results"]
compact_text = xr[3]["content"][0]["text"]
none_text = xr[4]["content"][0]["text"]
bounds_re = re.compile(r', bounds: (\{[^}]*\})$')
pair_re = re.compile(r'(\w+): "(.*?)"(?=, \w+: |, bounds: |$)')

def parse(text):
    lines = text.split("\n")
    header, body = lines[0], [l for l in lines[2:] if l]
    # A Text value may contain a newline; glue continuation lines back on.
    merged = []
    for l in body:
        if l.startswith("Type: ") or not merged:
            merged.append(l)
        else:
            merged[-1] += "\n" + l
    elements = []
    for raw in merged:
        m = bounds_re.search(raw)
        b = json.loads(m.group(1)) if m else None
        head = raw[: m.start()] if m else raw
        type_ = head[len("Type: "):].split(", ")[0]
        props = {k: v for k, v in pair_re.findall(head[len("Type: ") + len(type_):].lstrip(", "))}
        el = {"type": type_}
        if "Key" in props: el["key"] = props.pop("Key")
        if "Text" in props: el["text"] = props.pop("Text")
        if props: el["properties"] = props
        el["bounds"] = b
        el["raw"] = raw
        elements.append(el)
    count = int(re.search(r"Found (\d+)", header).group(1))
    assert count == len(elements), (count, len(elements))
    return {"header": header, "count": count, "elements": elements}

xray_json = {
    "screen": "Custom Widgets (example app, /settings/custom-widgets)",
    "screenshot": "screen.webp",
    "logicalWidth": round(PHYS_W / RATIO, 2), "logicalHeight": round(PHYS_H / RATIO, 2),
    "imageWidth": IMG_W, "imageHeight": IMG_H, "imageScale": round(IMG_W / (PHYS_W / RATIO), 4),
    "note": "Bounds are logical pixels; multiply by imageScale for screenshot pixels. The screenshot is Flutter-rendered (take_screenshots), so it has no system status bar.",
    "compact": parse(compact_text),
    "none": parse(none_text),
    "compactRaw": compact_text,
    "noneRaw": none_text,
    "compactChars": len(compact_text),
    "noneChars": len(none_text),
}
json.dump(xray_json, open(f"{website}/demo/xray.json", "w"), indent=2, ensure_ascii=False)
open(f"{website}/demo/xray.json", "a").write("\n")
print("steps", n_steps, "shots", shots, "compact", len(compact_text), "none", len(none_text),
      "elements", xray_json["compact"]["count"], xray_json["none"]["count"])
PY

mkdir -p "$WORK/loop" "$WORK/loop_sessions" "$WORK/xray" "$WORK/xray_sessions"
cat >"$WORK/loop/calls.json" <<'JSON'
[
 {"name":"connect","arguments":{"uri":"__URI__","session_title":"profile email validation"}},
 {"name":"hot_reload","arguments":{},"pause":1.0},
 {"name":"tap","arguments":{"text":"Profile"},"frame":"01"},
 {"name":"get_interactive_elements","arguments":{}},
 {"name":"enter_text","arguments":{"key":"name_field","input":"Ada Lovelace"},"frame":"02"},
 {"name":"enter_text","arguments":{"key":"email_field","input":"ada@example"},"frame":"03"},
 {"name":"take_screenshots","arguments":{}},
 {"name":"get_interactive_elements","arguments":{}},
 {"name":"enter_text","arguments":{"key":"email_field","input":"ada@example.com"},"frame":"04"},
 {"name":"enter_text","arguments":{"key":"bio_field","input":"Writes programs"},"frame":"05"},
 {"name":"tap","arguments":{"text":"Submit"},"frame":"06","frame_delay":0.6},
 {"name":"get_interactive_elements","arguments":{},"pause":0.2},
 {"name":"take_screenshots","arguments":{"inline":false},"pause":0.2},
 {"name":"get_logs","arguments":{}},
 {"name":"disconnect","arguments":{}}
]
JSON
cat >"$WORK/xray/calls.json" <<'JSON'
[
 {"name":"connect","arguments":{"uri":"__URI__","session_title":"xray custom widgets"}},
 {"name":"call_custom_extension","arguments":{"extension":"appNavigation.goToPage","args":{"page":"custom_widgets"}},"pause":0.5},
 {"name":"take_screenshots","arguments":{},"pause":1.5},
 {"name":"get_interactive_elements","arguments":{"compaction":"compact"}},
 {"name":"get_interactive_elements","arguments":{"compaction":"none"}},
 {"name":"disconnect","arguments":{}}
]
JSON
sed -i "s#__URI__#$URI#" "$WORK/loop/calls.json" "$WORK/xray/calls.json"

(cd "$REPO" && fvm dart run packages/marionette_cli/bin/marionette.dart \
  --uri "$URI" --session-dir "$WORK/reset" hot-restart)
sleep 3
adb exec-out screencap -p >"$WORK/loop/frame_00.png"
python3 -I "$WORK/mcp_client.py" "$REPO" "$WORK/loop/calls.json" "$WORK/loop/out.json" "$WORK/loop_sessions"
python3 -I "$WORK/mcp_client.py" "$REPO" "$WORK/xray/calls.json" "$WORK/xray/out.json" "$WORK/xray_sessions"

# 4. Frames: 360 px wide for the phone pane; the X-RAY screenshot at full
#    size, since its bounds are scaled onto it.
mkdir -p "$WEBSITE/web/images/loop" "$WEBSITE/web/images/xray" "$WEBSITE/demo"
for frame in "$WORK"/loop/frame_*.png; do
  name="$(basename "$frame" .png)"
  magick "$frame" -resize 360x -quality 80 -define webp:method=6 \
    "$WEBSITE/web/images/loop/${name#frame_}.webp"
done
read -r IMG_W IMG_H < <(magick identify -format '%w %h\n' "$WORK/xray/call02_img0.png")
export IMG_W IMG_H
magick "$WORK/xray/call02_img0.png" -quality 80 -define webp:method=6 \
  "$WEBSITE/web/images/xray/screen.webp"

# 5. demo/loop.json and demo/xray.json (also writes report.md into the
#    session directory, as the agent would).
python3 -I "$WORK/build_json.py" "$WORK" "$WEBSITE"
echo "Done: demo/loop.json, demo/xray.json, web/images/loop/, web/images/xray/"
