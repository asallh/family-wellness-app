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

### On Windows

`start.ps1` does the same thing as `start.sh`. Run it from the repo folder in PowerShell:

```powershell
.\start.ps1 son http://<other-laptop>:3000
```

If Windows says running scripts is disabled, bypass the policy for this one run:

```powershell
powershell -ExecutionPolicy Bypass -File .\start.ps1 son http://<other-laptop>:3000
```

It finds the SDK under `%APPDATA%\Garmin\ConnectIQ\Sdks` and the developer key from VS Code's settings. Set `$env:DEVELOPER_KEY = 'C:\path\to\developer_key'` if it can't find the key.

**Finding the other laptop's address:** on a Mac, run `ipconfig getifaddr en0`. On Windows, run `ipconfig` and use the IPv4 address. Both machines must be on the same network. Check the connection with `curl.exe http://<other-laptop>:3000/family` before launching. If macOS asks whether `node` may accept incoming connections, allow it.

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
| POST | `/debug/reset` | | `{ok}` clears all events and statuses |

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
