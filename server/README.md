# Family Wellness server

The in-memory API that connects the watches. It implements the API contract in [PLAN.md](../PLAN.md). There's no database: a restart (or `POST /debug/reset`) is a clean slate.

```bash
npm install
npm start          # http://localhost:3000 (PORT=xxxx to change)
npm run dev        # restarts on file changes
npm test           # endpoint + rule tests, uses a fake clock
LOG=verbose npm start   # also log every GET poll (normally only writes are logged)
```

Drive any member from the terminal with [`demo.sh`](demo.sh). Run `./demo.sh` with no arguments for the full list. Point it at the shared server with `FAMILY_API=https://<team-domain>.ngrok-free.app`.

## Testing from the watch

For now, the watch app is an **API tester**. It's a stand-in until the real screens exist, and lives in `source/Tester.mc`, `source/Api.mc` and `source/Config.mc`.

1. Start the server, then in the simulator untick **Settings → Use Device HTTPS Requirements**. Otherwise every request fails with `-1001`.
2. Run the app (F5 in VS Code, or `monkeydo bin/app.prg fenix7pro`), and press **START** or **MENU** for the tester menu.
3. **Run self-test** sends telemetry, gets the family and inbox, answers a waiting check-in, and checks on Mom. It prints `PASS`/`FAIL` per step to the console. Run `./server/demo.sh checkin kid dad` first so there's a check-in to answer.
4. The other menu items fire one request each: auto poll (every 5 s), check on…, answer OK/HELP, ack, SOS, fall, identity, local/shared server, and reset. Each request and response shows in the VS Code Debug Console (or the `monkeydo` output).

Set `Config.AUTO_SELF_TEST = true` to run the self-test on launch with no button presses.

## API reference

Base URL: `http://localhost:3000` locally, or the team's ngrok domain in shared mode. Every request and response body is JSON. Send `Content-Type: application/json` on POSTs.

Members are fixed: `dad`, `kid`, `mom`, `grandpa`. Any member can call any endpoint, because every feature works both ways.

