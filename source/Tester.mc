import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// API tester: fires each server request from the menu, prints everything to
// the console, and keeps a short summary for the screen. A stand-in until the
// real FamilyState and screens exist.
class Tester {
    var myId as String;
    var useShared as Boolean;
    // True when ./start.sh baked in the identity and server for this build.
    var launched as Boolean;
    var polling as Boolean = false;
    private var _serverUrl as String;
    var status as String = "Press START for menu";
    var detail as String = "";
    var api as Api;

    private var _inbox as Array = [] as Array;
    private var _seen as Dictionary = {} as Dictionary;
    private var _timer as Timer.Timer?;

    // Self-test progress: -1 when not running.
    private var _testStep as Number = -1;
    private var _testPassed as Number = 0;
    private var _testRun as Number = 0;
    private var _testCheckin as Dictionary? = null;

    function initialize() {
        useShared = Application.Storage.getValue("useShared") == true;
        var launchId = Config.launchIdentity();
        var launchUrl = Config.launchServerUrl();
        launched = launchId != null;

        // start.sh's choice wins; otherwise use what was picked in the menu.
        var savedId = Application.Storage.getValue("myId");
        myId = launchId != null ? launchId : (savedId instanceof String ? savedId : "mom");
        _serverUrl = launchUrl != null ? launchUrl : (useShared ? Config.SHARED_URL : Config.LOCAL_URL);

        api = new Api(_serverUrl);
        System.println("API tester ready. I am '" + myId + "', server " + _serverUrl
            + (launched ? " (set by start.sh)" : " (set in the menu)"));
    }

    function serverUrl() as String {
        return _serverUrl;
    }

    // The server without the http(s):// prefix, for the screen.
    function serverHost() as String {
        var url = _serverUrl;
        var at = url.find("://");
        return at == null ? url : url.substring(at + 3, url.length()) as String;
    }

    // ---- settings -----------------------------------------------------------

    function setIdentity(id as String) as Void {
        myId = id;
        Application.Storage.setValue("myId", id);
        _seen = {} as Dictionary;
        _inbox = [] as Array;
        show("I am now " + id, "");
    }

    function toggleServer() as Void {
        useShared = !useShared;
        Application.Storage.setValue("useShared", useShared);
        _serverUrl = useShared ? Config.SHARED_URL : Config.LOCAL_URL;
        api.setBaseUrl(_serverUrl);
        System.println("Server switched to " + _serverUrl);
        show("Server: " + (useShared ? "shared" : "local"), serverHost());
    }

    function togglePolling() as Void {
        polling = !polling;
        if (polling) {
            _timer = new Timer.Timer();
            _timer.start(method(:pollOnce), Config.POLL_MS, true);
            pollOnce();
            show("Polling every " + (Config.POLL_MS / 1000) + " s", "telemetry + inbox");
        } else {
            stop();
            show("Polling off", "");
        }
    }

    function stop() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    // ---- actions ------------------------------------------------------------

    function pollOnce() as Void {
        if (api.pending() > 2) {
            System.println("(skipping poll: previous requests still in flight)");
            return;
        }
        sendTelemetry();
        getInbox();
    }

    function sendTelemetry() as Void {
        var body = buildTelemetry();
        api.post("/members/" + myId + "/telemetry", body, method(:onSimple));
        show("Sent telemetry", summarizeTelemetry(body));
    }

    function getFamily() as Void {
        show("GET /family", "...");
        api.get("/family", method(:onFamily));
    }

    function getInbox() as Void {
        api.get("/members/" + myId + "/inbox", method(:onInbox));
    }

    function sos(type as String) as Void {
        var body = { "type" => type } as Dictionary;
        var pos = currentPosition();
        if (pos != null) {
            body["lat"] = pos[0];
            body["lon"] = pos[1];
        }
        show(type.equals("fall") ? "Sent FALL" : "Sent SOS", "...");
        api.post("/members/" + myId + "/sos", body, method(:onSimple));
    }

    function checkOn(targetId as String) as Void {
        show("Check on " + targetId, "...");
        api.post("/members/" + targetId + "/checkin", { "from" => myId }, method(:onSimple));
    }

    // Answers the newest unanswered check-in in the last inbox we fetched.
    function answerCheckin(response as String) as Void {
        var ev = newest("checkin");
        if (ev == null) {
            show("No check-in to answer", "Get inbox first");
            return;
        }
        ack(ev, response);
    }

