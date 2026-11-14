# Family Wellness

A family safety network on Garmin watches. Every member sees everyone's heart rate and location, anyone can send "Are you OK?" to anyone, and an SOS or fall alerts the whole family, closest person first.

The family is the two watches, **Mom** and **Son**. Every feature works both ways between them.

**The full plan is in [PLAN.md](PLAN.md):** the architecture, the API contract, who owns what, the timeline and the demo script.

## Run it

You need the Connect IQ SDK (with the `fenix7pro` device), a developer key set in VS Code, and Node 20+. For Mom's real fēnix 7, see [Physical watch](#physical-watch-moms-fēnix-7).

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

**On the watch:** the family list is the main screen. MENU (or START with nobody listed) opens the menu: **SOS**, **Simulate fall**, **Preview screens** (every alert with sample data, no server needed) and **API tester** (**Run self-test** checks every endpoint and prints `PASS`/`FAIL`).

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

### Fake data from a window (instead of the simulator's Activity menu)

```bash
python3 tools/feeder.py
```

**It's demo-ready the moment it opens.** Mom and Son both start with every field ticked: normal vitals, and about 500 m apart (Mom north of Son). **Keep sending every 5 s** is on for both, so both watches show live data with no setup, and neither goes stale even without its simulator running. Heart rate drifts by a beat or two on each send so it looks live, but never crosses an alert threshold. Start it with `--manual` to begin with nothing ticked or sent.

**Real watch for one member?** Untick that member under **Mock** (or start with `--mock son` to fake only Son). The feeder then stops sending for them and releases anything it had pinned, so the real watch's sensors show through. Their sliders grey out, but you can still send an SOS, a fall or a check-in as them. Tick **Mock** again to go back to fake data.

```bash
python3 tools/feeder.py --mock son
```

Pick who to **Edit** (**Mom** or **Son**) and move a slider (heart rate, SpO₂, temperature, altitude, battery, heading) or type a position. The field ticks itself and goes to the server straight away. Ticked fields are pinned on the server, so the watch's own sensor readings can't overwrite them. Untick a field to hand it back to the watch's real readings. The other watch sees the fake values, and health alerts fire as usual.

- **Presets:** one click for normal, high HR (165), low HR (35) or low SpO₂ (85).
- **Move 100 m N/S/E/W:** walks the member around, so distances and arrows change.
- **Keep sending every 5 s:** sends the values over and over. This also keeps a member with no simulator running from going stale, so one Mac can play both Mom and Son.
- **Events:** send an SOS, a fall or a check-in as the selected member, or reset the server. **Reset server** clears events and statuses for a fresh run and keeps feeding Mom and Son. Use **Release all** to stop faking a member.
- The table at the bottom shows what the server has, and which fields are pinned.

- **Connection line:** green when connected, red with a retry count when not. If the server can't be reached, the feeder keeps retrying every 3 s. When it's back (or it restarted, or someone reset it), the feeder sends every member's ticked values again by itself.

Use `python3 tools/feeder.py <other-laptop>:3000` for a shared server (`http://` is added for you), or type the address in the **Server** box and press Return. If that laptop runs an older server without pinning (for example `main`), the connection line says *telemetry only*. Values are then sent as ordinary telemetry, so tick **Keep sending** to stop the watch's own readings from replacing them. The feeder only needs Python's standard library, which includes Tkinter.

### Fake events from the terminal

```bash
./server/demo.sh checkin son mom
```

```bash
./server/demo.sh sos son
```

```bash
./server/demo.sh hr son 165
```

```bash
./server/demo.sh reset
```

Run `./server/demo.sh` with no arguments for every command.

## API

