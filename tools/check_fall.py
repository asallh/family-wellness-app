#!/usr/bin/env python3
"""Checks the fall detector's logic off the watch.

Mirrors FallDetector in source/FallDetector.mc and reads the recorded sample
straight from that file, so "Simulate fall" is known to trigger and everyday
movement is known not to.

    python3 tools/check_fall.py
"""
import re
import sys
from pathlib import Path

FREE_FALL_MG, IMPACT_MG = 400, 2500
IMPACT_WINDOW, SETTLE, STILL_SAMPLES, STILL_TOL_MG = 25, 8, 50, 200


class Detector:
    def __init__(self):
        self.state = self.count = 0

    def add(self, mg):
        if self.state == 0:
            if mg < FREE_FALL_MG:
                self.state, self.count = 1, 0
        elif self.state == 1:
            self.count += 1
            if mg > IMPACT_MG:
                self.state, self.count = 2, 0
            elif self.count > IMPACT_WINDOW:
                self.state = 3
        elif self.state == 3:
            if mg >= FREE_FALL_MG:
                self.state = self.count = 0
        else:
            self.count += 1
            if self.count > SETTLE and abs(mg - 1000) > STILL_TOL_MG:
                self.state = self.count = 0
            elif self.count >= SETTLE + STILL_SAMPLES:
                self.state = self.count = 0
                return True
        return False

    def run(self, samples):
        return [i for i, mg in enumerate(samples) if self.add(mg)]


def recorded_sample():
    src = (Path(__file__).resolve().parent.parent / "source" / "FallDetector.mc").read_text()
    out = []
    for name in ("WALK", "FALL"):
        body = re.search(rf"const {name} = \[(.*?)\];", src, re.S).group(1)
        out += [int(v) for v in re.findall(r"\d+", body)]
    return out


def main():
    sample = recorded_sample()
    walk = [1010, 1180, 1320, 1090, 870, 760, 940, 1150, 1290, 1120] * 30
    cases = [
        ("recorded fall triggers once", sample, 1),
        ("walking never triggers", walk, 0),
        ("standing still never triggers", [1000] * 500, 0),
        ("no accelerometer data (zeros) never triggers", [0] * 500, 0),
        ("hard tap with no free fall", [1000] * 20 + [3000] + [1000] * 100, 0),
        ("free fall, impact too late (>1 s)", [1000] * 5 + [200] * 30 + [3000] + [1000] * 80, 0),
        ("fall then gets up and walks", [1000] * 5 + [200] * 8 + [3000] + [1000] * 20 + walk, 0),
        ("two falls trigger twice", sample + [1000] * 10 + sample, 2),
    ]
    failed = 0
    for name, samples, want in cases:
        got = len(Detector().run(samples))
        ok = got == want
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {got} (want {want})")
    hits = Detector().run(sample)
    if hits:
        print(f"     sample fires at {hits[0]}/{len(sample)} samples = {hits[0] / 25:.1f} s")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
