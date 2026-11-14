import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// "Mom is asking: are you OK?" with four answers and a countdown ring. Yes and
// I'm Fine answer OK; No and Need Help ask for help (the server then alerts
// the whole family). UP/DOWN moves the focus, START picks, or tap a button.
class CheckinView extends WatchUi.View {
    const LABELS = ["Yes", "No", "Need Help", "I'm Fine"];

    var focus as Number = 0;
    var event as Dictionary;
    private var _deadline as Number;
    private var _timer as Timer.Timer?;

    function initialize(ev as Dictionary) {
        View.initialize();
        event = ev;
        var secs = ev["expiresInSec"];
        _deadline = System.getTimer() + (secs == null ? 30 : secs as Number) * 1000;
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 1000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function secondsLeft() as Number {
        var left = (_deadline - System.getTimer()) / 1000;
        return left < 0 ? 0 : left;
    }

    function tick() as Void {
        if (secondsLeft() == 0) {
            // The server escalates on its own; just tell the wearer.
            onHide();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            getState().pushMessage(false, "No reply sent", "Family has been alerted");
            return;
        }
        WatchUi.requestUpdate();
    }

    // Button rectangles [x, y, w, h], in the order of LABELS. On a 260 px
    // screen: a wide row at 134-172 and a narrower one at 178-214, so the
    // lower buttons stay inside the circle.
    function buttons(w as Number, h as Number) as Array<Array<Number>> {
        var gap = w * 25 / 1000;
        var bw = w * 40 / 100;
        var bh = h * 145 / 1000;
        var y1 = h * 515 / 1000;
        var y2 = y1 + bh + gap;
        var sw = w * 34 / 100;
        var sh = h * 14 / 100;
        return [
            [w / 2 - gap / 2 - bw, y1, bw, bh],
            [w / 2 + gap / 2, y1, bw, bh],
            [w / 2 - gap / 2 - sw, y2, sw, sh],
            [w / 2 + gap / 2, y2, sw, sh]
        ] as Array<Array<Number>>;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        Theme.clear(dc);

        // Countdown ring around the edge.
        var left = secondsLeft();
        var frac = left / 30.0;
        if (frac > 1) {
            frac = 1.0;
        }
        dc.setPenWidth(5);
        dc.setColor(Theme.CARD, Theme.CARD);
        dc.drawCircle(cx, h / 2, w / 2 - 3);
        if (frac > 0) {
            dc.setColor(left <= 10 ? Theme.WARN : Theme.ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, h / 2, w / 2 - 3, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * frac).toNumber());
        }
        dc.setPenWidth(1);

        // Header 28, name 60, question 88, countdown 112 (on a 260 px screen).
        Theme.chevronLeft(dc, w * 29 / 100, h * 11 / 100, Theme.MUTED);
        Theme.text(dc, cx, h * 11 / 100, Graphics.FONT_XTINY, "Check-in", Theme.MUTED);
        Theme.line(dc, h * 23 / 100, Graphics.FONT_SMALL, event["fromName"] as String, Theme.TEXT);
        Theme.line(dc, h * 34 / 100, Graphics.FONT_TINY, "Are you OK?", Theme.TEXT);
        Theme.line(dc, h * 43 / 100, Graphics.FONT_XTINY, left + "s to answer", left <= 10 ? Theme.WARN : Theme.MUTED);

        var rects = buttons(w, h);
        for (var i = 0; i < rects.size(); i++) {
            var r = rects[i];
            Theme.button(dc, r[0], r[1], r[2], r[3], LABELS[i] as String, i == focus, Theme.BUTTON);
        }
    }
}

class CheckinDelegate extends WatchUi.BehaviorDelegate {
    private var _view as CheckinView;

    function initialize(view as CheckinView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    private function view() as CheckinView {
        return _view;
    }

    function onNextPage() as Boolean {
        var v = view();
        v.focus = (v.focus + 1) % 4;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        var v = view();
        v.focus = (v.focus + 3) % 4;
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        answer(view().focus);
        return true;
    }

    // BACK hides the prompt without answering; the server times it out.
    function onBack() as Boolean {
        view().onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        getState().modalClosed();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var settings = System.getDeviceSettings();
        var v = view();
        var rects = v.buttons(settings.screenWidth, settings.screenHeight);
        for (var i = 0; i < rects.size(); i++) {
            if (Theme.inRect(xy[0], xy[1], rects[i])) {
                v.focus = i;
                answer(i);
                return true;
            }
        }
        if (xy[1] < settings.screenHeight * 20 / 100) {
            return onBack();
        }
        return false;
    }

    private function answer(i as Number) as Void {
        var v = view();
        var ok = i == 0 || i == 3;
        var s = getState();
        s.ack(v.event, ok ? "ok" : "help");
        v.onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var name = v.event["fromName"] as String;
        s.pushMessage(ok, ok ? "Reply sent" : "Help requested", ok ? "Told " + name + " you're OK" : "Family has been alerted");
    }
}