| Method | Path | What it does |
|---|---|---|
| GET | [`/`](#get-) | Health check |
| POST | [`/members/:id/telemetry`](#post-membersidtelemetry) | A watch reports its sensor readings |
| GET | [`/family`](#get-family) | Everyone's latest vitals, position and status |
| GET | [`/members/:id/inbox`](#get-membersidinbox) | Events waiting for a member |
| POST | [`/members/:id/sos`](#post-membersidsos) | `:id` needs help (SOS button or a detected fall) |
| POST | [`/members/:id/checkin`](#post-membersidcheckin) | Ask `:id` "Are you OK?" |
| POST | [`/events/:eventId/ack`](#post-eventseventidack) | Answer a check-in or dismiss an alert |
| POST | [`/debug/reset`](#post-debugreset) | Clear events and statuses before a demo run |

### `GET /`

```json
{"ok": true, "service": "family-wellness"}
```

### `POST /members/:id/telemetry`

The watch sends this every 5 s. Every field is optional. Leave out a sensor with no reading, or send `null`, and the server keeps its last value.

```json
{"hr": 72, "spo2": 98, "temp": 31.5, "lat": 38.86, "lon": -94.8, "heading": 90, "alt": 300, "battery": 80}
```

| Field | Unit |
|---|---|
| `hr` | bpm |
| `spo2` | % |
| `temp` | °C (skin) |
| `lat`, `lon` | degrees. A no-fix position like `(180, 180)` is ignored. |
| `heading` | degrees, 0–360 |
| `alt` | metres |
| `battery` | % |

**Returns** `{"ok": true}`.

**Side effect:** when a reading crosses a health threshold (HR > 150, HR < 40, SpO₂ < 90), everyone else gets a `health` event. It fires once per crossing, and again only after the value recovers and crosses again.

### `GET /family`

Returns **every** member, including the watch that's asking, so filter out your own `id`.

```json
[
  {"id": "dad", "name": "Dad", "hr": 72, "spo2": 98, "temp": 31.5, "alt": 300, "battery": 80,
   "heading": 90, "lat": 38.86, "lon": -94.8, "status": "ok", "lastSeen": 0, "seeded": false},
  {"id": "mom", "name": "Mom", "hr": 70, "spo2": 98, "temp": 32.4, "alt": 310, "battery": 76,
   "heading": null, "lat": 38.860894, "lon": -94.802307, "status": "ok", "lastSeen": 0, "seeded": true}
]
```

- `status` is the first that applies:
  - `sos`: raised an SOS in the last 2 minutes
  - `stale`: no telemetry for 30 s, or never reported
  - `alert`: a vital is past a threshold
  - `ok`
- `lastSeen` is **seconds since the last telemetry**, not a timestamp (small numbers are easier on the watch). It's `null` if the watch never reported, and `0` for seeded members.
- A sensor that never reported is `null`.

### `GET /members/:id/inbox`

Events for `:id` that haven't been acked yet, oldest first. The same event comes back on every poll until it's acked, so **remember the `eventId`s you've already shown** and only vibrate for new ones.

```json
[
  {"eventId": "e3", "type": "sos", "from": "grandpa", "fromName": "Grandpa",
   "lat": 38.865835, "lon": -94.793078, "distanceM": 883, "rank": 1,
   "response": null, "reason": null, "value": null, "ageSec": 0, "expiresInSec": null},
  {"eventId": "e4", "type": "health", "from": "kid", "fromName": "Kid",
   "lat": 38.8555, "lon": -94.8, "distanceM": 500, "rank": 1,
   "response": null, "reason": "hr_high", "value": 162, "ageSec": 0, "expiresInSec": null}
]
```

| `type` | Meaning | Fields that matter |
|---|---|---|
| `checkin` | `from` is asking "Are you OK?" | `expiresInSec`: seconds left before it escalates (use it for the countdown) |
| `checkin_reply` | `from` answered your check-in | `response`: `ok` or `help` |
| `sos` | `from` needs help | `reason`: `null` (SOS button), `checkin_help`, or `checkin_timeout` |
| `fall` | A fall was detected on `from`'s watch | |
| `health` | `from`'s vitals crossed a threshold | `reason`: `hr_high` / `hr_low` / `spo2_low`, and `value`: the reading |

Common fields:
- `lat`/`lon`: where `from` was when the event was sent. Point the arrow there.
- `distanceM`: metres from `from` to you at that moment.
- `rank`: on `sos`/`fall`/`health`, your place among the **live watches** by distance (1 = closest, so show "(you're closest)"). Seeded or stale members get `null`, so rank 1 always goes to someone who can respond.
- `ageSec`: how long ago the event was created.

### `POST /members/:id/sos`

`:id` is the person in trouble. The body is optional.

```json
{"type": "manual", "lat": 38.85, "lon": -94.8}
```

- `type`: `"manual"` (the SOS button, the default) becomes an `sos` event. `"fall"` becomes a `fall` event.
- `lat`/`lon`: optional. Without them, the server uses the member's last telemetry position.

**Returns** `{"ok": true, "eventId": "e3", "notified": 3}`. Every other member gets the event, and `:id` shows `status: "sos"` for 2 minutes.

### `POST /members/:id/checkin`

Ask `:id` "Are you OK?". Both directions work: Dad can check on Kid, and Kid can check on Dad.

```json
{"from": "dad"}
```

**Returns** `{"ok": true, "eventId": "e1"}`. Then one of these happens:
- **`:id` acks with `ok` or `help`:** the asker gets a `checkin_reply` with that `response`.
- **`help`:** an `sos` from `:id` (reason `checkin_help`) also goes to everyone.
- **No answer within 30 s:** it escalates to an `sos` from `:id` (reason `checkin_timeout`). Mom and Grandpa never answer, so checking on them demos this.

### `POST /events/:eventId/ack`

```json
{"by": "kid", "response": "ok"}
```

- `by`: the member answering. They must be a recipient of the event.
- `response`:
  - `"ok"` or `"help"` answers a check-in.
  - `"seen"` (the default) just dismisses the event. On a check-in, `"seen"` hides it without answering, so it still escalates at 30 s.

**Returns** `{"ok": true}`, and the event leaves `by`'s inbox.

### `POST /debug/reset`

Clears every event, check-in, SOS and alert, and restores Mom and Grandpa. Live watches keep their last telemetry. **Returns** `{"ok": true}`.

### Errors

Errors are always JSON, so the watch can read them:

| Code | When | Example |
|---|---|---|
| 404 | Unknown member, event or path | `{"ok": false, "error": "Unknown member \"bob\". Known: dad, kid, mom, grandpa"}` |
| 400 | Bad input | `{"ok": false, "error": "\"hr\" must be a number or null"}`, `{"ok": false, "error": "A member can't check in on themselves"}` |

On the watch, a **negative** response code means the request never reached the server. For example, `-1001` means the simulator is still requiring HTTPS.

### Seeded members

Mom and Grandpa aren't real watches:
- **Position:** they sit a few hundred metres from the live watches' average position, so distances look realistic wherever the simulators' GPS is set. Before any watch reports, they sit around `SEED_LAT`/`SEED_LON` (default 38.8554, -94.7995).
- **Behaviour:** they're never stale, their HR drifts ±2 bpm, and they never answer check-ins.
- **Driving them:** use `demo.sh` (`hr`, `spo2`, `move`, `sos`, `fall`, `checkin`).
