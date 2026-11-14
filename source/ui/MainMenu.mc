import Toybox.Lang;
import Toybox.WatchUi;

// The menu from the family list (MENU, or START with nobody listed). The same
// on every watch.
function openMainMenu() as Void {
    var menu = new WatchUi.Menu2({ :title => "Family" });
    menu.addItem(new WatchUi.MenuItem("SOS", "Alert the family", :sos, null));
    menu.addItem(new WatchUi.MenuItem("Preview screens", "Sample alerts", :preview, null));
    menu.addItem(new WatchUi.MenuItem("API tester", "I am " + getTester().myId, :tester, null));
    WatchUi.pushView(menu, new MainMenuDelegate(), WatchUi.SLIDE_UP);
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :sos) {
            var confirm = new WatchUi.Menu2({ :title => "Send SOS?" });
            confirm.addItem(new WatchUi.MenuItem("Yes, send SOS", "Alerts everyone", :yes, null));
            confirm.addItem(new WatchUi.MenuItem("Cancel", null, :no, null));
            WatchUi.pushView(confirm, new SosConfirmDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :preview) {
            openPreviewMenu();
        } else if (id == :tester) {
            WatchUi.pushView(new family_wellnessView(), new family_wellnessDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

class SosConfirmDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        // Close the confirmation and the main menu.
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (item.getId() == :yes) {
            var s = getState();
            s.sendSos("manual");
            s.pushMessage(false, "SOS sent", "Your family has been alerted");
        }
    }
}

// ---- preview: every event screen with sample data, no server needed ----------

function openPreviewMenu() as Void {
    var menu = new WatchUi.Menu2({ :title => "Preview" });
    menu.addItem(new WatchUi.MenuItem("Check-in", "Are you OK?", :checkin, null));
    menu.addItem(new WatchUi.MenuItem("Reply: OK", "Message received", :replyOk, null));
    menu.addItem(new WatchUi.MenuItem("Reply: help", "Needs help", :replyHelp, null));
    menu.addItem(new WatchUi.MenuItem("Fall alert", "You're closest", :fall, null));
    menu.addItem(new WatchUi.MenuItem("SOS alert", "No reply", :sos, null));
    menu.addItem(new WatchUi.MenuItem("Health alert", "High HR", :health, null));
    WatchUi.pushView(menu, new PreviewMenuDelegate(), WatchUi.SLIDE_LEFT);
}

class PreviewMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var ev = previewEvent("grandpa", "Grandpa");
        if (id == :checkin) {
            ev["type"] = "checkin";
            ev["expiresInSec"] = 30;
        } else if (id == :replyOk || id == :replyHelp) {
            ev["type"] = "checkin_reply";
            ev["response"] = id == :replyOk ? "ok" : "help";
        } else if (id == :fall) {
            ev["type"] = "fall";
            ev["rank"] = 1;
        } else if (id == :sos) {
            ev = previewEvent("grandpa", "Grandpa");
            ev["type"] = "sos";
            ev["reason"] = "checkin_timeout";
            ev["rank"] = 2;
        } else {
            ev["type"] = "health";
            ev["reason"] = "hr_high";
            ev["value"] = 162;
        }
        getState().showEvent(ev);
    }
}

// A sample event from a member, placed where the server has them (if known).
function previewEvent(from as String, name as String) as Dictionary {
    var m = getState().member(from);
    return {
        "eventId" => "preview",
        "from" => from,
        "fromName" => name,
        "lat" => m == null ? null : m["lat"],
        "lon" => m == null ? null : m["lon"],
        "distanceM" => 1100,
        "rank" => null,
        "response" => null,
        "reason" => null,
        "value" => null
    } as Dictionary;
}
