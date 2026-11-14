import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// API tester status screen: who I am, which server, and the last result.
// Full request/response detail goes to the console.
class family_wellnessView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var t = getTester();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.08, Graphics.FONT_XTINY, "API TESTER", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.17, Graphics.FONT_SMALL, "I am " + t.myId, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var mode = (t.useShared ? "shared" : "local") + (t.polling ? " | polling" : "");
        dc.drawText(cx, h * 0.29, Graphics.FONT_XTINY, mode, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.40, Graphics.FONT_TINY, t.status, Graphics.TEXT_JUSTIFY_CENTER);

        // Up to four lines of detail, cut to fit the round screen.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var lines = splitLines(t.detail, 4);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, h * (0.53 + 0.09 * i), Graphics.FONT_XTINY, fit(lines[i], 26), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function splitLines(text as String, max as Number) as Array<String> {
        var out = [] as Array<String>;
        var rest = text;
        while (rest.length() > 0 && out.size() < max) {
            var nl = rest.find("\n");
            if (nl == null) {
                out.add(rest);
                break;
            }
            out.add(rest.substring(0, nl) as String);
            rest = rest.substring(nl + 1, rest.length()) as String;
        }
        return out;
    }

    private function fit(s as String, maxChars as Number) as String {
        return s.length() <= maxChars ? s : (s.substring(0, maxChars - 1) as String) + "~";
    }
}
