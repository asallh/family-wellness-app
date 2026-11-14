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

        // Layout for a 260 px round screen, scaled: icon 18, title 42, rows at
        // 88 / 142 / 196 (46 tall), page dots 240.
        Theme.people(dc, cx, h * 7 / 100);
        Theme.text(dc, cx, h * 16 / 100, Graphics.FONT_SMALL, "Family", Theme.TEXT);

        var list = s.members;
        if (list.size() == 0) {
            Theme.line(dc, h / 2, Graphics.FONT_TINY, s.connected ? "No one else yet" : "Connecting...", Theme.MUTED);
            var detail = s.lastError != null ? s.lastError + " · " + getTester().serverHost() : getTester().serverHost();
            Theme.line(dc, h * 61 / 100, Graphics.FONT_XTINY, detail, Theme.DIM);
            return;
        }
        if (selected >= list.size()) {
            selected = list.size() - 1;
        }

        // Rows above and below the selected one.
        var rowH = h * 21 / 100;
        var midY = h * 545 / 1000;
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
            dc.fillCircle(x0 + i * gap, h * 92 / 100, i == selected ? 4 : 3);
        }
    }

    // Which row a tap at y landed on (-1, 0 or 1 relative to the selection).
    function rowAt(h as Number, y as Number) as Number {
        var rowH = h * 21 / 100;
        var midY = h * 545 / 1000;
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
        var cx = w / 2;
        var cardH = dc.getHeight() * 175 / 1000;

        // As wide as the circle allows at the card's edge farthest from the
        // centre, so the top and bottom cards tuck inside the bezel.
        var top = y - cardH / 2;
        var bottom = y + cardH / 2;
        var half = Theme.halfWidth(dc, (top - dc.getHeight() / 2).abs() > (bottom - dc.getHeight() / 2).abs() ? top : bottom) - 6;
        if (half > w * 44 / 100) {
            half = w * 44 / 100;
        }
        var x = cx - half;
        var cw = 2 * half;

        dc.setColor(Theme.CARD, Theme.CARD);
        dc.fillRoundedRectangle(x, top, cw, cardH, cardH / 2);
        if (focused) {
            dc.setColor(Theme.ACCENT, Theme.ACCENT);
            dc.setPenWidth(3);
            dc.drawRoundedRectangle(x - 2, top - 2, cw + 4, cardH + 4, cardH / 2 + 2);
            dc.setPenWidth(1);
        }

        var id = m["id"] as String;
        var r = cardH * 4 / 10;
        Theme.avatar(dc, x + cardH / 2 + 1, y, r, id);

        var dotX = x + cw - cardH / 2;
        var tx = x + cardH + 6;
        var textW = dotX - 12 - tx;
        var status = m["status"] as String?;
        var hr = m["hr"];
        var dist = Theme.distance(s.distanceTo(m["lat"], m["lon"]));
        var hrText = hr == null ? "--" : hr.toString();
        var line2 = hrText + " bpm · " + dist;
        if (dc.getTextWidthInPixels(line2, Graphics.FONT_XTINY) > textW) {
            line2 = hrText + " · " + dist;
        }
        if ("stale".equals(status)) {
            line2 = "offline";
        } else if ("sos".equals(status)) {
            line2 = "SOS · " + dist;
        }
        var nameH = dc.getFontHeight(Graphics.FONT_TINY);
        var subH = dc.getFontHeight(Graphics.FONT_XTINY);
        // Two lines centred as a block on the card.
        var blockTop = y - (nameH + subH - 6) / 2;
        Theme.textLeft(dc, tx, blockTop + nameH / 2, Graphics.FONT_TINY,
            Theme.fit(dc, Graphics.FONT_TINY, m["name"] as String, textW), focused ? Theme.TEXT : Theme.MUTED);
        Theme.textLeft(dc, tx, blockTop + nameH - 6 + subH / 2, Graphics.FONT_XTINY, Theme.fit(dc, Graphics.FONT_XTINY, line2, textW),
            "sos".equals(status) ? Theme.DANGER : Theme.MUTED);

        var dot = Theme.statusColor(status);
        dc.setColor(dot, dot);
        dc.fillCircle(dotX, y, 6);
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
