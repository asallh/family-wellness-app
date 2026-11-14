# Family Wellness: Hackathon Plan

**Team:** 3 people · **Time:** 6 hours · **Demo:** two Connect IQ simulators (one per laptop) talking through a small server

## The pitch (one line)

A two-way family safety network that lives on Garmin watches. Everyone in the family can see everyone else's live heart rate, location and direction. **Anyone** can check on **anyone** with "Are you OK?", and an SOS or fall on any watch alerts the whole family, closest member first. Parents get peace of mind about their kids, and kids can keep an eye on their parents' and grandparents' health.

## Core rule: every feature is two-way

There are **no parent-only or child-only features**. Every watch runs the same app with the same menus. Any member can:

- see every other member's vitals, distance and direction
- send "Are you OK?" to any other member, and answer one from any member
- broadcast an SOS, or have a fall broadcast for them, to everyone else
- receive health alerts about any other member

The demo has to show features working **in both directions** (Mom checks on Son, *and* Son checks on Mom).

## Architecture

```
 ┌───────────────────────────┐                                  ┌───────────────────────────┐
 │ Laptop 1: CIQ simulator   │   POST telemetry every 5 s       │ Laptop 2: CIQ simulator   │
 │ Watch app as "Mom"        │ ──────────────────────────┐  ┌── │ Watch app as "Son"        │
 │                           │ ◀── poll inbox / events ─┐ │  │   │                           │
 └───────────────────────────┘                          │ ▼  ▼   └───────────────────────────┘
                                                  ┌─────────────────────┐
                                                  │ Node + Express      │
                                                  │ in-memory store     │
                                                  │ (localhost or ngrok)│
                                                  └─────────────────────┘
                                        + "Grandpa" seeded on the server
```

**Key decisions:**

- **Simulators only.** The whole build and demo runs on the Connect IQ simulator. The physical fēnix 7 is a stretch goal for after the feature freeze, if there's time (see [Stretch: physical watch](#stretch-physical-watch)). The code uses the real sensor APIs, so the same build runs on a real watch later.
- **No phone app.** The simulator's `Communications.makeWebRequest` goes straight from the Mac to the internet.
- **The server is the network.** Watches can't talk to each other directly, so every message goes through the server. It's small: no auth.
- **No database.** The server keeps each member's latest telemetry and pending events in an in-memory `Map`, which is all the features need. A restart wipes the state, which is fine for a demo (and `/debug/reset` does it on purpose). A database only matters for real accounts, history or multiple families, which are out of scope.
- **Local mode for dev, shared mode for together.** Each person runs their own server on `localhost:3000` while building alone. Whenever the two simulators need to see each other, and for the demo, both point at **one** server. Separate local servers are separate families. See the [README](README.md) for both setups.
- **One simulator per laptop, so two machines.** We tested this. The Connect IQ simulator only runs one instance per Mac. A second copy quits immediately, even with its main port moved via `SHELL_SERVER_PORT` and a separate temp folder. **Don't spend hackathon time trying to work around it.** Building and testing two-way features always uses two machines: Mom on one, Son on the other. A third laptop can add a third live member if you want one.
- **Pair up to test two-way features.** Most work happens alone in local mode with `demo.sh` playing the other members. When you need a real round trip between two watches (check-in reply, SOS arrow), pair with a teammate. Point both machines at one server, and pick different identities.
- **One app, many identities.** Both simulators run the *same build*. You pick who you are on the watch itself (see below).
- **No extra simulator tool.** The simulator's *Simulation* menu sets HR, GPS and heading. The watch app's "Simulate fall" item covers falls. `server/demo.sh` makes the seeded members do things, and is the stage backup.
- **"Grandpa" is seeded on the server** with a fixed location and plausible HR. He fills out the family list and gives "closest member" routing two watches to choose between. `demo.sh` can make him send an SOS or a health spike.

## Identity and server URL