    // Marks the newest event of any other type as seen.
    function ackNewest() as Void {
        var ev = newest(null);
        if (ev == null) {
            show("Nothing to ack", "Get inbox first");
            return;
        }
        ack(ev, "seen");
    }

    function resetServer() as Void {
        show("Reset server", "...");
        _seen = {} as Dictionary;
        _inbox = [] as Array;
        api.post("/debug/reset", {} as Dictionary, method(:onSimple));
    }

    private function ack(ev as Dictionary, response as String) as Void {
        var id = ev["eventId"] as String;
        show("Ack " + id + ": " + response, "");
        api.post("/events/" + id + "/ack", { "by" => myId, "response" => response }, method(:onSimple));
        // Drop it locally so the next answer picks the next event.
        var kept = [] as Array;
        for (var i = 0; i < _inbox.size(); i++) {
            if (!(_inbox[i]["eventId"] as String).equals(id)) {
                kept.add(_inbox[i]);
            }
        }
        _inbox = kept;
    }

    private function newest(type as String?) as Dictionary? {
        for (var i = _inbox.size() - 1; i >= 0; i--) {
            var ev = _inbox[i] as Dictionary;
            var t = ev["type"] as String;
            if (type == null ? !t.equals("checkin") : t.equals(type)) {
                return ev;
            }
        }
        return null;
    }

    // ---- self-test ----------------------------------------------------------
    // Runs the main requests in order and prints PASS/FAIL for each. It answers
    // a waiting check-in if there is one, and checks on another member, so run
    // it against your local server rather than the shared one.

    function runSelfTest() as Void {
        _testStep = 0;
        _testPassed = 0;
        _testRun = 0;
        _testCheckin = null;
        System.println("=== SELF-TEST as '" + myId + "' against " + serverUrl());
        show("Self-test running", "watch the console");
        selfTestNext();
    }

    private function otherMember() as String {
        return myId.equals("son") ? "mom" : "son";
    }

    private function selfTestNext() as Void {
        if (_testStep == 0) {
            api.post("/members/" + myId + "/telemetry", buildTelemetry(), method(:onSelfTest));
        } else if (_testStep == 1) {
            api.get("/family", method(:onSelfTest));
        } else if (_testStep == 2) {
            api.get("/members/" + myId + "/inbox", method(:onSelfTest));
        } else if (_testStep == 3) {
            if (_testCheckin == null) {
                System.println("SELF-TEST answer check-in: SKIP (none waiting; try `server/demo.sh checkin " + otherMember() + " " + myId + "` first)");
                _testStep++;
                selfTestNext();
                return;
            }
            var id = _testCheckin["eventId"] as String;
            api.post("/events/" + id + "/ack", { "by" => myId, "response" => "ok" }, method(:onSelfTest));
        } else if (_testStep == 4) {
            // This pops a real "Are you OK?" on the other watch.
            api.post("/members/" + otherMember() + "/checkin", { "from" => myId }, method(:onSelfTest));
        } else {
            var summary = _testPassed + "/" + _testRun + " passed";
            System.println("=== SELF-TEST DONE: " + summary);
            _testStep = -1;
            show("Self-test: " + summary, _testPassed == _testRun ? "all good" : "see console");
        }
    }

    function onSelfTest(code as Number, data) as Void {
        var names = ["POST telemetry", "GET /family", "GET inbox", "answer check-in", "POST checkin"] as Array<String>;
        var ok = code == 200;
        if (_testStep == 1 || _testStep == 2) {
            ok = ok && data instanceof Array;
        }
        if (_testStep == 2 && ok) {
            _inbox = data as Array;
            for (var i = _inbox.size() - 1; i >= 0 && _testCheckin == null; i--) {
                if ((_inbox[i]["type"] as String).equals("checkin")) {
                    _testCheckin = _inbox[i] as Dictionary;
                }
            }
        }
        _testRun++;
        if (ok) {
            _testPassed++;
        }
        System.println("SELF-TEST " + names[_testStep] + ": " + (ok ? "PASS" : "FAIL") + " (" + code + ")");
        _testStep++;
        selfTestNext();
    }

    // ---- responses ----------------------------------------------------------

    function onSimple(code as Number, data) as Void {
        detail = code == 200 ? "OK " + code : "Error " + code + " " + errorText(data);
        WatchUi.requestUpdate();
    }

