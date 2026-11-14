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

## Details the watch team should know

These are on top of the field list in PLAN.md. Nothing in the contract was renamed.

- **`GET /family`** returns *everyone*, including the calling watch. Filter out `myId` on the watch.
  - `lastSeen` is **seconds since the last telemetry** (a small integer, easy for Monkey C), not a timestamp. It's `null` if the watch never reported, and `0` for seeded members.
  - `seeded: true` marks Mom and Grandpa.
  - `heading` is included as well.
- **Seeded members** (Mom, Grandpa) sit a few hundred metres from the live watches' average position. That means distances look realistic wherever the simulators' GPS is set. Until a watch reports a position, they sit around `SEED_LAT`/`SEED_LON` (default 38.8554, -94.7995). They're never stale, their HR drifts ±2 bpm, and they never answer check-ins.
- **Inbox events** also carry:
  - `reason`: `hr_high` / `hr_low` / `spo2_low` for health events, and `checkin_timeout` / `checkin_help` for SOS events raised by a check-in
  - `value`: the reading that triggered a health event, e.g. 162
  - `ageSec`: how old the event is
  - `expiresInSec`: on check-ins, the seconds left before it escalates (use it for the countdown); `null` on other events
- **`rank`** only counts members whose watch is live (not seeded, not stale), so "(you're closest)" always goes to someone who can actually respond. Everyone else gets `rank: null`.
- **SOS body:** `type` is `"manual"` (becomes an `sos` event) or `"fall"` (becomes a `fall` event). `lat`/`lon` are optional; without them the server uses the last telemetry position.
- **Ack:** `response` defaults to `"seen"`. Acking a check-in with `"seen"` hides it but doesn't answer it, so it still escalates at 30 s.
- **Status** priority is `sos` (for 2 minutes after raising one) → `stale` → `alert` → `ok`.
- **Errors** are always JSON (`{ok: false, error}`) with a 4xx code: 404 for an unknown member or event, 400 for bad input.
