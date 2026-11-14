import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// One member: a compass whose dial turns with my heading and an arrow that
// points at them, the distance, and their vitals. START (or a tap) offers
// "Check on them".
class MemberDetailView extends WatchUi.View {
    private var _id as String;
    private var _timer as Timer.Timer?;

    function initialize(id as String) {
        View.initialize();
        _id = id;
    }

    // Redraw every second so the compass follows the heading.
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

    function onUpdate(dc as Dc) as Void {
        var s = getState();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        Theme.clear(dc);

        var m = s.member(_id);
        if (m == null) {
            Theme.text(dc, cx, h / 2, Graphics.FONT_TINY, "Loading...", Theme.MUTED);
            return;
        }

        Theme.chevronLeft(dc, w * 21 / 100, h * 11 / 100, Theme.TEXT);
        Theme.text(dc, cx, h * 10 / 100, Graphics.FONT_SMALL, m["name"] as String, Theme.TEXT);

        drawCompass(dc, cx, h * 43 / 100, h * 26 / 100, m);

        // Divider and vitals.
        dc.setColor(Theme.CARD_EDGE, Theme.CARD_EDGE);
        dc.drawLine(w * 16 / 100, h * 72 / 100, w * 84 / 100, h * 72 / 100);
        var colY = h * 78 / 100;
        var gap = w * 23 / 100;
        var spo2 = m["spo2"];
        var batt = m["battery"];
        var hr = m["hr"];
        Theme.heart(dc, cx - gap, colY, 16, Theme.DANGER);
        Theme.drop(dc, cx, colY, 16, Theme.ACCENT);
        Theme.battery(dc, cx + gap, colY, 16, batt);
        var valY = h * 86 / 100;
        Theme.text(dc, cx - gap, valY, Graphics.FONT_TINY, hr == null ? "--" : hr.toString(), Theme.TEXT);
        Theme.text(dc, cx, valY, Graphics.FONT_TINY, spo2 == null ? "--" : spo2 + "%", Theme.TEXT);
        Theme.text(dc, cx + gap, valY, Graphics.FONT_TINY, batt == null ? "--" : batt + "%", Theme.TEXT);
        var labY = h * 93 / 100;
        Theme.text(dc, cx - gap, labY, Graphics.FONT_XTINY, "bpm", Theme.MUTED);
        Theme.text(dc, cx, labY, Graphics.FONT_XTINY, "SpO2", Theme.MUTED);
        Theme.text(dc, cx + gap, labY, Graphics.FONT_XTINY, "Batt", Theme.MUTED);
        dc.setColor(Theme.CARD_EDGE, Theme.CARD_EDGE);
        dc.drawLine(cx - gap / 2, h * 75 / 100, cx - gap / 2, h * 92 / 100);
        dc.drawLine(cx + gap / 2, h * 75 / 100, cx + gap / 2, h * 92 / 100);
    }

    private function drawCompass(dc as Dc, cx as Number, cy as Number, r as Number, m as Dictionary) as Void {
        var s = getState();
        var heading = s.myHeading();

        dc.setColor(0x000055, 0x000055);
        dc.fillCircle(cx, cy, r);
        dc.setColor(Theme.CARD_EDGE, Theme.CARD_EDGE);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, r);
        dc.setPenWidth(1);

        // Tick marks every 10°, longer every 30°. The dial turns so north
        // stays north while the watch rotates.
        dc.setColor(Theme.MUTED, Theme.MUTED);
        for (var d = 0; d < 360; d += 10) {
            var a = (d - heading).toFloat();
            var inner = d % 30 == 0 ? r - 9 : r - 5;
            var p1 = Theme.polar(cx, cy, r - 2, a);
            var p2 = Theme.polar(cx, cy, inner, a);
            dc.drawLine(p1[0], p1[1], p2[0], p2[1]);
        }
        var labels = ["N", "E", "S", "W"] as Array<String>;
        for (var i = 0; i < 4; i++) {
            var p = Theme.polar(cx, cy, r - 18, (i * 90 - heading).toFloat());
            Theme.text(dc, p[0], p[1], Graphics.FONT_XTINY, labels[i], i == 0 ? Theme.DANGER : Theme.TEXT);
        }

        var angle = s.arrowAngle(m["lat"], m["lon"]);
        if (angle == null) {
            Theme.text(dc, cx, cy - 6, Graphics.FONT_XTINY, "No GPS fix", Theme.MUTED);
            return;
        }
        Theme.arrow(dc, cx, cy - r * 15 / 100, r * 38 / 100, angle);
        Theme.text(dc, cx, cy + r * 45 / 100, Graphics.FONT_TINY, Theme.distance(s.distanceTo(m["lat"], m["lon"])), Theme.TEXT);
    }
}

class MemberDetailDelegate extends WatchUi.BehaviorDelegate {
    private var _id as String;

    function initialize(id as String) {
        BehaviorDelegate.initialize();
        _id = id;
    }

    function onSelect() as Boolean {
        openActions();
        return true;
    }

    function onMenu() as Boolean {
        openActions();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var w = System.getDeviceSettings().screenWidth;
        // The back chevron in the top-left.
        if (xy[1] < w * 22 / 100 && xy[0] < w * 35 / 100) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            openActions();
        }
        return true;
    }

    private function openActions() as Void {
        var m = getState().member(_id);
        var name = m == null ? _id : m["name"] as String;
        var menu = new WatchUi.Menu2({ :title => name });
        menu.addItem(new WatchUi.MenuItem("Check on " + name, "Are you OK?", :checkin, null));
        menu.addItem(new WatchUi.MenuItem("Back", null, :back, null));
        WatchUi.pushView(menu, new MemberActionsDelegate(_id, name), WatchUi.SLIDE_UP);
    }
}

class MemberActionsDelegate extends WatchUi.Menu2InputDelegate {
    private var _id as String;
    private var _name as String;

    function initialize(id as String, name as String) {
        Menu2InputDelegate.initialize();
        _id = id;
        _name = name;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (item.getId() == :checkin) {
            var s = getState();
            s.sendCheckin(_id);
            s.pushMessage(true, "Check-in sent", "Waiting for " + _name);
        }
    }
}
