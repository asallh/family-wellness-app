# Family Wellness: Hackathon Plan

**Team:** 3 people · **Time:** 6 hours · **Demo:** Mom on a real fēnix 7 and Son in the Connect IQ simulator, talking through a small server on a Mac over a phone hotspot

## The pitch (one line)

A two-way family safety network that lives on Garmin watches. Everyone in the family can see everyone else's live heart rate, location and direction. **Anyone** can check on **anyone** with "Are you OK?", and an SOS or fall on any watch alerts the whole family, closest member first. Parents get peace of mind about their kids, and kids can keep an eye on their parents' health.

## Core rule: every feature is two-way

There are **no parent-only or child-only features**. Every watch runs the same app with the same menus. Any member can:

- see every other member's vitals, distance and direction
- send "Are you OK?" to any other member, and answer one from any member
- broadcast an SOS, or have a fall broadcast for them, to everyone else
- receive health alerts about any other member

The demo has to show features working **in both directions** (Mom checks on Son, *and* Son checks on Mom).

## Architecture

```
 ┌──────────────────────┐  Bluetooth  ┌──────────────┐  hotspot   ┌───────────────────────────────┐
 │ Mom: real fēnix 7    │ ──────────▶ │ Phone:       │ ─────────▶ │ Mac                           │
 │ (her own sensors)    │ ◀────────── │ Garmin       │ ◀───────── │  Node + Express server :3000  │
 └──────────────────────┘             │ Connect app  │            │  (in-memory store)            │
                                      └──────────────┘            │           ▲                   │
                                                                  │  localhost│                   │
                                                                  │  CIQ simulator: Son           │
                                                                  │  tools/feeder.py --mock son   │
                                                                  └───────────────────────────────┘
```

Both watches POST telemetry every 5 s and poll `/family` and their inbox. The feeder fakes Son's vitals, position and heading (the simulator has no real sensors), and leaves Mom's real readings alone.

**Key decisions:**

- **One real watch, one simulator.** Mom wears a real fēnix 7 and Son runs in the Connect IQ simulator. Both run the same build, with the real sensor APIs. Setup steps are in the [README](README.md#physical-watch-moms-fēnix-7).
- **No phone app of our own.** The real watch's `Communications.makeWebRequest` goes through the Garmin Connect app on the paired phone. The simulator's goes straight from the Mac.
- **The server is the network.** Watches can't talk to each other directly, so every message goes through the server. It's small: no auth.
- **No database.** The server keeps each member's latest telemetry and pending events in an in-memory `Map`, which is all the features need. A restart wipes the state, which is fine for a demo (and `/debug/reset` does it on purpose). A database only matters for real accounts, history or multiple families, which are out of scope.
- **One server for the demo, on the Mac, over the phone's hotspot.** The Mac joins the phone's hotspot, and Mom's build has the Mac's hotspot address baked in (`BUILD_ONLY=1 DEVICE=fenix7 ./start.sh mom http://<mac-ip>:3000`). Son's simulator uses `localhost`. No ngrok, unless the phone refuses plain `http://` (see the README's troubleshooting table). Separate servers are separate families.
- **One simulator per Mac.** We tested this. The Connect IQ simulator only runs one instance per Mac. A second copy quits immediately, even with its main port moved via `SHELL_SERVER_PORT` and a separate temp folder. **Don't spend time trying to work around it.** The real watch is the second member, and the feeder or `demo.sh` can play either member when the watch isn't on hand.
- **One app, many identities.** Both simulators run the *same build*. You pick who you are on the watch itself (see below).
- **Fake data from a window.** `tools/feeder.py` sets Son's HR, SpO₂, position and heading (pinned on the server, so the simulator's own readings can't overwrite them), with presets for alerts. `--mock son` fakes only Son, so Mom's real sensors show through. "Simulate fall" on either watch covers falls. `server/demo.sh` makes either member do anything from a terminal, and is the stage backup.
- **The family is just Mom and Son.** The server seeds no other members (Dad and Grandpa were both removed). The code still supports a seeded member if one is ever wanted (see `server/src/store.js`).

## Identity and server URL