The base URL is `http://localhost:3000`, and all bodies are JSON. Members are `mom` and `son`.

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/members/:id/telemetry` | `{hr, spo2, temp, lat, lon, heading, alt, battery}`, all optional | `{ok}` |
| GET | `/family` | | Everyone, including you: `[{id, name, hr, spo2, temp, alt, battery, heading, lat, lon, status, lastSeen, seeded, pinned}]`. `pinned` lists the fields the data feeder holds, and a watch uses its own pinned position and heading instead of its sensors. |
| GET | `/members/:id/inbox` | | Unanswered events: `[{eventId, type, from, fromName, lat, lon, distanceM, rank, response, reason, value, ageSec, expiresInSec}]` |
| POST | `/members/:id/sos` | `{type: "manual" or "fall", lat?, lon?}` | `{ok, eventId, notified}` |
| POST | `/members/:id/checkin` | `{from}` asks `:id` "Are you OK?" | `{ok, eventId}` |
| POST | `/events/:eventId/ack` | `{by, response: "ok", "no", "help" or "seen"}` | `{ok}`, or `{ok, late: true}` when the check-in had already timed out or been answered |
| POST | `/debug/override/:id` | `{hr, spo2, temp, lat, lon, heading, alt, battery}`: a number pins that field, `null` releases it, `{clear: true}` releases all | `{ok, pinned}` |
| GET | `/debug/override` | | Pinned fields per member: `{son: {hr: 165}}` |
| POST | `/debug/reset` | | `{ok}` clears all events, statuses and pinned fields |

**Event types in the inbox:**

| `type` | Meaning |
|---|---|
| `checkin` | Someone asks "Are you OK?". `expiresInSec` counts down the 30 s you have to answer. |
| `checkin_reply` | The answer to your check-in. `response` is `ok`, `no` (not OK) or `help`. |
| `sos` | Someone needs help. `reason` is null for the SOS button, or `checkin_no` / `checkin_help` / `checkin_timeout`. |
| `fall` | A fall was detected. |
| `health` | Vitals crossed a threshold. `reason` is `hr_high`, `hr_low` or `spo2_low`, and `value` is the reading. |

**Rules:**
- **Health alerts:** HR above 150 or below 40, or SpO₂ below 90, alerts everyone else once per crossing.
- **Check-ins:** on the watch, **Yes** and **I'm Fine** answer `ok`, **No** answers `no` and **Need Help** answers `help`. Answering `no` or `help`, or not answering within 30 s, turns into an SOS to the whole family. Only the first answer counts, and an answer after the 30 s gets `late: true`, so the watch says "Too late to answer" instead of "Reply sent".
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

## Physical watch (Mom's fēnix 7)

Mom wears a real fēnix 7. Son runs in the simulator with the feeder. The watch has no Wi-Fi path of its own: its requests go over Bluetooth to the Garmin Connect app on the phone, and from there to the server. So the phone, the Mac running the server, and the watch's pairing all have to line up.

1. **Download the device profile once.** Open the Connect IQ SDK Manager → **Devices**, and download **fēnix 7** (`fenix7`). Without it the build stops with "device 'fenix7' isn't installed". If Mom's watch is actually a fēnix 7 **Pro**, use `fenix7pro` everywhere below instead. Check under **Settings → System → About** on the watch.
2. **Join the phone's hotspot** on the Mac, and find the Mac's address on it:
   ```bash
   ipconfig getifaddr en0
   ```
   An iPhone hotspot gives addresses like `172.20.10.x`, and Android often uses `192.168.x.x`.
3. **Start the server** on the Mac. If macOS asks whether `node` may accept incoming connections, allow it.
   ```bash
   cd server && npm start
   ```
4. **Build Mom's app** with that address baked in. This builds `bin/family-mom.prg` and stops (no simulator):
   ```bash
   BUILD_ONLY=1 DEVICE=fenix7 ./start.sh mom http://<mac-ip>:3000
   ```
5. **Sideload it.** Plug the watch in over USB and copy `bin/family-mom.prg` into its `GARMIN/APPS` folder. On a Mac, macOS doesn't mount the watch as a drive, so use [OpenMTP](https://openmtp.ganeshrvel.com/). Unplug, and the app appears in the watch's app list (START → scroll to **Family Wellness**). If it shows an "IQ!" icon, it was built for the wrong device (see step 1).
6. **Phone:** pair the watch with the **Garmin Connect** app, keep the app open (or at least running in the background), with Bluetooth on. The watch's requests fail with `Phone not connected` (`-104`) otherwise.
7. **Son on the simulator**, with the feeder faking only Son so Mom's real sensors show through:
   ```bash
   ./start.sh son
   ```
   ```bash
   python3 tools/feeder.py --mock son
   ```
8. **Check it:** the server log shows `POST /members/mom/telemetry` every 5 s, and `./server/demo.sh family` shows Mom with a real heart rate and `lastSeen` under 10.

**If Mom's watch shows an error under "Connecting...":**

| Watch says | Meaning | Fix |
|---|---|---|
| `Phone not connected` | No Bluetooth link to Garmin Connect | Open Garmin Connect on the phone, and check that the watch is paired |
| `Server must use HTTPS` | The phone refuses plain `http://` (iPhones enforce this) | Run `ngrok http 3000` and build with the `https://…ngrok-free.app` URL instead of the hotspot IP |
| `Can't reach server (-2xx/-3xx)` | The phone can't reach the Mac's IP | Check the IP, allow `node` in the macOS firewall, try `curl http://<mac-ip>:3000/` from the phone's browser |
| `Server timed out` | Server down or very slow | Check the server is still running |

**Indoors, GPS won't get a fix,** so the arrows to and from Mom say "No GPS fix". Give Mom a position on the server instead. The watch uses it whenever it has no fix of its own:

```bash
./server/demo.sh move mom 38.8599 -94.7995
```

**Fall detection on the real watch** uses the accelerometer at 25 Hz: a free fall below 0.4 g, an impact above 2.5 g within 1 s, then 2 s of lying still. Dropping the watch onto a cushion from about a metre and leaving it there should trigger it, but this hasn't been tried on the real watch yet. For the demo, **Simulate fall** in the menu plays a recorded fall through the same detector and is far more reliable. `python3 tools/check_fall.py` tests the detector's logic off the watch.
