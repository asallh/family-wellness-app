import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// What the screens read: the rest of the family, where I am and which way I
// face, plus the events that pop up a screen. Every 5 s it posts my telemetry,
// fetches /family, then my inbox, one request after another through the Api
// queue. It uses the Tester's identity, server and sensor readings.
class FamilyState {
    var members as Array<Dictionary> = [] as Array<Dictionary>; // everyone but me
    var connected as Boolean = false;
    var lastError as String? = null;

    private var _tester as Tester;
    private var _timer as Timer.Timer?;
    private var _meFromServer as Dictionary? = null;
    private var _seen as Dictionary = {} as Dictionary;
    private var _queue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _modalOpen as Boolean = false;

    function initialize(tester as Tester) {
        _tester = tester;
    }

    function myId() as String {
        return _tester.myId;
    }

    function start() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:poll), Config.POLL_MS, true);
        poll();
    }

    function stop() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    // ---- polling ------------------------------------------------------------

    function poll() as Void {
        if (_tester.api.pending() > 2) {
            return;
        }
        _tester.api.post("/members/" + myId() + "/telemetry", _tester.buildTelemetry(), null);
        _tester.api.get("/family", method(:onFamily));
        _tester.api.get("/members/" + myId() + "/inbox", method(:onInbox));
    }

    function onFamily(code as Number, data) as Void {
        connected = code == 200 && data instanceof Array;
        if (!connected) {
            lastError = "Error " + code;
            WatchUi.requestUpdate();
            return;
        }
        lastError = null;
        var others = [] as Array<Dictionary>;
        for (var i = 0; i < data.size(); i++) {
            var m = data[i] as Dictionary;
            if (myId().equals(m["id"])) {
                _meFromServer = m;
            } else {
                others.add(m);
            }
        }
        members = others;
        WatchUi.requestUpdate();
    }

    function onInbox(code as Number, data) as Void {
        if (code != 200 || !(data instanceof Array)) {
            return;
        }
        for (var i = 0; i < data.size(); i++) {
            var ev = data[i] as Dictionary;
            var id = ev["eventId"] as String;
            if (_seen.hasKey(id)) {
                continue;
            }
            _seen[id] = true;
            _queue.add(ev);
        }
        showNext();
    }

    // ---- event screens ------------------------------------------------------
    // One event screen at a time. Each calls modalClosed() when it goes away,
    // and the next queued event shows.

    function showNext() as Void {
        if (_modalOpen || _queue.size() == 0) {
            return;
        }
        var ev = _queue[0];
        _queue = _queue.slice(1, null);
        showEvent(ev);
    }

    function showEvent(ev as Dictionary) as Void {
        var type = ev["type"] as String;
        _modalOpen = true;
        if (type.equals("checkin")) {
            vibrate(2);
            var view = new CheckinView(ev);
            WatchUi.pushView(view, new CheckinDelegate(view), WatchUi.SLIDE_UP);
        } else if (type.equals("checkin_reply")) {
            vibrate(1);
            ack(ev, "seen");
            var response = ev["response"];
            var name = ev["fromName"] as String;
            if ("ok".equals(response)) {
                pushMessage(true, name + " is OK", "Replied to your check-in");
            } else if ("no".equals(response)) {
                pushMessage(false, name + " is not OK", "Family has been alerted");
            } else {
                pushMessage(false, name + " needs help", "Family has been alerted");
            }
        } else {
            vibrate(3);
            var alert = new AlertView(ev);
            WatchUi.pushView(alert, new AlertDelegate(alert), WatchUi.SLIDE_UP);
        }
    }

    // A short confirmation screen that closes itself.
    function pushMessage(good as Boolean, title as String, subtitle as String) as Void {
        _modalOpen = true;
        var view = new MessageView(good, title, subtitle);
        WatchUi.pushView(view, new MessageDelegate(view), WatchUi.SLIDE_UP);
    }

    function modalClosed() as Void {
        _modalOpen = false;
        showNext();
    }

    // ---- actions ------------------------------------------------------------

    function sendCheckin(targetId as String) as Void {
        _tester.api.post("/members/" + targetId + "/checkin", { "from" => myId() }, null);
    }

    function sendSos(type as String) as Void {
        var body = { "type" => type } as Dictionary;
        var pos = myPosition();
        if (pos != null) {
            body["lat"] = pos[0];
            body["lon"] = pos[1];
        }
        _tester.api.post("/members/" + myId() + "/sos", body, null);
    }

    // Answers a check-in ("ok", "no" or "help") and confirms only once the
    // server has it, so the screen never claims a reply that wasn't sent.
    private var _answer as Dictionary? = null;

    function answerCheckin(ev as Dictionary, response as String) as Void {
        _answer = { "name" => ev["fromName"], "response" => response };
        _modalOpen = true; // hold other events until the confirmation shows
        var id = ev["eventId"] as String;
        if (id.find("preview") == 0) {
            onAnswered(200, { "ok" => true });
            return;
        }
        _tester.api.post("/events/" + id + "/ack", { "by" => myId(), "response" => response }, method(:onAnswered));
    }

    function onAnswered(code as Number, data) as Void {
        var a = _answer;
        _answer = null;
        if (a == null) {
            return;
        }
        var name = a["name"] as String;
        var response = a["response"] as String;
        if (code != 200) {
            pushMessage(false, "Reply not sent", code < 0 ? "No connection to the server" : "Server error " + code);
        } else if (data instanceof Dictionary && data["late"] == true) {
            pushMessage(false, "Too late to answer", "Family was already alerted");
        } else if (response.equals("ok")) {
            pushMessage(true, "Reply sent", "Told " + name + " you're OK");
        } else if (response.equals("no")) {
            pushMessage(false, "Told " + name, "You're not OK. Family alerted");
        } else {
            pushMessage(false, "Help requested", "Family has been alerted");
        }
    }

    // Preview events (from the menu) have no server id, so nothing to ack.
    function ack(ev as Dictionary, response as String) as Void {
        var id = ev["eventId"] as String;
        if (id.find("preview") == 0) {
            return;
        }
        _tester.api.post("/events/" + id + "/ack", { "by" => myId(), "response" => response }, null);
    }

    function vibrate(pulses as Number) as Void {
        if (!(Attention has :vibrate)) {
            return;
        }
        var profile = [] as Array<Attention.VibeProfile>;
        for (var i = 0; i < pulses; i++) {
            profile.add(new Attention.VibeProfile(100, 300));
            profile.add(new Attention.VibeProfile(0, 150));
        }
        Attention.vibrate(profile);
    }

    // ---- geometry -----------------------------------------------------------

    function member(id as String?) as Dictionary? {
        for (var i = 0; i < members.size(); i++) {
            if ((members[i]["id"] as String).equals(id)) {
                return members[i];
            }
        }
        return null;
    }

    // True when the data feeder has pinned this field for me on the server.
    function pinnedForMe(field as String) as Boolean {
        var mine = _meFromServer;
        if (mine == null || !(mine["pinned"] instanceof Array)) {
            return false;
        }
        return (mine["pinned"] as Array).indexOf(field) >= 0;
    }

    // Where I am. A position pinned in the data feeder wins, so my own arrows
    // and distances match what the other watch sees. Otherwise my GPS fix, or
    // else the position the server has for me (set with `demo.sh move`).
    function myPosition() as Array<Double>? {
        var here = _meFromServer;
        if (pinnedForMe("lat") && here != null && here["lat"] != null && here["lon"] != null) {
            return [(here["lat"] as Numeric).toDouble(), (here["lon"] as Numeric).toDouble()] as Array<Double>;
        }
        var info = Position.getInfo();
        if (info.position != null && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            var deg = info.position.toDegrees();
            if (deg[0] <= 90 && deg[0] >= -90 && deg[1] < 180) {
                return deg;
            }
        }
        if (here != null && here["lat"] != null && here["lon"] != null) {
            return [(here["lat"] as Numeric).toDouble(), (here["lon"] as Numeric).toDouble()] as Array<Double>;
        }
        return null;
    }

    // Which way the watch faces, in degrees clockwise from north. A heading
    // pinned in the data feeder wins (the simulator's compass is stuck on
    // north), then the compass, then the GPS course.
    function myHeading() as Float {
        var mine = _meFromServer;
        if (pinnedForMe("heading") && mine != null && mine["heading"] != null) {
            return normalizeDeg((mine["heading"] as Numeric).toFloat());
        }
        var h = Sensor.getInfo().heading;
        if (h == null) {
            h = Position.getInfo().heading;
        }
        if (h == null) {
            return 0.0;
        }
        return normalizeDeg(Math.toDegrees(h).toFloat());
    }

    function normalizeDeg(deg as Float) as Float {
        while (deg < 0) { deg += 360.0; }
        while (deg >= 360) { deg -= 360.0; }
        return deg;
    }

    // Metres from me to a lat/lon, or null without positions.
    function distanceTo(lat, lon) as Float? {
        var here = myPosition();
        if (here == null || lat == null || lon == null) {
            return null;
        }
        var r = 6371000.0;
        var p1 = Math.toRadians(here[0]);
        var p2 = Math.toRadians(lat.toDouble());
        var dp = p2 - p1;
        var dl = Math.toRadians(lon.toDouble() - here[1]);
        var a = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        return (2 * r * Math.asin(Math.sqrt(a))).toFloat();
    }

    // Compass bearing from me to a lat/lon, in degrees clockwise from north.
    function bearingTo(lat, lon) as Float? {
        var here = myPosition();
        if (here == null || lat == null || lon == null) {
            return null;
        }
        var p1 = Math.toRadians(here[0]);
        var p2 = Math.toRadians(lat.toDouble());
        var dl = Math.toRadians(lon.toDouble() - here[1]);
        var y = Math.sin(dl) * Math.cos(p2);
        var x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        var deg = Math.toDegrees(Math.atan2(y, x)).toFloat();
        return deg < 0 ? deg + 360.0 : deg;
    }

    // Where the arrow should point on screen: the bearing minus my heading.
    function arrowAngle(lat, lon) as Float? {
        var b = bearingTo(lat, lon);
        return b == null ? null : normalizeDeg(b - myHeading());
    }

    // Why there's no arrow to a member, or null when there can be one.
    function noArrowReason(m as Dictionary?) as String? {
        if (myPosition() == null) {
            return "No GPS fix";
        }
        if (m == null || m["lat"] == null || m["lon"] == null) {
            return "No location yet";
        }
        var d = distanceTo(m["lat"], m["lon"]);
        if (d != null && d < 10) {
            return "Right here";
        }
        return null;
    }
}
