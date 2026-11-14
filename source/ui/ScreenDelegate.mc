import Toybox.Lang;
import Toybox.WatchUi;

// Base delegate for screens that use both the START button and taps.
//
// On a touch screen a tap first fires the Select behaviour, and onTap only
// runs if onSelect returns false (see BehaviorDelegate in the SDK docs). So a
// screen that acts in onSelect can't tell a tap on "No" from START on the
// focused "Yes": every tap answered with the focused button.
//
// Here onSelect always declines, so the SDK passes on the input that caused
// it: START arrives as onKey(KEY_ENTER) and acts on the focused item, and a
// tap arrives as onTap and acts on what it landed on. No timer is used
// (watch apps only get a few, and the poll and screen countdowns use them).
class ScreenDelegate extends WatchUi.BehaviorDelegate {

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
        return false; // hand over to onKey (START) or onTap (a tap)
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            onStart();
            return true;
        }
        return false;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        onTouch(xy[0], xy[1]);
        return true; // a tap never falls back to "pick the focused item"
    }
}
