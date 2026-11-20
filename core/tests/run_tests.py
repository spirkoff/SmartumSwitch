#!/usr/bin/env python3
"""Runs core/tests/cases.json against the Python reference core and (if present) the Linux daemon's Judge."""
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "..", "python"))
from smartum_core import Judge, retype, OTHER
cases = json.load(open(os.path.join(here, "cases.json"), encoding="utf-8"))
def run(name, judge):
    bad = 0
    for c in cases:
        L = c["layout"]; other = retype(c["shown"], L)
        fix, why = judge.should_fix(c["shown"], other, L, OTHER[L])
        if fix != c["fix"] or (fix and other != c["result"]):
            bad += 1; print(f"  FAIL [{name}] {c['shown']!r} ({L}) expected fix={c['fix']} got {fix} ({why})")
    print(f"{name}: {len(cases) - bad}/{len(cases)} passed")
    return bad
bad = run("python-core", Judge())
linux = os.path.join(here, "..", "..", "linux", "smartum-switch")
if os.path.exists(linux):
    import types  # the daemon imports evdev at top level; the Judge does not need it
    if "evdev" not in sys.modules:
        ev = types.ModuleType("evdev"); ev.InputDevice = ev.UInput = ev.list_devices = None
        ev.ecodes = types.SimpleNamespace(**{f"KEY_{k}": i for i, k in enumerate(
            "RESERVED ESC 1 2 3 4 5 6 7 8 9 0 MINUS EQUAL BACKSPACE TAB Q W E R T Y U I O P LEFTBRACE RIGHTBRACE ENTER LEFTCTRL A S D F G H J K L SEMICOLON APOSTROPHE GRAVE LEFTSHIFT BACKSLASH Z X C V B N M COMMA DOT SLASH RIGHTSHIFT KPASTERISK LEFTALT SPACE CAPSLOCK".split())})
        class _E(types.SimpleNamespace):
            def __getattr__(self, k): return 1000 + abs(hash(k)) % 1000
        ev.ecodes = _E(**vars(ev.ecodes)); sys.modules["evdev"] = ev
    src = open(linux, encoding="utf-8").read().split("# ---------- окружение")[0]
    ns = {"__name__": "smartum_linux"}; exec(src, ns)
    bad += run("linux-daemon", ns["Judge"]())
sys.exit(1 if bad else 0)
