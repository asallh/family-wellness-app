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
        if ("checkin_no".equals(reason)) {
            return "Said they're not OK";
        }
        if ("checkin_timeout".equals(reason)) {
            return "Didn't answer a check-in";
        }
        return type.equals("fall") ? "May need help" : "Needs help";
    }

    // Acknowledge button [x, y, w, h].
    function buttonRect(w as Number, h as Number) as Array<Number> {
        var bw = w * 50 / 100;
        var bh = h * 125 / 1000;
        return [(w - bw) / 2, h * 76 / 100, bw, bh] as Array<Number>;
    }

    function onUpdate(dc as Dc) as Void {
        var s = getState();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        Theme.clear(dc);
        // Layout on a 260 px screen: red glow down to 130, warning 22, title 50,
        // name 76, detail 98, "closest" 116, arrow + ripples 132-172,
        // distance 186, Acknowledge 198-230.
        dc.setColor(Theme.DANGER_DK, Theme.DANGER_DK);
        dc.fillCircle(cx, -h * 4 / 100, h * 52 / 100);

        Theme.warning(dc, cx, h * 85 / 1000, 24);
        Theme.line(dc, h * 19 / 100, Graphics.FONT_SMALL, title(), Theme.TEXT);
        Theme.line(dc, h * 29 / 100, Graphics.FONT_TINY, event["fromName"] as String, Theme.TEXT);
        Theme.line(dc, h * 375 / 1000, Graphics.FONT_XTINY, detail(), Theme.MUTED);
        if (event["rank"] == 1) {
            Theme.line(dc, h * 445 / 1000, Graphics.FONT_XTINY, "You are the closest member.", Theme.WARN);
        }

        // Ripples with an arrow pointing at them, and the distance under it.
        var ry = h * 66 / 100;
        dc.setColor(Theme.ACCENT_DK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var i = 1; i <= 3; i++) {
            dc.drawArc(cx, ry, h * (4 + 45 * i / 10) / 100, Graphics.ARC_COUNTER_CLOCKWISE, 30, 150);
        }
        dc.setPenWidth(1);
        // Point at where they are now if the family list has them, else where
        // the alert came from. No arrow at all rather than a made-up north.
        var m = s.member(event["from"] as String);
        var lat = m != null && m["lat"] != null ? m["lat"] : event["lat"];
        var lon = m != null && m["lon"] != null ? m["lon"] : event["lon"];
        var angle = s.arrowAngle(lat, lon);
        if (angle != null && s.noArrowReason({ "lat" => lat, "lon" => lon }) == null) {
            Theme.arrow(dc, cx, ry - h * 45 / 1000, h * 45 / 1000, angle);
        }
        var dist = s.distanceTo(lat, lon);
        if (dist == null && event["distanceM"] != null) {
            dist = (event["distanceM"] as Numeric).toFloat();
        }
        Theme.text(dc, cx, h * 715 / 1000, Graphics.FONT_XTINY, Theme.distance(dist), Theme.TEXT);

        var b = buttonRect(w, h);
        dc.setColor(Theme.ORANGE, Theme.ORANGE);
        dc.fillRoundedRectangle(b[0], b[1], b[2], b[3], b[3] / 2);
        Theme.text(dc, cx, b[1] + b[3] / 2, Graphics.FONT_XTINY, "Acknowledge", Theme.TEXT);
    }
}

class AlertDelegate extends ScreenDelegate {
    private var _view as AlertView;
    private var _done as Boolean = false;

    function initialize(view as AlertView) {
        ScreenDelegate.initialize();
        _view = view;
    }

    function onStart() as Void {
        acknowledge();
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

    // Only the Acknowledge button acknowledges a tap; anywhere else does nothing.
    function onTouch(x as Number, y as Number) as Void {
        var settings = System.getDeviceSettings();
        if (Theme.inRect(x, y, _view.buttonRect(settings.screenWidth, settings.screenHeight))) {
            acknowledge();
        }
    }

    private function acknowledge() as Void {
        if (_done) {
            return;
        }
        _done = true;
        var s = getState();
        s.ack(_view.event, "seen");
        _view.onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        s.modalClosed();
    }
}