- **Who am I:** `./start.sh mom` or `./start.sh son` bakes the persona and server URL into the build (`BUILD_ONLY=1` stops after the build, for sideloading). A plain VS Code build falls back to the API tester's picker (Mom / Son), saved in `Application.Storage`.
- **Server URL:** whatever `start.sh` was given. Without it, `source/Config.mc` has `LOCAL_URL` (`http://localhost:3000`) and `SHARED_URL` (an ngrok domain, unused for now).
- **Simulator + HTTP:** for local mode, untick *Settings → Use Device HTTPS Requirements* in the simulator, so it can call `http://localhost`.

## Features (all on the watch, all two-way)

| Feature | What the user sees | Sensors |
|---|---|---|
| **Family list** | Every other member with ♥ HR, distance, and a status dot (ok / alert / stale / SOS) | HR, GPS |
| **Direction to a member** | Pick anyone to get a big arrow pointing at them, with their vitals underneath | GPS + compass |
| **"Are you OK?" check-in** | From any member's detail screen, choose "Check on them". Their watch vibrates with **Yes / No / Need Help / I'm Fine** and a 30 s countdown, and the reply shows on the sender's watch. No, Need Help, or no reply escalates to an SOS to the whole family. | Vibration |
| **Emergency SOS broadcast** | Any member can choose SOS from the menu. *Every other* watch vibrates with an alert naming them, the distance and an arrow to them. The closest live member sees "You are the closest member." | GPS, vibration |
| **Fall detection** | Free fall then impact then stillness, followed by "Did you fall?" with a 15 s countdown and **I'm OK** / **Get help**. If nobody cancels, a fall alert goes to the whole family. "Simulate fall" plays a recorded fall through the same detector. | Accelerometer |
| **Health alerts** | When anyone's HR goes above 150 or below 40, or SpO₂ drops below 90, everyone else gets a vibration and an alert. | HR, Pulse Ox |
| **Vitals on the detail screen** | HR, SpO₂, battery, and a compass with an arrow and distance to them | HR, Pulse Ox, GPS, compass |

### Sensors used (for the bonus points)

All of them are read through the real Connect IQ APIs, and the simulator feeds the values (*Simulation* menu, or FIT/GPX playback).

| Sensor | API | Used for |
|---|---|---|
| Heart rate | `Sensor.Info.heartRate` | Live HR, HR alerts |
| GPS | `Position.enableLocationEvents` | Distance, closest-member routing, direction arrow |
| Compass / magnetometer | `Sensor.Info.heading` | Direction arrow |
| Accelerometer | `Sensor.registerSensorDataListener` (25 Hz) | Fall detection |
| Barometer / altimeter | `Sensor.Info.altitude` | Sent with telemetry |
| Pulse Ox | `Sensor.Info.oxygenSaturation` | Low-SpO₂ alert |
| Temperature | `Sensor.Info.temperature` | Sent with telemetry |
| Vibration | `Attention.vibrate` | All alerts and prompts |

## API contract (agree on this first, 0:00–0:20)

Member ids and names are hardcoded on the server: `mom` (Mom) and `son` (Son). All bodies are JSON. **Don't rename fields without telling the team.** Keep responses small, because watch memory is tight. Every endpoint works the same for every member.

| Method | Path | Body / returns |
|---|---|---|
| POST | `/members/:id/telemetry` | `{hr, spo2, temp, lat, lon, heading, alt, battery}` → `{ok}` |
| GET | `/family` | `[{id, name, hr, spo2, temp, alt, battery, lat, lon, status, lastSeen}]` |
| GET | `/members/:id/inbox` | `[{eventId, type, from, fromName, lat, lon, distanceM, rank, response}]`, **unacked events only** |
| POST | `/members/:id/sos` | `{type: "manual"\|"fall", lat, lon}`. `:id` is the person in trouble. |
| POST | `/members/:id/checkin` | `{from}`. `:id` is who's being checked on, `from` is any other member. |
| POST | `/events/:eventId/ack` | `{by, response: "ok"\|"no"\|"help"\|"seen"}` |
| POST | `/debug/reset` | Clears events and statuses between demo runs |

Event `type` values: `sos`, `fall`, `checkin`, `checkin_reply`, `health` (HR/SpO₂ alert).

