import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// "Did you fall?" after the detector fires: a 15 s countdown ring, then the
// watch sends a fall SOS to the family. "I'm OK" cancels, "Get help" sends it
// now. UP/DOWN moves the focus, START picks, BACK means "I'm OK", or tap a
// button.
class FallView extends WatchUi.View {
    const LABELS = ["I'm OK", "Get help"];

    var focus as Number = 0;
    var done as Boolean = false; // set once, so only one outcome happens
    private var _deadline as Number;
    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
        _deadline = System.getTimer() + Config.FALL_COUNTDOWN_S * 1000;
    }

    function onShow() as Void {
        if (_timer == null && !done) {
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
        var left = (_deadline - System.getTimer() + 999) / 1000;
        return left < 0 ? 0 : left;
    }

    function tick() as Void {
        if (done) {
            return;
        }
        var left = secondsLeft();
        if (left == 0) {
            finish(true);
            return;
        }
        if (left <= 5) {
            getState().vibrate(1);
        }
        WatchUi.requestUpdate();
    }

    // Closes the screen: sendAlert true sends the fall SOS, false cancels.
    function finish(sendAlert as Boolean) as Void {
        if (done) {
            return;
        }
        done = true;
        onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        getState().fallPromptClosed(sendAlert);
    }

    // Button rectangles [x, y, w, h], in the order of LABELS.
    function buttons(w as Number, h as Number) as Array<Array<Number>> {
        var gap = w * 25 / 1000;
        var bw = w * 36 / 100;
        var bh = h * 15 / 100;
        var y = h * 66 / 100;
        return [
            [w / 2 - gap / 2 - bw, y, bw, bh],
            [w / 2 + gap / 2, y, bw, bh]
        ] as Array<Array<Number>>;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        Theme.clear(dc);

        var left = secondsLeft();
        var frac = left / Config.FALL_COUNTDOWN_S.toFloat();
        if (frac > 1) {
            frac = 1.0;
        }
        dc.setPenWidth(6);
        dc.setColor(Theme.DANGER_DK, Theme.DANGER_DK);
        dc.drawCircle(cx, h / 2, w / 2 - 4);
        if (frac > 0) {
            dc.setColor(Theme.DANGER, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, h / 2, w / 2 - 4, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * frac).toNumber());
        }
        dc.setPenWidth(1);

        Theme.warning(dc, cx, h * 13 / 100, w * 9 / 100);
        Theme.line(dc, h * 26 / 100, Graphics.FONT_SMALL, "Did you fall?", Theme.TEXT);
        Theme.text(dc, cx, h * 43 / 100, Graphics.FONT_NUMBER_MEDIUM, left.toString(), left <= 5 ? Theme.DANGER : Theme.WARN);
        Theme.line(dc, h * 57 / 100, Graphics.FONT_XTINY, "Alerting family at 0", Theme.MUTED);

        var rects = buttons(w, h);
        for (var i = 0; i < rects.size(); i++) {
            var r = rects[i];
            Theme.button(dc, r[0], r[1], r[2], r[3], LABELS[i] as String, i == focus, i == 0 ? Theme.OK_DK : Theme.DANGER);
        }
    }
}

class FallDelegate extends ScreenDelegate {
    private var _view as FallView;

    function initialize(view as FallView) {
        ScreenDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.focus = 1 - _view.focus;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        return onNextPage();
    }

    function onStart() as Void {
        _view.finish(_view.focus == 1);
    }

    function onTouch(x as Number, y as Number) as Void {
        var settings = System.getDeviceSettings();
        var rects = _view.buttons(settings.screenWidth, settings.screenHeight);
        for (var i = 0; i < rects.size(); i++) {
            if (Theme.inRect(x, y, rects[i])) {
                _view.focus = i;
                _view.finish(i == 1);
                return;
            }
        }
    }

    // BACK is "I'm OK": the quickest way out for someone who is fine.
    function onBack() as Boolean {
        _view.finish(false);
        return true;
    }
}