- **Who am I:** `./start.sh mom` or `./start.sh son` bakes the persona and server URL into the build. A plain VS Code build uses the menu picker (Mom / Son / Grandpa), saved in `Application.Storage`.
- **Server URL:** `source/Config.mc` holds two constants. `LOCAL_URL` is `http://localhost:3000`. `SHARED_URL` is an ngrok **free static domain** (`ngrok http --url=<your-domain>.ngrok-free.app 3000`), committed once. A **Menu → Server: Local / Shared** toggle, saved in `Application.Storage`, picks one without editing code. Local is the default.
- **Simulator + HTTP:** for local mode, untick *Settings → Use Device HTTPS Requirements* in the simulator, so it can call `http://localhost`.

## Features (all on the watch, all two-way)

| Feature | What the user sees | Sensors |
|---|---|---|
| **Family list** | Every other member with ♥ HR, distance, and a status dot (ok / alert / stale / SOS) | HR, GPS |
| **Direction to a member** | Pick anyone to get a big arrow pointing at them, with their vitals underneath | GPS + compass |
| **"Are you OK?" check-in** | From any member's detail screen, choose "Check on them". Their watch vibrates with OK / HELP and a 30 s countdown, and the reply shows on the sender's watch. A HELP reply, or no reply, escalates to an SOS to the whole family. | Vibration |
| **Emergency SOS broadcast** | Any member can choose SOS from the menu. *Every other* watch vibrates with "Son needs help, 350 m" and an arrow to them. The closest member sees "(you're closest)". | GPS, vibration |
| **Fall detection** | Free-fall then impact, followed by "Did you fall?" with a 15 s countdown. If nobody cancels, the SOS broadcast goes out automatically. | Accelerometer, barometer |
| **Health alerts** | When anyone's HR goes above 150 or below 40, or SpO₂ drops below 90, everyone else gets a vibration and an alert. | HR, Pulse Ox |
| **Vitals on the detail screen** | HR, SpO₂, skin temperature, altitude, battery | HR, Pulse Ox, temperature, barometer |

### Sensors used (for the bonus points)

All of them are read through the real Connect IQ APIs, and the simulator feeds the values (*Simulation* menu, or FIT/GPX playback).

| Sensor | API | Used for |
|---|---|---|
| Heart rate | `Sensor.Info.heartRate` | Live HR, HR alerts |
| GPS | `Position.enableLocationEvents` | Distance, closest-member routing, direction arrow |
| Compass / magnetometer | `Sensor.Info.heading` | Direction arrow |
| Accelerometer | `Sensor.registerSensorDataListener` (25 Hz) | Fall detection |
| Barometer / altimeter | `Sensor.Info.pressure`, `altitude` | Second fall signal (sudden drop), shown on detail screen |
| Pulse Ox | `Sensor.Info.oxygenSaturation` | Low-SpO₂ alert |
| Temperature | `Sensor.Info.temperature` | Shown on detail screen |
| Vibration | `Attention.vibrate` | All alerts and prompts |

## API contract (agree on this first, 0:00–0:20)

Member ids and names are hardcoded on the server: `mom` (Mom) and `son` (Son), plus the seeded `grandpa` (Grandpa). All bodies are JSON. **Don't rename fields without telling the team.** Keep responses small, because watch memory is tight. Every endpoint works the same for every member.

| Method | Path | Body / returns |
|---|---|---|
| POST | `/members/:id/telemetry` | `{hr, spo2, temp, lat, lon, heading, alt, battery}` → `{ok}` |
| GET | `/family` | `[{id, name, hr, spo2, temp, alt, battery, lat, lon, status, lastSeen}]` |
| GET | `/members/:id/inbox` | `[{eventId, type, from, fromName, lat, lon, distanceM, rank, response}]`, **unacked events only** |
| POST | `/members/:id/sos` | `{type: "manual"\|"fall", lat, lon}`. `:id` is the person in trouble. |
| POST | `/members/:id/checkin` | `{from}`. `:id` is who's being checked on, `from` is any other member. |
| POST | `/events/:eventId/ack` | `{by, response: "ok"\|"help"\|"seen"}` |
| POST | `/debug/reset` | Clears events and statuses between demo runs |

Event `type` values: `sos`, `fall`, `checkin`, `checkin_reply`, `health` (HR/SpO₂ alert).

