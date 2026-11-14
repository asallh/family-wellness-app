import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Colours and small vector icons shared by every screen. The fēnix 7 Pro has a
// 64-colour MIP display, so every colour here is one of its native shades
// (each channel 0x00, 0x55, 0xAA or 0xFF) to avoid dithering.
module Theme {
    const BG = 0x000000;
    const CARD = 0x000055;
    const CARD_EDGE = 0x0055AA;
    const ACCENT = 0x00AAFF;
    const ACCENT_LT = 0x55AAFF;
    const ACCENT_DK = 0x0055AA;
    const BUTTON = 0x0055FF;
    const TEXT = 0xFFFFFF;
    const MUTED = 0xAAAAAA;
    const DIM = 0x555555;
    const OK = 0x00FF55;
    const OK_DK = 0x005500;
    const WARN = 0xFFAA00;
    const DANGER = 0xFF0000;
    const DANGER_DK = 0x550000;
    const ORANGE = 0xFF5500;

    // ---- text ---------------------------------------------------------------

    function text(dc as Dc, x as Numeric, y as Numeric, font as FontType, s as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function textLeft(dc as Dc, x as Numeric, y as Numeric, font as FontType, s as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, s, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Cuts a string so it fits in maxWidth pixels.
    function fit(dc as Dc, font as FontType, s as String, maxWidth as Number) as String {
        if (dc.getTextWidthInPixels(s, font) <= maxWidth) {
            return s;
        }
        var n = s.length();
        while (n > 1 && dc.getTextWidthInPixels(s.substring(0, n) + "...", font) > maxWidth) {
            n--;
        }
        return s.substring(0, n) + "...";
    }

    function clear(dc as Dc) as Void {
        dc.setColor(BG, BG);
        dc.clear();
    }

    // ---- members ------------------------------------------------------------

    // Light and dark shade for each member's avatar.
    function memberColor(id as String?) as Number {
        if ("mom".equals(id)) { return 0xFF55FF; }
        if ("son".equals(id)) { return 0x55FF55; }
        if ("dad".equals(id)) { return 0x55AAFF; }
        if ("grandpa".equals(id)) { return 0xFFAA55; }
        return 0xAAAAAA;
    }

    function memberShade(id as String?) as Number {
        if ("mom".equals(id)) { return 0x550055; }
        if ("son".equals(id)) { return 0x005500; }
        if ("dad".equals(id)) { return 0x000055; }
        if ("grandpa".equals(id)) { return 0x552200; }
        return 0x555555;
    }

    function statusColor(status as String?) as Number {
        if ("sos".equals(status)) { return DANGER; }
        if ("alert".equals(status)) { return WARN; }
        if ("stale".equals(status)) { return DIM; }
        return OK;
    }

    // ---- icons --------------------------------------------------------------

    // Round avatar: a head and shoulders inside a tinted circle.
    function avatar(dc as Dc, x as Number, y as Number, r as Number, id as String?) as Void {
        dc.setColor(memberShade(id), memberShade(id));
        dc.fillCircle(x, y, r);
        dc.setColor(memberColor(id), memberColor(id));
        dc.fillCircle(x, y - r * 3 / 10, r * 3 / 10);
        dc.fillEllipse(x, y + r * 11 / 20, r * 11 / 20, r * 7 / 20);
    }

    // Three people, the middle one in front: the "Family" header icon.
    function people(dc as Dc, x as Number, y as Number) as Void {
        dc.setColor(ACCENT_DK, ACCENT_DK);
        dc.fillCircle(x - 13, y - 4, 4);
        dc.fillEllipse(x - 13, y + 5, 7, 4);
        dc.fillCircle(x + 13, y - 4, 4);
        dc.fillEllipse(x + 13, y + 5, 7, 4);
        dc.setColor(ACCENT_LT, ACCENT_LT);
        dc.fillCircle(x, y - 6, 5);
        dc.fillEllipse(x, y + 6, 9, 5);
    }

    function heart(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, color);
        var r = s / 4;
        dc.fillCircle(x - r, y - r / 2, r);
        dc.fillCircle(x + r, y - r / 2, r);
        dc.fillPolygon([[x - 2 * r, y - r / 4], [x + 2 * r, y - r / 4], [x, y + 2 * r - 1]]);
    }

    function drop(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, color);
        var r = s * 3 / 10;
        dc.fillCircle(x, y + r / 2, r);
        dc.fillPolygon([[x - r, y + r / 2], [x + r, y + r / 2], [x, y - s / 2]]);
    }

    function battery(dc as Dc, x as Number, y as Number, s as Number, pct as Numeric?) as Void {
        var w = s * 6 / 10;
        var h = s;
        var color = pct == null ? DIM : (pct < 20 ? DANGER : OK);
        dc.setColor(color, color);
        dc.fillRectangle(x - w / 4, y - h / 2 - 2, w / 2, 3);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(x - w / 2, y - h / 2, w, h, 2);
        dc.setPenWidth(1);
        if (pct != null) {
            var fill = ((h - 4) * pct.toFloat() / 100).toNumber();
            dc.fillRectangle(x - w / 2 + 2, y + h / 2 - 2 - fill, w - 4, fill);
        }
    }

