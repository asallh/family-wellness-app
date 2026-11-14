import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Base delegate for screens that use both the START button and taps.
//
// On a touch screen a tap first fires the Select behaviour, and onTap only
// runs if onSelect returns false (see BehaviorDelegate in the SDK docs). So a
// screen that acts in onSelect can't tell a tap on "No" from START on the
// focused "Yes": every tap answered with the focused button. Here onSelect
// waits briefly instead. If a tap follows, the tap decides from where it
// landed; if not, it was the START button and onStart() acts on the focus.
class ScreenDelegate extends WatchUi.BehaviorDelegate {
    const TAP_WAIT_MS = 120;
    private var _pending as Timer.Timer?;

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // START was pressed (not a tap). Override.
    function onStart() as Void {
    }

    // A tap at (x, y). Override.
    function onTouch(x as Number, y as Number) as Void {
    }

    function onSelect() as Boolean {
        cancelPending();
        _pending = new Timer.Timer();
        _pending.start(method(:firePending), TAP_WAIT_MS, false);
        return false; // let a tap reach onTap
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        cancelPending();
        var xy = evt.getCoordinates();
        onTouch(xy[0], xy[1]);
        return true; // a tap never falls back to "pick the focused item"
    }

    function firePending() as Void {
        _pending = null;
        onStart();
    }

    function cancelPending() as Void {
        if (_pending != null) {
            _pending.stop();
            _pending = null;
        }
    }
}
