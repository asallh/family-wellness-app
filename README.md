# Family Wellness

A family safety network on Garmin watches. Every member sees everyone's heart rate and location, anyone can send "Are you OK?" to anyone, and an SOS or fall alerts the whole family, closest person first.

The two watches are **Mom** and **Son**. **Dad** and **Grandpa** are faked by the server so the family looks full.

**The full plan is in [PLAN.md](PLAN.md):** the architecture, the API contract, who owns what, the timeline and the demo script.

## Run it

You need the Connect IQ SDK (with the `fenix7pro` device), a developer key set in VS Code, and Node 20+.

```bash
./start.sh mom
```

```bash
./start.sh son
```

`start.sh` does the following:
1. Starts the server on `localhost:3000` if it isn't running. It stops when you press Ctrl-C.
2. Builds the watch app with that persona and server baked in.
3. Opens the simulator and runs the app.

The watch shows who it is and which server it's on, and every request and response prints to the terminal.

**First time only:** in the simulator, untick **Settings → Use Device HTTPS Requirements**. Otherwise every request fails with `-1001`.

**On the watch:** press START or MENU for the menu. **Run self-test** checks every endpoint and prints `PASS`/`FAIL`. The other items send one request each.

Only one simulator runs per Mac. Run `./start.sh mom` on one laptop and `./start.sh son` on another, both pointed at the same server: `./start.sh son http://<other-laptop>:3000`.

### Fake data from a window (instead of the simulator's Activity menu)

```bash
python3 tools/feeder.py
```

Pick **Mom** or **Son**, tick the fields you want to fake (heart rate, SpO₂, temperature, altitude, battery, heading, position) and move the sliders. Ticked fields are pinned on the server, so the watch's own sensor readings can't overwrite them. Unticked fields go back to the watch's real readings. The other watch sees the fake values, and health alerts fire as usual.

- **Presets:** one click for normal, high HR (165), low HR (35) or low SpO₂ (85).
- **Move 100 m N/S/E/W:** walks the member around, so distances and arrows change.
- **Keep sending every 5 s:** sends the values over and over. This also keeps a member with no simulator running from going stale, so one Mac can play both Mom and Son.
- **Events:** send an SOS, a fall or a check-in as the selected member, or reset the server.
- The table at the bottom shows what the server has, and which fields are pinned.

Use `python3 tools/feeder.py http://<other-laptop>:3000` for a shared server. It only needs Python's standard library, which includes Tkinter.

### Fake events from the terminal

```bash
./server/demo.sh checkin grandpa mom
```

```bash
./server/demo.sh sos grandpa
```

```bash
./server/demo.sh hr son 165
```

```bash
./server/demo.sh reset
```

Run `./server/demo.sh` with no arguments for every command.

## API

The base URL is `http://localhost:3000`, and all bodies are JSON. Members are `mom`, `son`, `dad` and `grandpa`.

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/members/:id/telemetry` | `{hr, spo2, temp, lat, lon, heading, alt, battery}`, all optional | `{ok}` |
| GET | `/family` | | Everyone, including you: `[{id, name, hr, spo2, temp, alt, battery, heading, lat, lon, status, lastSeen, seeded}]` |
| GET | `/members/:id/inbox` | | Unanswered events: `[{eventId, type, from, fromName, lat, lon, distanceM, rank, response, reason, value, ageSec, expiresInSec}]` |
| POST | `/members/:id/sos` | `{type: "manual" or "fall", lat?, lon?}` | `{ok, eventId, notified}` |
| POST | `/members/:id/checkin` | `{from}` asks `:id` "Are you OK?" | `{ok, eventId}` |
| POST | `/events/:eventId/ack` | `{by, response: "ok", "help" or "seen"}` | `{ok}` |
| POST | `/debug/override/:id` | `{hr, spo2, temp, lat, lon, heading, alt, battery}`: a number pins that field, `null` releases it, `{clear: true}` releases all | `{ok, pinned}` |
| GET | `/debug/override` | | Pinned fields per member: `{son: {hr: 165}}` |
| POST | `/debug/reset` | | `{ok}` clears all events, statuses and pinned fields |

**Event types in the inbox:**

| `type` | Meaning |
|---|---|
| `checkin` | Someone asks "Are you OK?". `expiresInSec` counts down the 30 s you have to answer. |
| `checkin_reply` | The answer to your check-in. `response` is `ok` or `help`. |
| `sos` | Someone needs help. `reason` is null for the SOS button, or `checkin_help` / `checkin_timeout`. |
| `fall` | A fall was detected. |
| `health` | Vitals crossed a threshold. `reason` is `hr_high`, `hr_low` or `spo2_low`, and `value` is the reading. |

**Rules:**
- **Health alerts:** HR above 150 or below 40, or SpO₂ below 90, alerts everyone else once per crossing.
- **Check-ins:** answering `help`, or not answering within 30 s, turns into an SOS to the whole family.
- **Closest member:** `rank: 1` marks the closest live watch, so show "(you're closest)".
- **Status** is one of:
  - `sos`: raised an SOS in the last 2 minutes
  - `stale`: no telemetry for 30 s
  - `alert`: a vital is past a threshold
  - `ok`
- **`lastSeen`** is seconds since the last telemetry.
- **The inbox repeats events until they're acked.** Remember the `eventId`s you've already shown.
- **Errors** are JSON, `{ok: false, error}`: 404 for an unknown member or event, 400 for bad input.

## Server only

```bash
cd server && npm install && npm start
```

```bash
cd server && npm test
```

## FAQ

**Do we need a database?** No. The server keeps the family's latest telemetry and pending events in memory, which is all the features need. Losing state on restart is fine for a demo, and `/debug/reset` does it on purpose. A database only matters once you have real accounts, history or multiple families, which are all out of scope.

## Stretch: physical watch (fēnix 7)

Not part of the main build. Only try this after the feature freeze if the simulator demo is solid. The steps are in [PLAN.md → Stretch: physical watch](PLAN.md#stretch-physical-watch).
