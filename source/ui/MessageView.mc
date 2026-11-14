import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// A big green check (or red "!") with a title and a line under it: check-in
// replies, and confirmations of what I just sent. Closes itself after 4 s, or
// on any button or tap.
class MessageView extends WatchUi.View {
    private var _good as Boolean;
    private var _title as String;
    private var _subtitle as String;
    private var _timer as Timer.Timer?;
    private var _closed as Boolean = false;

    function initialize(good as Boolean, title as String, subtitle as String) {
        View.initialize();
        _good = good;
        _title = title;
        _subtitle = subtitle;
    }

    function onShow() as Void {
        if (_timer == null && !_closed) {
            _timer = new Timer.Timer();
            _timer.start(method(:close), 4000, false);
        }
    }

    function onHide() as Void {
        // Something opened on top: don't pop it from under the user.
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function close() as Void {
        if (_closed) {
            return;
        }
        _closed = true;
        onHide();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        getState().modalClosed();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        Theme.clear(dc);
        // Badge centred at 100 (glow 48-152), title 178, subtitle 204.
        Theme.badge(dc, cx, h * 385 / 1000, w * 16 / 100, _good);
        Theme.line(dc, h * 685 / 1000, Graphics.FONT_SMALL, _title, Theme.TEXT);
        Theme.line(dc, h * 785 / 1000, Graphics.FONT_XTINY, _subtitle, Theme.MUTED);
    }
}

class MessageDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MessageView;

    function initialize(view as MessageView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.close();
        return true;
    }

    function onBack() as Boolean {
        _view.close();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.close();
        return true;
    }
}
