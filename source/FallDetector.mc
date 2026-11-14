import Toybox.Lang;
import Toybox.Math;

// Fall detection on accelerometer magnitude (milli-g) at 25 Hz:
//   1. free fall: magnitude drops below 400 mg
//   2. impact: above 2500 mg within 1 s of the free fall starting
//   3. stillness: after a short settle, about 2 s within +/-200 mg of 1 g
// A free fall that times out waits for the reading to come back above 400 mg
// before it can start again, so a long low reading can't re-arm itself.
// The live accelerometer and "Simulate fall" both go through addSample(), so
// the demo exercises the same code the real watch runs.
// tools/check_fall.py mirrors this logic to test it off the watch.
class FallDetector {
    const RATE_HZ = 25;
    const FREE_FALL_MG = 400;
    const IMPACT_MG = 2500;
    const IMPACT_WINDOW = 25;   // samples (1 s) from free fall to impact
    const SETTLE = 8;           // samples (~0.3 s) of bounce ignored after impact
    const STILL_SAMPLES = 50;   // samples (2 s) that must be still
    const STILL_TOL_MG = 200;  // walking at the wrist swings well past this

    private var _state as Number = 0; // 0 idle, 1 free fall, 2 checking stillness, 3 re-arming
    private var _count as Number = 0;

    function initialize() {
    }

    function reset() as Void {
        _state = 0;
        _count = 0;
    }

    // Feeds one magnitude sample. Returns true on the sample that completes a fall.
    function addSample(mg as Numeric) as Boolean {
        if (_state == 0) {
            if (mg < FREE_FALL_MG) {
                _state = 1;
                _count = 0;
            }
        } else if (_state == 1) {
            _count++;
            if (mg > IMPACT_MG) {
                _state = 2;
                _count = 0;
            } else if (_count > IMPACT_WINDOW) {
                _state = 3;
            }
        } else if (_state == 3) {
            if (mg >= FREE_FALL_MG) {
                reset();
            }
        } else {
            _count++;
            var off = mg - 1000;
            if (off < 0) { off = -off; }
            if (_count > SETTLE && off > STILL_TOL_MG) {
                // Moving again: walked it off, not a fall.
                reset();
            } else if (_count >= SETTLE + STILL_SAMPLES) {
                reset();
                return true;
            }
        }
        return false;
    }

    // Feeds a batch. Returns true if any sample completed a fall.
    function addSamples(samples as Array<Numeric>) as Boolean {
        var fell = false;
        for (var i = 0; i < samples.size(); i++) {
            if (addSample(samples[i])) {
                fell = true;
            }
        }
        return fell;
    }

    // Converts one batch of accelerometer x/y/z arrays (mg) to magnitudes.
    static function magnitudes(x as Array<Numeric>, y as Array<Numeric>, z as Array<Numeric>) as Array<Numeric> {
        var n = x.size();
        if (y.size() < n) { n = y.size(); }
        if (z.size() < n) { n = z.size(); }
        var out = new [n] as Array<Numeric>;
        for (var i = 0; i < n; i++) {
            var a = x[i].toFloat();
            var b = y[i].toFloat();
            var c = z[i].toFloat();
            out[i] = Math.sqrt(a * a + b * b + c * c);
        }
        return out;
    }
}

// A recorded fall at 25 Hz (magnitude in mg): walking, ~0.4 s free fall, the
// impact and bounce, then lying still. "Simulate fall" plays this through the
// detector.
module FallSample {
    const WALK = [1010, 1180, 1320, 1090, 870, 760, 940, 1150, 1290, 1120,
                  900, 780, 960, 1170, 1310, 1100, 880, 770, 950, 1160,
                  1300, 1080, 890, 790, 980];
    const FALL = [720, 410, 260, 180, 140, 120, 130, 150, 190, 240,
                  3350, 2900, 1700, 640, 1450, 820, 1180, 950,
                  1020, 990, 1005, 1012, 998, 985, 1001, 1010, 995, 990,
                  1003, 1008, 997, 992, 1000, 1011, 996, 989, 1002, 1006,
                  999, 994, 1004, 1009, 993, 988, 1001, 1007, 998, 991,
                  1003, 1010, 996, 990, 1000, 1005, 997, 993, 1002, 1008,
                  999, 995, 1004, 1006, 994, 990, 1001, 1009, 998, 992,
                  1003, 997, 1001, 1006, 995, 991, 1002, 1008, 999, 994,
                  1000, 1004];

    function samples() as Array<Numeric> {
        // Copy: addAll would otherwise grow the constant arrays.
        var out = [] as Array<Numeric>;
        out.addAll(WALK);
        out.addAll(FALL);
        return out;
    }
}
