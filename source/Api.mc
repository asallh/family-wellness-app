import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

// Talks to the Family Wellness server. Requests go out one at a time, because
// the watch only allows a few in flight, and every request and response is
// printed to the console.
class Api {
    private var _baseUrl as String;
    private var _queue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _current as Dictionary? = null;

    function initialize(baseUrl as String) {
        _baseUrl = baseUrl;
    }

    function setBaseUrl(url as String) as Void {
        _baseUrl = url;
    }

    function baseUrl() as String {
        return _baseUrl;
    }

    // onDone is called as onDone.invoke(responseCode, data).
    function get(path as String, onDone as Method?) as Void {
        enqueue(false, path, null, onDone);
    }

    function post(path as String, body as Dictionary, onDone as Method?) as Void {
        enqueue(true, path, body, onDone);
    }

    // A POST that goes ahead of queued polls (SOS, check-ins, answers), so the
    // wearer isn't kept waiting behind routine traffic.
    function postNow(path as String, body as Dictionary, onDone as Method?) as Void {
        _queue = [{ :isPost => true, :path => path, :body => body, :onDone => onDone }].addAll(_queue) as Array<Dictionary>;
        sendNext();
    }

    function pending() as Number {
        return _queue.size() + (_current == null ? 0 : 1);
    }

    private function enqueue(isPost as Boolean, path as String, body as Dictionary?, onDone as Method?) as Void {
        _queue.add({ :isPost => isPost, :path => path, :body => body, :onDone => onDone });
        sendNext();
    }

    private function sendNext() as Void {
        if (_current != null || _queue.size() == 0) {
            return;
        }
        var req = _queue[0];
        _queue = _queue.slice(1, null);
        _current = req;

        var isPost = req[:isPost] as Boolean;
        var path = req[:path] as String;
        var body = req[:body] as Dictionary?;
        var headers = { "ngrok-skip-browser-warning" => "1" } as Dictionary<String, String or Number>;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        if (isPost) {
            options[:method] = Communications.HTTP_REQUEST_METHOD_POST;
            headers["Content-Type"] = Communications.REQUEST_CONTENT_TYPE_JSON;
            System.println("-> POST " + path + " " + body);
        } else {
            System.println("-> GET " + path);
        }
        Communications.makeWebRequest(_baseUrl + path, isPost ? body : null, options, method(:onResponse));
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        var req = _current;
        _current = null;
        if (req != null) {
            System.println("<- " + code + " " + (req[:path] as String) + " " + data);
            if (code < 0) {
                System.println("   (negative code = the request never reached the server; check the URL, that the server is running, and the HTTPS setting)");
            }
            var onDone = req[:onDone] as Method?;
            if (onDone != null) {
                onDone.invoke(code, data);
            }
        }
        sendNext();
    }
}

// What a response code means, short enough for one line on the watch.
function describeCode(code as Number) as String {
    if (code == -104) { return "Phone not connected"; }
    if (code == -1001) { return "Server must use HTTPS"; }
    if (code == -300) { return "Server timed out"; }
    if (code == -400 || code == -402) { return "Bad server reply"; }
    if (code < 0) { return "Can't reach server (" + code + ")"; }
    if (code == 404) { return "Not on the server"; }
    return "Server error " + code;
}