Server rules:
- **SOS / fall:** compute the haversine distance from the sender to every other member, sort ascending, and put the event in every other member's inbox with `distanceM` and `rank` (1 = closest).
- **Check-in:** goes into the target's inbox. An `ok`/`no`/`help` ack puts a `checkin_reply` in the asker's inbox, and a `no` or `help` reply also triggers an SOS from the target. With no ack after 30 s, escalate to an SOS from the target. To demo the escalation, leave the prompt on the other watch unanswered.
- **Health:** when telemetry crosses a threshold (HR > 150 or < 40, SpO₂ < 90), set status `alert` and send a `health` event to everyone else. Only send it once per crossing, not on every poll.
- **Status:** `ok` / `alert` / `stale` (no telemetry for 30 s or more) / `sos`.
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
1. 0:20–1:15: Express server in `/server` (`npm start`, port from `PORT` and defaulting to 3000), an in-memory `Map`, every endpoint above. Push it early so A and C can run it locally.
2. Test every endpoint with `curl`. Write `server/demo.sh` with one-liners to reset state and to make either member check in, SOS, fall or spike their HR.
3. 1:15–2:30: check-in escalation timer, health threshold events, stale detection. Then host the shared instance (ngrok static domain) so both laptops can connect.
4. 2:30 onward: integration tester. Drive both simulators through the demo script, in both directions, and log what breaks.

### Person C: Watch data layer + sensors (Monkey C)
1. Manifest: add permissions `Communications`, `Positioning`, `Sensor`, `SensorHistory`. Add `source/Config.mc` with `LOCAL_URL`/`SHARED_URL`, plus the Local/Shared toggle.
2. `FamilyState` + a `Timer` every 5 s that reads sensors, POSTs telemetry, GETs `/family`, then GETs the inbox. **Chain the requests one after another** (start the next in the previous callback), because the watch only allows a few requests in flight at once.
3. Event dispatch: new inbox events trigger `Attention.vibrate` and hand off to Person A's alert or check-in views.
4. **Fall detection** (from about 2:30):
   - Accelerometer at 25 Hz. Magnitude = √(x²+y²+z²) in milli-g.
   - Rule: free fall (< 400 mg) followed within 1 s by an impact (> 2500 mg), then still (within ±200 mg of 1 g) for 2 s. Done: `source/FallDetector.mc`, tested off the watch by `tools/check_fall.py`.
   - A trigger opens "Did you fall?" (`source/ui/FallView.mc`) with a 15 s countdown, then calls `sendSos("fall")`.
   - The simulator can't stream a realistic fall, so "Simulate fall" pushes a recorded sample array through the *same* detector function. The algorithm is real (and ready for a real watch), and the demo is reliable.

## Timeline

