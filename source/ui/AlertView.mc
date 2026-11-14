import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// SOS, fall and health alerts about another member: what happened, who, how
// far, "You are the closest member." when rank is 1, and an arrow to them.
// START (or tapping Acknowledge) marks it seen. MENU opens their detail.
class AlertView extends WatchUi.View {
    var event as Dictionary;
    private var _timer as Timer.Timer?;

    function initialize(ev as Dictionary) {
        View.initialize();
        event = ev;
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

    function tick() as Void {
        WatchUi.requestUpdate();
    }

    function title() as String {
        var type = event["type"] as String;
        var reason = event["reason"];
        if (type.equals("fall")) {
            return "Fall Detected";
        }
        if (type.equals("health")) {
            if ("hr_high".equals(reason)) { return "High Heart Rate"; }
            if ("hr_low".equals(reason)) { return "Low Heart Rate"; }
            if ("spo2_low".equals(reason)) { return "Low Oxygen"; }
            return "Health Alert";
        }
        if ("checkin_timeout".equals(reason)) {
            return "No Reply: SOS";
        }
        return "SOS";
    }

    // The line under the name: the reading for health alerts, else the cause.
    function detail() as String {
        var type = event["type"] as String;
        var reason = event["reason"];
        var value = event["value"];
        if (type.equals("health") && value != null) {
            return "spo2_low".equals(reason) ? "SpO2 " + value + "%" : value + " bpm";
        }
        if ("checkin_help".equals(reason)) {
            return "Asked for help";
        }
        if ("checkin_timeout".equals(reason)) {
            return "Didn't answer a check-in";
        }
        return type.equals("fall") ? "May need help" : "Needs help";
    }

    // Acknowledge button [x, y, w, h].
    function buttonRect(w as Number, h as Number) as Array<Number> {
        var bw = w * 56 / 100;
        var bh = h * 14 / 100;
        return [(w - bw) / 2, h * 80 / 100, bw, bh] as Array<Number>;
    }

    function onUpdate(dc as Dc) as Void {
        var s = getState();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var isHealth = "health".equals(event["type"]);

        Theme.clear(dc);
        // Red glow behind the top half.
        dc.setColor(Theme.DANGER_DK, Theme.DANGER_DK);
        dc.fillCircle(cx, h * 15 / 100, w * 55 / 100);

        Theme.warning(dc, cx, h * 10 / 100, 26);
        Theme.text(dc, cx, h * 23 / 100, Graphics.FONT_SMALL, Theme.fit(dc, Graphics.FONT_SMALL, title(), w * 85 / 100), Theme.TEXT);
        Theme.text(dc, cx, h * 34 / 100, Graphics.FONT_TINY, event["fromName"] as String, Theme.TEXT);

        var line = event["rank"] == 1 ? "You are the closest member." : detail();
        Theme.text(dc, cx, h * 43 / 100, Graphics.FONT_XTINY, Theme.fit(dc, Graphics.FONT_XTINY, line, w * 88 / 100),
            event["rank"] == 1 ? Theme.WARN : Theme.MUTED);
        if (event["rank"] == 1 && !isHealth) {
            Theme.text(dc, cx, h * 51 / 100, Graphics.FONT_XTINY, detail(), Theme.MUTED);
        }

        // Ripples with an arrow pointing at them, and the distance.
        var ry = h * 72 / 100;
        dc.setColor(Theme.ACCENT_DK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var i = 1; i <= 3; i++) {
            dc.drawArc(cx, ry, i * 15 + 10, Graphics.ARC_COUNTER_CLOCKWISE, 25, 155);
        }
        dc.setPenWidth(1);
        var angle = s.arrowAngle(event["lat"], event["lon"]);
        Theme.arrow(dc, cx, ry - 18, 14, angle == null ? 0.0 : angle);
        var dist = s.distanceTo(event["lat"], event["lon"]);
        if (dist == null && event["distanceM"] != null) {
            dist = (event["distanceM"] as Numeric).toFloat();
        }
        Theme.text(dc, cx, ry + 1, Graphics.FONT_XTINY, Theme.distance(dist), Theme.TEXT);

        var b = buttonRect(w, h);
        dc.setColor(Theme.ORANGE, Theme.ORANGE);
        dc.fillRoundedRectangle(b[0], b[1], b[2], b[3], b[3] / 2);
        Theme.text(dc, cx, b[1] + b[3] / 2, Graphics.FONT_XTINY, "Acknowledge", Theme.TEXT);
    }
}

class AlertDelegate extends WatchUi.BehaviorDelegate {
    private var _view as AlertView;

    function initialize(view as AlertView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        acknowledge();
        return true;
    }

    function onBack() as Boolean {
        acknowledge();
        return true;
    }

    // Jump to the member's compass screen (the alert is acked first).
    function onMenu() as Boolean {
        var id = _view.event["from"] as String;
        acknowledge();
        if (getState().member(id) != null) {
            WatchUi.pushView(new MemberDetailView(id), new MemberDetailDelegate(id), WatchUi.SLIDE_LEFT);
        }
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var settings = System.getDeviceSettings();
        if (Theme.inRect(xy[0], xy[1], _view.buttonRect(settings.screenWidth, settings.screenHeight))) {
            acknowledge();
            return true;
        }
        return false;
    }

    private function acknowledge() as Void {
        var s = getState();
        s.ack(_view.event, "seen");
        _view.onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        s.modalClosed();
    }
}