Server rules:
- **SOS / fall:** compute the haversine distance from the sender to every other member, sort ascending, and put the event in every other member's inbox with `distanceM` and `rank` (1 = closest).
- **Check-in:** goes into the target's inbox. An `ok`/`help` ack puts a `checkin_reply` in the asker's inbox, and a `help` reply also triggers an SOS from the target. With no ack after 30 s, escalate to an SOS from the target. Seeded members never answer, so checking on them demos the escalation.
- **Health:** when telemetry crosses a threshold (HR > 150 or < 40, SpO₂ < 90), set status `alert` and send a `health` event to everyone else. Only send it once per crossing, not on every poll.
- **Status:** `ok` / `alert` / `stale` (no telemetry for 30 s or more) / `sos`. Seeded members are never stale.
- **Inbox:** returns unacked events. The watch remembers `eventId`s it has already shown, so repeated polls don't re-vibrate.

## Who does what

Two people work on the watch app, so split it along a clear seam. **Person C owns the data layer, and Person A owns the screens.** Agree on this interface in the first 20 minutes:

```
FamilyState (singleton, Person C)
  myId           : chosen identity (Application.Storage)
  members        : Array of member dictionaries from /family (excluding me)
  me             : this watch's latest telemetry
  pendingEvents  : events not yet shown
  onChange       : callback the views use to WatchUi.requestUpdate()
  sendSos(type), sendCheckin(targetId), ack(eventId, response)
```

### Person A: Watch screens (Monkey C)
1. **Identity picker** (first launch, and from the menu).
2. **Family list** (main view): name, ♥ HR, distance, status dot.
3. **Member detail:** compass arrow drawn with `dc.fillPolygon`. Angle = `bearing(me → them) − myHeading`. Vitals underneath, and a **"Check on them"** action available for *every* member.
4. **Alert view:** pushed on any `sos`/`fall`/`health` event. Shows who, the distance, "(you're closest)", and an arrow to them. Has an Acknowledge button.
5. **Check-in prompt:** "Mom is asking: are you OK?" with OK / HELP buttons and a 30 s countdown. **Check-in reply:** "Son says OK ✅" or "Son needs HELP".
6. **Menu:** SOS, Change identity, Server: Local / Shared, Simulate fall. The same menu on every watch.
7. Keep the UI to `dc.drawText` and simple shapes. No custom fonts or layouts.

### Person B: Server, then integration
1. 0:20–1:15: Express server in `/server` (`npm start`, port from `PORT` and defaulting to 3000), an in-memory `Map`, every endpoint above, and the seeded `grandpa`. Push it early so A and C can run it locally.
2. Test every endpoint with `curl`. Write `server/demo.sh` with one-liners to reset state and to make any member (including the seeded ones) check in, SOS, fall or spike their HR.
3. 1:15–2:30: check-in escalation timer, health threshold events, stale detection. Then host the shared instance (ngrok static domain) so both laptops can connect.
4. 2:30 onward: integration tester. Drive both simulators through the demo script, in both directions, and log what breaks.

### Person C: Watch data layer + sensors (Monkey C)
1. Manifest: add permissions `Communications`, `Positioning`, `Sensor`, `SensorHistory`. Add `source/Config.mc` with `LOCAL_URL`/`SHARED_URL`, plus the Local/Shared toggle.
2. `FamilyState` + a `Timer` every 5 s that reads sensors, POSTs telemetry, GETs `/family`, then GETs the inbox. **Chain the requests one after another** (start the next in the previous callback), because the watch only allows a few requests in flight at once.
3. Event dispatch: new inbox events trigger `Attention.vibrate` and hand off to Person A's alert or check-in views.
4. **Fall detection** (from about 2:30):
   - Accelerometer at 25 Hz. Magnitude = √(x²+y²+z²) in milli-g.
   - Rule: free fall (< 400 mg) followed within 1 s by an impact (> 2500 mg), then roughly still for 2 s. Optionally confirm with an altitude drop from the barometer.
   - A trigger opens "Did you fall?" with a 15 s countdown, then calls `sendSos("fall")`.
   - The simulator can't stream a realistic fall, so "Simulate fall" pushes a recorded sample array through the *same* detector function. The algorithm is real (and ready for a real watch), and the demo is reliable.

## Timeline