    function onFamily(code as Number, data) as Void {
        if (code != 200 || !(data instanceof Array)) {
            detail = "Error " + code + " " + errorText(data);
            WatchUi.requestUpdate();
            return;
        }
        var lines = "";
        for (var i = 0; i < data.size(); i++) {
            var m = data[i] as Dictionary;
            var line = m["id"] + " " + m["status"] + " hr=" + m["hr"] + " lastSeen=" + m["lastSeen"];
            System.println("   " + line + " @ " + m["lat"] + "," + m["lon"]);
            if (!(m["id"] as String).equals(myId)) {
                lines += m["name"] + " " + m["status"] + " " + m["hr"] + "\n";
            }
        }
        show(data.size() + " members", lines);
    }

    function onInbox(code as Number, data) as Void {
        if (code != 200 || !(data instanceof Array)) {
            detail = "Inbox error " + code + " " + errorText(data);
            WatchUi.requestUpdate();
            return;
        }
        _inbox = data;
        var fresh = 0;
        var latest = "";
        for (var i = 0; i < data.size(); i++) {
            var ev = data[i] as Dictionary;
            var id = ev["eventId"] as String;
            if (_seen.hasKey(id)) {
                continue;
            }
            _seen[id] = true;
            fresh++;
            latest = describe(ev);
            System.println("   NEW " + latest + "  " + ev);
        }
        if (fresh > 0) {
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(75, 400)]);
            }
            show(fresh + " new event" + (fresh == 1 ? "" : "s"), latest);
        } else if (!polling) {
            show("Inbox: " + data.size() + " waiting", data.size() > 0 ? describe(data[data.size() - 1] as Dictionary) : "empty");
        }
    }

    // ---- helpers ------------------------------------------------------------

    private function describe(ev as Dictionary) as String {
        var type = ev["type"] as String;
        var who = ev["fromName"];
        var s = type + " from " + who;
        if (type.equals("checkin_reply")) {
            s = who + " says " + ev["response"];
        } else if (type.equals("checkin")) {
            s = who + ": are you OK? (" + ev["expiresInSec"] + "s)";
        } else if (type.equals("health")) {
            s = who + " " + ev["reason"] + " " + ev["value"];
        }
        if (ev["distanceM"] != null && !type.equals("checkin_reply")) {
            s += " " + ev["distanceM"] + "m";
        }
        if (ev["rank"] == 1) {
            s += " (closest)";
        }
        return s;
    }

    private function errorText(data) as String {
        if (data instanceof Dictionary && data["error"] != null) {
            return data["error"].toString();
        }
        return data == null ? "" : data.toString();
    }

    private function show(newStatus as String, newDetail as String) as Void {
        status = newStatus;
        detail = newDetail;
        WatchUi.requestUpdate();
    }

    private function currentPosition() as Array<Double>? {
        var info = Position.getInfo();
        if (info.position == null || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return null;
        }
        var deg = info.position.toDegrees();
        // With no fix the simulator reports (180, 180), which isn't a real place.
        if (deg[0] > 90 || deg[0] < -90 || deg[1] >= 180) {
            return null;
        }
        return deg;
    }

    // Reads every sensor the plan uses. Missing readings are left out, so the
    // server keeps their last value.
    function buildTelemetry() as Dictionary {
        var t = {} as Dictionary;
        var info = Sensor.getInfo();
        if (info.heartRate != null) { t["hr"] = info.heartRate; }
        if (info has :oxygenSaturation && info.oxygenSaturation != null) { t["spo2"] = info.oxygenSaturation; }
        if (info.temperature != null) { t["temp"] = info.temperature; }
        if (info.altitude != null) { t["alt"] = info.altitude; }
        if (info.heading != null) {
            var deg = Math.toDegrees(info.heading);
            t["heading"] = deg < 0 ? deg + 360 : deg;
        }
        var pos = currentPosition();
        if (pos != null) {
            t["lat"] = pos[0];
            t["lon"] = pos[1];
        }
        t["battery"] = System.getSystemStats().battery;
        return t;
    }

    private function summarizeTelemetry(t as Dictionary) as String {
        var s = "hr " + (t.hasKey("hr") ? t["hr"] : "-");
        s += t.hasKey("lat") ? " gps ok" : " no gps";
        return s;
    }
}
