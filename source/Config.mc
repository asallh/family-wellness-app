import Toybox.Lang;

// Server addresses and shared constants.
module Config {
    // Your own server (`./start.sh` starts it). In the simulator, untick
    // Settings > "Use Device HTTPS Requirements" so plain http works.
    const LOCAL_URL = "http://localhost:3000";

    // The team's ngrok static domain. Set it once and commit it.
    const SHARED_URL = "https://REPLACE-ME.ngrok-free.app";

    const POLL_MS = 5000;

    // Run the API self-test as soon as the app starts (handy with monkeydo).
    const AUTO_SELF_TEST = false;

    // The family: the two watches.
    const MEMBER_IDS = ["mom", "son"] as Array<String>;

    // Who this watch is and which server it uses, when built by ./start.sh.
    // start.sh replaces these two functions with generated ones (see
    // bin/launch/Launch.mc). A plain VS Code build keeps these defaults, and
    // the watch falls back to the identity and server picked in its menu.
    (:notLaunched)
    function launchIdentity() as String? {
        return null;
    }

    (:notLaunched)
    function launchServerUrl() as String? {
        return null;
    }
}