    function chevronLeft(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, color);
        dc.setPenWidth(3);
        dc.drawLine(x + 5, y - 8, x - 3, y);
        dc.drawLine(x - 3, y, x + 5, y + 8);
        dc.setPenWidth(1);
    }

    // Red warning triangle with an exclamation mark.
    function warning(dc as Dc, x as Number, y as Number, s as Number) as Void {
        dc.setColor(DANGER, DANGER);
        dc.fillPolygon([[x, y - s / 2], [x + s * 6 / 10, y + s / 2], [x - s * 6 / 10, y + s / 2]]);
        dc.setColor(TEXT, TEXT);
        dc.fillRectangle(x - 2, y - s / 6, 4, s * 4 / 10);
        dc.fillCircle(x, y + s * 3 / 10, 2);
    }

    // Big ring with a check mark (ok) or an exclamation mark (help).
    function badge(dc as Dc, x as Number, y as Number, r as Number, good as Boolean) as Void {
        var color = good ? OK : DANGER;
        var shade = good ? OK_DK : DANGER_DK;
        dc.setColor(shade, shade);
        dc.fillCircle(x, y, r + 10);
        dc.setColor(BG, BG);
        dc.fillCircle(x, y, r - 3);
        dc.setColor(color, color);
        dc.setPenWidth(7);
        dc.drawCircle(x, y, r);
        dc.setColor(TEXT, TEXT);
        if (good) {
            dc.setPenWidth(8);
            dc.drawLine(x - r * 4 / 10, y, x - r / 10, y + r * 3 / 10);
            dc.drawLine(x - r / 10, y + r * 3 / 10, x + r * 45 / 100, y - r * 3 / 10);
        } else {
            dc.fillRoundedRectangle(x - 4, y - r / 2, 8, r * 6 / 10, 3);
            dc.fillCircle(x, y + r * 4 / 10, 5);
        }
        dc.setPenWidth(1);
    }

    // Navigation arrow pointing at `deg` (0 = up, clockwise), two-tone like a
    // folded paper arrow.
    function arrow(dc as Dc, x as Number, y as Number, size as Number, deg as Float) as Void {
        var tip = rotate(0, -size, deg);
        var left = rotate(-size * 7 / 10, size * 7 / 10, deg);
        var right = rotate(size * 7 / 10, size * 7 / 10, deg);
        var notch = rotate(0, size * 3 / 10, deg);
        dc.setColor(ACCENT_LT, ACCENT_LT);
        dc.fillPolygon([[x + tip[0], y + tip[1]], [x + notch[0], y + notch[1]], [x + left[0], y + left[1]]]);
        dc.setColor(ACCENT_DK, ACCENT_DK);
        dc.fillPolygon([[x + tip[0], y + tip[1]], [x + right[0], y + right[1]], [x + notch[0], y + notch[1]]]);
    }

    // A point (px, py) rotated clockwise by deg around the origin.
    function rotate(px as Numeric, py as Numeric, deg as Float) as Array<Number> {
        var a = Math.toRadians(deg);
        var c = Math.cos(a);
        var s = Math.sin(a);
        return [(px * c - py * s).toNumber(), (px * s + py * c).toNumber()] as Array<Number>;
    }

    // A point on a circle at compass bearing deg (0 = up, clockwise).
    function polar(cx as Number, cy as Number, r as Numeric, deg as Float) as Array<Number> {
        var a = Math.toRadians(deg);
        return [(cx + r * Math.sin(a)).toNumber(), (cy - r * Math.cos(a)).toNumber()] as Array<Number>;
    }

    // A rounded button, filled when focused.
    function button(dc as Dc, x as Number, y as Number, w as Number, h as Number, label as String,
            focused as Boolean, fill as Number) as Void {
        dc.setColor(focused ? fill : CARD, focused ? fill : CARD);
        dc.fillRoundedRectangle(x, y, w, h, h / 2);
        if (focused) {
            dc.setColor(ACCENT_LT, ACCENT_LT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x, y, w, h, h / 2);
            dc.setPenWidth(1);
        }
        text(dc, x + w / 2, y + h / 2, Graphics.FONT_XTINY, label, TEXT);
    }

    // ---- formatting ---------------------------------------------------------

    function distance(m as Numeric?) as String {
        if (m == null) {
            return "--";
        }
        if (m < 1000) {
            return m.toNumber() + " m";
        }
        return (m / 1000.0).format("%.1f") + " km";
    }

    function inRect(x as Number, y as Number, r as Array<Number>) as Boolean {
        return x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3];
    }
}
