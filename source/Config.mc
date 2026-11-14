import Toybox.Lang;

// Server addresses and shared constants. Pick Local/Shared from the watch menu.
module Config {
    // Your own server (`cd server && npm start`). In the simulator, untick
    // Settings > "Use Device HTTPS Requirements" so plain http works.
    const LOCAL_URL = "http://localhost:3000";

    // The team's ngrok static domain. Set it once and commit it.
    const SHARED_URL = "https://REPLACE-ME.ngrok-free.app";

    const POLL_MS = 5000;

    // Run the API self-test as soon as the app starts (handy with monkeydo).
    const AUTO_SELF_TEST = false;

    const MEMBER_IDS = ["dad", "kid", "mom", "grandpa"] as Array<String>;
}
