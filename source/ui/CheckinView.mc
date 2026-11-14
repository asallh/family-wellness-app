import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// "Mom is asking: are you OK?" with four answers and a countdown ring.
// Yes and I'm Fine answer "ok". No answers "no" (not OK) and Need Help answers
// "help"; for both, the server alerts the whole family. UP/DOWN moves the
// focus, START picks, or tap a button.
class CheckinView extends WatchUi.View {
    const LABELS = ["Yes", "No", "Need Help", "I'm Fine"];
    const RESPONSES = ["ok", "no", "help", "ok"];

    var focus as Number = 0;
    var answered as Boolean = false; // set once, so only one answer is sent
    var event as Dictionary;
    private var _deadline as Number;
    private var _total as Number = 30; // the server's check-in timeout
    private var _timer as Timer.Timer?;

    function initialize(ev as Dictionary) {
        View.initialize();
        event = ev;
        var secs = ev["expiresInSec"];
        var left = secs instanceof Number ? secs : 30;
        if (left > _total) {
            _total = left;
        }
        _deadline = System.getTimer() + left * 1000;
    }

    function onShow() as Void {
        if (_timer == null && !answered) {
            _timer = new Timer.Timer();
            _timer.start(method(:tick), 1000, true);
        }
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
        if (answered) {
            return;
        }
        if (secondsLeft() == 0) {
            answered = true;
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
        var frac = left / _total.toFloat();
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
        Theme.line(dc, h * 23 / 100, Graphics.FONT_SMALL, getState().nameOf(event), Theme.TEXT);
        Theme.line(dc, h * 34 / 100, Graphics.FONT_TINY, "Are you OK?", Theme.TEXT);
        Theme.line(dc, h * 43 / 100, Graphics.FONT_XTINY, left + "s to answer", left <= 10 ? Theme.WARN : Theme.MUTED);

        var rects = buttons(w, h);
        for (var i = 0; i < rects.size(); i++) {
            var r = rects[i];
            Theme.button(dc, r[0], r[1], r[2], r[3], LABELS[i] as String, i == focus, Theme.BUTTON);
        }
    }
}

class CheckinDelegate extends ScreenDelegate {
    private var _view as CheckinView;

    function initialize(view as CheckinView) {
        ScreenDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.focus = (_view.focus + 1) % 4;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.focus = (_view.focus + 3) % 4;
        WatchUi.requestUpdate();
        return true;
    }

    // START answers with the focused button.
    function onStart() as Void {
        answer(_view.focus);
    }

    // A tap answers with the button it landed on. A tap between buttons does
    // nothing (it used to fall through to the focused "Yes"). The top band
    // hides the prompt, like BACK.
    function onTouch(x as Number, y as Number) as Void {
        var settings = System.getDeviceSettings();
        var rects = _view.buttons(settings.screenWidth, settings.screenHeight);
        for (var i = 0; i < rects.size(); i++) {
            if (Theme.inRect(x, y, rects[i])) {
                _view.focus = i;
                answer(i);
                return;
            }
        }
        if (y < settings.screenHeight * 20 / 100) {
            onBack();
        }
    }

    // BACK hides the prompt without answering; the server times it out.
    function onBack() as Boolean {
        if (_view.answered) {
            return true;
        }
        _view.answered = true;
        _view.onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        getState().modalClosed();
        return true;
    }

    private function answer(i as Number) as Void {
        // Only the first answer counts (a double press or a late timer).
        if (_view.answered) {
            return;
        }
        _view.answered = true;
        _view.onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        getState().answerCheckin(_view.event, _view.RESPONSES[i] as String);
    }
}
