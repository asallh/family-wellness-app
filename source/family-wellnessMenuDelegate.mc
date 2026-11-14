import Toybox.Lang;
import Toybox.WatchUi;

// API tester menu: one item per server request.
function openTesterMenu() as Void {
    var t = getTester();
    var menu = new WatchUi.Menu2({ :title => "API tester" });
    menu.addItem(new WatchUi.MenuItem("Run self-test", "PASS/FAIL to console", :selfTest, null));
    menu.addItem(new WatchUi.MenuItem("Auto poll", t.polling ? "On: stop" : "Off: start (5 s)", :poll, null));
    menu.addItem(new WatchUi.MenuItem("Send telemetry", "POST telemetry", :telemetry, null));
    menu.addItem(new WatchUi.MenuItem("Get family", "GET /family", :family, null));
    menu.addItem(new WatchUi.MenuItem("Get inbox", "GET inbox", :inbox, null));
    menu.addItem(new WatchUi.MenuItem("Check on...", "Are you OK?", :checkin, null));
    menu.addItem(new WatchUi.MenuItem("Answer OK", "newest check-in", :answerOk, null));
    menu.addItem(new WatchUi.MenuItem("Answer HELP", "newest check-in", :answerHelp, null));
    menu.addItem(new WatchUi.MenuItem("Ack newest", "mark alert seen", :ackSeen, null));
    menu.addItem(new WatchUi.MenuItem("SOS", "POST sos manual", :sos, null));
    menu.addItem(new WatchUi.MenuItem("Simulate fall", "POST sos fall", :fall, null));
    menu.addItem(new WatchUi.MenuItem("I am", t.myId, :identity, null));
    menu.addItem(new WatchUi.MenuItem("Server", t.serverHost(), :server, null));
    menu.addItem(new WatchUi.MenuItem("Reset server", "POST /debug/reset", :reset, null));
    WatchUi.pushView(menu, new family_wellnessMenuDelegate(), WatchUi.SLIDE_UP);
}

function pushMemberPicker(title as String, action as Symbol, excludeId as String?) as Void {
    var menu = new WatchUi.Menu2({ :title => title });
    for (var i = 0; i < Config.MEMBER_IDS.size(); i++) {
        var id = Config.MEMBER_IDS[i];
        if (excludeId == null || !id.equals(excludeId)) {
            menu.addItem(new WatchUi.MenuItem(id, null, id, null));
        }
    }
    WatchUi.pushView(menu, new MemberPickDelegate(action), WatchUi.SLIDE_LEFT);
}

class family_wellnessMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var t = getTester();
        var id = item.getId();

        // These open a second menu; the main menu stays underneath.
        if (id == :checkin) {
            pushMemberPicker("Check on", :checkin, t.myId);
            return;
        }
        if (id == :identity) {
            pushMemberPicker("Who am I?", :identity, null);
            return;
        }

        // Everything else runs, then returns to the status screen.
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :selfTest) {
            t.runSelfTest();
        } else if (id == :poll) {
            t.togglePolling();
        } else if (id == :telemetry) {
            t.sendTelemetry();
        } else if (id == :family) {
            t.getFamily();
        } else if (id == :inbox) {
            t.getInbox();
        } else if (id == :answerOk) {
            t.answerCheckin("ok");
        } else if (id == :answerHelp) {
            t.answerCheckin("help");
        } else if (id == :ackSeen) {
            t.ackNewest();
        } else if (id == :sos) {
            t.sos("manual");
        } else if (id == :fall) {
            t.sos("fall");
        } else if (id == :server) {
            t.toggleServer();
        } else if (id == :reset) {
            t.resetServer();
        }
    }
}

class MemberPickDelegate extends WatchUi.Menu2InputDelegate {
    private var _action as Symbol;

    function initialize(action as Symbol) {
        Menu2InputDelegate.initialize();
        _action = action;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var memberId = item.getId() as String;
        // Close the picker and the main menu.
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var t = getTester();
        if (_action == :identity) {
            t.setIdentity(memberId);
        } else {
            t.checkOn(memberId);
        }
    }
}