| Time | Milestone |
|---|---|
| 0:00–0:20 | Agree on the API contract and the `FamilyState` interface. Repo layout: watch app at the repo root (moving it breaks the VS Code Monkey C setup), `/server`. The simulator runs on both laptops. |
| 0:20–1:30 | Server running locally. One simulator posts telemetry and shows the family list (the other watch). **First end-to-end data flow.** |
| 1:30–2:30 | Member detail with the arrow. Shared server up, and **both simulators see each other**. |
| 2:30–4:00 | Two-way check-in, SOS broadcast + alert view, health alerts, fall detection + "Simulate fall". |
| 4:00–5:00 | **Integration only.** Run the full demo script on both laptops, in both directions, and fix whatever breaks. |
| 5:00 | **Feature freeze.** |
| 5:00–5:40 | Record a backup demo video, then make 3–4 slides (problem → demo → sensors used → what's next). |
| 5:40–6:00 | Rehearse twice. |

Priority order if time runs short: telemetry → family list → two-way check-in → SOS broadcast + alert → direction arrow → health alerts → fall detection.

## Demo script (about 4 minutes)

**Setup:** Mom (the presenter) wears the real fēnix 7. Son is the Connect IQ simulator on the Mac, shown on the projector next to a close-up of Mom's watch. The Mac runs the server and `python3 tools/feeder.py --mock son`. Before you start:

```bash
./server/demo.sh reset
```

```bash
./server/demo.sh family
```

Check that Mom's `lastSeen` is under 10 s, then press **Reset server** in the feeder (it keeps feeding Son). Indoors, give Mom a position, so arrows and distances work without a GPS fix:

```bash
./server/demo.sh move mom 38.8599 -94.7995
```

The feeder puts Son about 500 m south of that.

1. **Pitch.** "I worry about my son walking home from school. He worries about me too. Garmin can connect all of us, in both directions."
2. **Family list, both ways.** Mom's watch shows Son's card: heart rate, distance, green dot. Son's simulator shows Mom's card with her *real* heart rate from the watch on her wrist.
3. **Check-in, Mom → Son.** On Mom's watch, START on Son → **Check on Son**. Mom sees "Check-in sent". Son's watch vibrates with "Are you OK?" and a 30 s ring. Click **Yes** on the simulator. Mom's watch shows "Son is OK".
4. **Check-in, Son → Mom.** On the simulator, open Mom → **Check on Mom**. Mom's real watch buzzes. Mom taps **Need Help**. Son's watch shows "Mom needs help", followed by an SOS alert with an arrow to Mom and "You are the closest member."
   - *Variant:* Mom ignores it. After 30 s it escalates on its own, and Son gets "No Reply: SOS".
5. **Health alert, Son → Mom.** In the feeder, click the **High HR** preset for Son. Mom's watch buzzes with "High Heart Rate · Son · 165 bpm" and an arrow to him. Acknowledge, then click **Normal** to put Son back.
   - *The other way:* Mom's real HR won't hit 150 on stage, so `./server/demo.sh hr mom 165` stands in for it, and Son's watch gets the alert. (Mom's own telemetry sets it back within 5 s.)
6. **SOS broadcast with closest-member routing.** On Mom's watch: MENU → **SOS** → **Yes, send SOS**. Mom sees "SOS sent" once the server has it. Son's watch shows the SOS with the distance, the arrow and "You are the closest member." Then the other way: on the simulator, MENU → **SOS**, and Mom's watch alerts.
7. **Fall detection.** On the simulator: MENU → **Simulate fall**. A recorded fall runs through the same detector the real watch uses. "Did you fall?" counts down from 15. Let it run out, and Mom's watch shows "Fall Detected · Son" with the arrow and distance. Then on Mom's watch: **Simulate fall**, and pick **I'm OK** to show the cancel ("Glad you're OK", nothing sent).
8. **Compass arrow.** Open Son on Mom's watch, and turn on the spot: the dial and the arrow to Son swing with the watch's real compass. On the simulator, drag the feeder's **Heading** slider for Son, and the arrow to Mom swings the same way. Click **Move 100 m N** a few times, and the distance on both watches shrinks.
9. **Close** on the sensors used (HR, Pulse Ox, GPS, compass, accelerometer, vibration) and what's next.

**If something fails on stage:** `./server/demo.sh` can make either member check in, answer, SOS, fall or spike their HR (`./server/demo.sh` with no arguments lists everything). **Preview screens** in the watch menu shows every alert with sample data, with no server at all.

## Out of scope (say these as "next steps")

- Running day to day: a background service, battery tuning, and a pairing flow instead of `start.sh`
- A phone companion app with a map, real push notifications, and calling or texting emergency services
- A background service so sharing continues while the app is closed. Connect IQ background services can only wake every 5 minutes or more.
- Auth, real accounts, a database, multiple families, privacy controls such as letting a member pause sharing
- Geofences ("arrived at school")

## Risks and mitigations

- **Real-watch networking:** the watch reaches the server through Garmin Connect on the phone. If the phone refuses plain `http://` (`Server must use HTTPS`, typical on iPhones) or can't reach the Mac on its own hotspot, fall back to `ngrok http 3000` and rebuild Mom with the `https://` URL. Test this well before the demo.
- **Real watch flaky on stage:** the feeder can mock Mom too (tick **Mock** for Mom), so the demo runs entirely on one Mac.
- **Two people in one Monkey C codebase:** stick to the `FamilyState` seam. Person A doesn't make web requests, and Person C doesn't draw. Commit small and often.
- **Monkey C learning curve:** plain `dc.drawText` and `dc.fillPolygon`, no layouts.
- **Live demo fails:** keep the backup video, and use `server/demo.sh` to trigger any alert from a terminal.