| Time | Milestone |
|---|---|
| 0:00–0:20 | Agree on the API contract and the `FamilyState` interface. Repo layout: watch app at the repo root (moving it breaks the VS Code Monkey C setup), `/server`. The simulator runs on both laptops. |
| 0:20–1:30 | Server running locally. One simulator posts telemetry and shows the family list (with seeded Grandpa). **First end-to-end data flow.** |
| 1:30–2:30 | Member detail with the arrow. Shared server up, and **both simulators see each other**. |
| 2:30–4:00 | Two-way check-in, SOS broadcast + alert view, health alerts, fall detection + "Simulate fall". |
| 4:00–5:00 | **Integration only.** Run the full demo script on both laptops, in both directions, and fix whatever breaks. |
| 5:00 | **Feature freeze.** |
| 5:00–5:40 | Record a backup demo video, then make 3–4 slides (problem → demo → sensors used → what's next). |
| 5:40–6:00 | Rehearse twice. |

Priority order if time runs short: telemetry → family list → two-way check-in → SOS broadcast + alert → direction arrow → health alerts → fall detection.

## Demo script (about 3 minutes)

Two laptops side by side: Laptop 1 is **Mom's watch** and Laptop 2 is **Son's watch**. Both are on the shared server. Run `server/demo.sh reset` before you start.

1. "I worry about my son walking home from school. My son worries about me, and about Grandpa, who lives alone. Garmin can connect all of us, in both directions."
2. Both watches show the family list: everyone's live HR and distance, including Grandpa.
3. **Parent → child:** Mom chooses "Check on Son". Son's watch vibrates, Son taps **OK**, and Mom's watch shows "Son says OK ✅".
4. **Child → parent:** on Mom's laptop, raise the simulated HR above 150. Son's watch vibrates with "Mom's heart rate is high (162)". Son chooses "Check on Mom", and **Mom doesn't answer**. After 30 s it escalates, and Son gets the SOS with an arrow pointing to Mom.
5. **Direction:** change Son's heading in the simulator, and the arrow to Mom swings around with it.
6. **Fall:** on Son's watch, choose **Simulate fall**. "Did you fall?" counts down 15 s, then Mom's watch shows "Son may have fallen, 350 m (you're closest)".
7. **Grandpa** (optional): `demo.sh sos grandpa`. Both watches alert, and only the closer one is marked "(you're closest)".
8. Close on the sensor list (HR, GPS, compass, accelerometer, barometer, SpO₂, temperature) and what comes next, including running it on a real fēnix 7.

## Stretch: physical watch

Only after the 5:00 feature freeze, and only if the demo is already solid. The fēnix 7 is already in the manifest.

- **Needs:** the fēnix 7 device downloaded in the SDK Manager, a phone paired through the Garmin Connect app (the watch's requests go through it), and the shared ngrok server, because a real watch can't reach `localhost`.
- **Sideload:** "Monkey C: Build for Device" → `fenix7`, then copy the `.prg` into the watch's `GARMIN/APPS` folder over USB (OpenMTP on a Mac).
- **Check:** if the build complains about `minApiLevel` (currently `5.2.0`), lower it to what the device supports. Indoors, GPS may not get a fix.

## Out of scope (say these as "next steps")

- Running on real watches day to day (the code is ready, see the stretch section)
- A phone companion app with a map, real push notifications, and calling or texting emergency services
- A background service so sharing continues while the app is closed. Connect IQ background services can only wake every 5 minutes or more.
- Auth, real accounts, a database, multiple families, privacy controls such as letting a member pause sharing
- Geofences ("arrived at school")

## Risks and mitigations

- **Simulator networking:** get the first `makeWebRequest` working against `localhost` within the first hour. For the shared server, use the ngrok HTTPS URL, and send the `ngrok-skip-browser-warning` header if ngrok's free-tier warning page breaks JSON responses.
- **Two people in one Monkey C codebase:** stick to the `FamilyState` seam. Person A doesn't make web requests, and Person C doesn't draw. Commit small and often.
- **Monkey C learning curve:** plain `dc.drawText` and `dc.fillPolygon`, no layouts.
- **Live demo fails:** keep the backup video, and use `server/demo.sh` to trigger any alert from a terminal.
