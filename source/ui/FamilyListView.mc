import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Main screen: everyone else in the family, one card each, with heart rate,
// distance and a status dot. The selected card sits in the middle with a blue
// outline. UP/DOWN (or swipe) moves, START (or tap) opens the member.
class FamilyListView extends WatchUi.View {
    var selected as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var s = getState();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        Theme.clear(dc);

        Theme.people(dc, cx, h * 9 / 100);
        Theme.text(dc, cx, h * 19 / 100, Graphics.FONT_SMALL, "Family", Theme.TEXT);

        var list = s.members;
        if (list.size() == 0) {
            Theme.text(dc, cx, h / 2, Graphics.FONT_TINY, s.connected ? "No one else yet" : "Connecting...", Theme.MUTED);
            var detail = s.lastError != null ? s.lastError + " · " + getTester().serverHost() : getTester().serverHost();
            Theme.text(dc, cx, h * 62 / 100, Graphics.FONT_XTINY, Theme.fit(dc, Graphics.FONT_XTINY, detail, w * 3 / 4), Theme.DIM);
            return;
        }
        if (selected >= list.size()) {
            selected = list.size() - 1;
        }

        // Rows above and below the selected one.
        var rowH = h * 21 / 100;
        var midY = h * 54 / 100;
        for (var off = -1; off <= 1; off++) {
            var i = selected + off;
            if (i >= 0 && i < list.size()) {
                drawRow(dc, list[i] as Dictionary, midY + off * rowH, off == 0);
            }
        }

        // Page dots.
        var n = list.size();
        var gap = 12;
        var x0 = cx - (n - 1) * gap / 2;
        for (var i = 0; i < n; i++) {
            dc.setColor(i == selected ? Theme.TEXT : Theme.DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + i * gap, h * 93 / 100, i == selected ? 4 : 3);
        }
    }

    // Which row a tap at y landed on (-1, 0 or 1 relative to the selection).
    function rowAt(h as Number, y as Number) as Number {
        var rowH = h * 21 / 100;
        var midY = h * 54 / 100;
        if (y < midY - rowH * 3 / 2 || y > midY + rowH * 3 / 2) {
            return -99;
        }
        if (y < midY - rowH / 2) {
            return -1;
        }
        return y > midY + rowH / 2 ? 1 : 0;
    }

    private function drawRow(dc as Dc, m as Dictionary, y as Number, focused as Boolean) as Void {
        var s = getState();
        var w = dc.getWidth();
        var cardH = dc.getHeight() * 19 / 100;
        var x = w * 6 / 100;
        var cw = w - 2 * x;
        dc.setColor(Theme.CARD, Theme.CARD);
        dc.fillRoundedRectangle(x, y - cardH / 2, cw, cardH, cardH / 2);
        if (focused) {
            dc.setColor(Theme.ACCENT, Theme.ACCENT);
            dc.setPenWidth(3);
            dc.drawRoundedRectangle(x - 3, y - cardH / 2 - 3, cw + 6, cardH + 6, cardH / 2 + 3);
            dc.setPenWidth(1);
        }

        var id = m["id"] as String;
        var r = cardH * 4 / 10;
        Theme.avatar(dc, x + cardH / 2 + 4, y, r, id);

        var tx = x + cardH + 12;
        var textW = cw - cardH - 40;
        var status = m["status"] as String?;
        var hr = m["hr"];
        var dist = s.distanceTo(m["lat"], m["lon"]);
        var line2 = (hr == null ? "--" : hr.toString()) + " bpm · " + Theme.distance(dist);
        if ("stale".equals(status)) {
            line2 = "offline";
        } else if ("sos".equals(status)) {
            line2 = "SOS · " + Theme.distance(dist);
        }
        Theme.textLeft(dc, tx, y - cardH / 5, Graphics.FONT_TINY, Theme.fit(dc, Graphics.FONT_TINY, m["name"] as String, textW), Theme.TEXT);
        Theme.textLeft(dc, tx, y + cardH / 5, Graphics.FONT_XTINY, Theme.fit(dc, Graphics.FONT_XTINY, line2, textW),
            "sos".equals(status) ? Theme.DANGER : Theme.MUTED);

        var dot = Theme.statusColor(status);
        dc.setColor(dot, dot);
        dc.fillCircle(x + cw - cardH / 2 + 4, y, 7);
    }
}

class FamilyListDelegate extends WatchUi.BehaviorDelegate {
    private var _view as FamilyListView;

    function initialize(view as FamilyListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        return move(1);
    }

    function onPreviousPage() as Boolean {
        return move(-1);
    }

    function onSelect() as Boolean {
        openSelected();
        return true;
    }

    function onMenu() as Boolean {
        openMainMenu();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var h = System.getDeviceSettings().screenHeight;
        var off = _view.rowAt(h, xy[1]);
        if (off == -99) {
            return false;
        }
        if (off == 0) {
            openSelected();
        } else {
            move(off);
        }
        return true;
    }

    private function move(by as Number) as Boolean {
        var n = getState().members.size();
        if (n == 0) {
            return false;
        }
        _view.selected = (_view.selected + by + n) % n;
        WatchUi.requestUpdate();
        return true;
    }

    private function openSelected() as Void {
        var list = getState().members;
        if (list.size() == 0) {
            openMainMenu();
            return;
        }
        var id = list[_view.selected]["id"] as String;
        WatchUi.pushView(new MemberDetailView(id), new MemberDetailDelegate(id), WatchUi.SLIDE_LEFT);
    }
}
