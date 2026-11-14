# Family Wellness: Hackathon Plan

**Team:** 3 people · **Time:** 6 hours · **Demo:** two Connect IQ simulators (one per laptop) talking through a small server

## The pitch (one line)

A family safety network that lives entirely on Garmin watches. Each watch shares live heart rate, location and direction with the family. A fall or SOS on one watch makes the others vibrate and point an arrow toward the person in trouble. A parent can send "Are you OK?" from their own watch, and the child's watch has to answer.

## Architecture

```
 ┌───────────────────────────┐                                  ┌───────────────────────────┐
 │ Laptop 1: CIQ simulator   │   POST telemetry, poll inbox     │ Laptop 2: CIQ simulator   │
 │ Watch app as "dad"        │ ──────── every 5 s ───────┐  ┌── │ Watch app as "kid"        │
 │ (role: parent)            │ ◀─── events ───────────┐  │  │   │ (role: child)             │
 └───────────────────────────┘                        │  ▼  ▼   └───────────────────────────┘
                                                ┌─────────────────────┐
                                                │ Node + Express      │
                                                │ in-memory store     │
                                                │ exposed via ngrok   │
                                                └─────────────────────┘
```

**Key decisions:**

- **No phone app.** In the simulator, `Communications.makeWebRequest` goes straight from the Mac to the internet. On real watches it goes through the official Garmin Connect app on each person's phone, which we don't build. Every feature in this plan fits on the watch.
- **The server is the network.** Watches can't talk to each other directly, so every message goes through the server. It's small: no auth, no database.
- **One simulator per laptop.** We tested this. The Connect IQ simulator only runs one instance per Mac (it always takes port 1234), so the two watches run on two laptops.
- **One app, two identities.** Both watches run the *same build*. Each laptop sets `memberId` and `role` in the app's settings, so nobody edits code to switch between "dad" and "kid".
- **No extra simulator tool.** The Connect IQ simulator's *Simulation* menu already sets heart rate, GPS position and heading, and can play back a FIT/GPX file. The watch app's own debug menu item covers falls. The Tkinter panel idea is scrapped.
- **Two fake members on the server** (`mom`, `grandpa`) with fixed locations and plausible HR. They're seeded in code with no UI. This gives the family list more than two people and makes "closest member" routing mean something. Optional: drop it if time is short.

## Watch app settings

Declared in `resources/properties.xml` and `resources/settings.xml`, and read with `Application.Properties.getValue(...)`. Set them per laptop in the simulator's app settings editor (File menu → edit application properties/settings).

| Key | Example | Purpose |
|---|---|---|
| `memberId` | `dad` / `kid` | Who this watch is |
| `role` | `parent` / `child` | Parents get the "Check on…" menu |
| `serverUrl` | `https://xxxx.ngrok-free.app` | Shared server address |

## Features (all on the watch)

| Feature | What the user sees | Sensors |
|---|---|---|
| **Family list** | Every member with ♥ HR, distance, and a status dot (ok / alert / stale / SOS) | HR, GPS |
| **Direction to a member** | Pick a member to get a big arrow pointing at them, with HR and distance underneath | GPS + compass |
| **Emergency SOS** | Menu item or hold a button: *every other* watch vibrates with "Kid needs help, 350 m" and an arrow to them. The closest member gets "(you're closest)". | GPS, vibration |
| **Fall detection** | Free-fall then impact, followed by "Did you fall?" with a 15 s countdown. If nobody cancels, an SOS is sent automatically. | Accelerometer, barometer |
| **"Are you OK?" check-in** | A parent picks "Check on Kid". The kid's watch vibrates with an OK / HELP prompt. The reply shows on the parent's watch. No reply in 30 s escalates to an SOS. | Vibration |
| **Health alerts** | When a member's HR goes above 150 or below 40, or SpO₂ drops below 90, the other watches get a vibration and an alert. | HR, Pulse Ox |
| **Vitals on the detail screen** | HR, SpO₂, skin temperature, altitude, battery | HR, Pulse Ox, temperature, barometer |

### Sensors used (for the bonus points)

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

Base URL: the ngrok URL. Member ids and names are hardcoded on the server: `dad` (Dad), `kid` (Kid), plus the seeded `mom` (Mom) and `grandpa` (Grandpa). All bodies are JSON. **Don't rename fields without telling the team.** Keep responses small, because watch memory is tight.

| Method | Path | Body / returns |
|---|---|---|
| POST | `/members/:id/telemetry` | `{hr, spo2, temp, lat, lon, heading, alt, battery}` → `{ok}` |
| GET | `/family` | `[{id, name, hr, spo2, temp, alt, battery, lat, lon, status, lastSeen}]` |
| GET | `/members/:id/inbox` | `[{eventId, type, from, fromName, lat, lon, distanceM, rank, response}]`, **unacked events only** |
| POST | `/members/:id/sos` | `{type: "manual"\|"fall", lat, lon}` |
| POST | `/members/:id/checkin` | `{from}`. `:id` is who's being checked on. |
| POST | `/events/:eventId/ack` | `{by, response: "ok"\|"help"\|"seen"}` |
| POST | `/debug/reset` | Clears events and statuses between demo runs |

Event `type` values: `sos`, `fall`, `checkin`, `checkin_reply`, `health` (HR/SpO₂ alert).

Server rules:
- **SOS / fall:** compute the haversine distance from the sender to every other member, sort ascending, and put the event in every inbox with `distanceM` and `rank` (1 = closest).
- **Check-in:** goes into the target's inbox. An `ok`/`help` ack puts a `checkin_reply` in the asker's inbox, and a `help` reply also triggers an SOS. With no ack after 30 s, escalate to an SOS from the target.
- **Health:** when telemetry crosses a threshold (HR > 150 or < 40, SpO₂ < 90), set status `alert` and send a `health` event to everyone else. Only send it once per crossing, not on every poll.
- **Status:** `ok` / `alert` / `stale` (no telemetry for 30 s or more) / `sos`.
- **Inbox:** returns unacked events. The watch remembers `eventId`s it has already shown, so repeated polls don't re-vibrate.

## Who does what

Two people work on the watch app, so split it along a clear seam. **Person C owns the data layer, and Person A owns the screens.** Agree on this interface in the first 20 minutes:

```
FamilyState (singleton, Person C)
  members        : Array of member dictionaries from /family
  me             : this watch's latest telemetry
  pendingEvents  : events not yet shown
  onChange       : callback the views use to WatchUi.requestUpdate()
  sendSos(type), sendCheckin(targetId), ack(eventId, response)
```

### Person A: Watch screens (Monkey C)
1. **Family list** (main view): name, ♥ HR, distance, status dot.
2. **Member detail:** compass arrow drawn with `dc.fillPolygon`. Angle = `bearing(me → them) − myHeading`, with vitals underneath.
3. **Alert view:** pushed on any `sos`/`fall`/`health` event. Shows who, the distance, "(you're closest)", and an arrow to them. Has an Acknowledge button.
4. **Check-in prompt** (child): "Are you OK?" with OK / HELP buttons and a 30 s countdown. **Check-in reply** (parent): "Kid says OK ✅".
5. **Menus:** SOS, "Check on…" (only when `role == parent`), "Simulate fall" (debug).
6. Keep the UI to `dc.drawText` and simple shapes. No custom fonts or layouts.

### Person B: Server, then integration
1. 0:20–1:15: Express server in `/server`, an in-memory `Map`, every endpoint above, and the seeded `mom`/`grandpa`. Run it with ngrok and share the URL right away.
2. Test every endpoint with `curl` so the watch team can trust it. Keep a `server/demo.sh` with `curl` one-liners for resetting state and triggering events, as a backup if a watch misbehaves on stage.
3. 1:15 onward: check-in escalation timer, health threshold events, and stale detection. Then become the integration tester: drive both simulators and log what breaks.

### Person C: Watch data layer + sensors (Monkey C)
1. Manifest: add permissions `Communications`, `Positioning`, `Sensor`, `SensorHistory`. Add `properties.xml` and `settings.xml` for `memberId`, `role` and `serverUrl`.
2. `FamilyState` + a `Timer` every 5 s that reads sensors, POSTs telemetry, GETs `/family`, then GETs the inbox. **Chain the requests one after another** (start the next in the previous callback), because the watch only allows a few requests in flight at once.
3. Event dispatch: new inbox events trigger `Attention.vibrate` and hand off to Person A's alert or check-in views.
4. **Fall detection** (from about 2:30):
   - Accelerometer at 25 Hz. Magnitude = √(x²+y²+z²) in milli-g.
   - Rule: free fall (< 400 mg) followed within 1 s by an impact (> 2500 mg), then roughly still for 2 s. Optionally confirm with an altitude drop from the barometer.
   - A trigger opens "Did you fall?" with a 15 s countdown, then calls `sendSos("fall")`.
   - **Simulator caveat:** the simulator can't stream a realistic fall, so "Simulate fall" pushes a recorded sample array through the *same* detector function. The algorithm is real and the demo is reliable.

## Timeline

| Time | Milestone |
|---|---|
| 0:00–0:20 | Agree on the API contract and the `FamilyState` interface. Repo layout: watch app at the repo root (moving it breaks the VS Code Monkey C setup), `/server`. The simulator runs on both laptops. |
| 0:20–1:30 | Server up on ngrok. One watch posts telemetry and shows the family list. **First end-to-end data flow.** |
| 1:30–2:30 | **Both laptops running.** Dad and Kid see each other's HR and distance. Member detail with the arrow. |
| 2:30–4:00 | SOS + alert view, check-in round trip, health alerts, fall detection + "Simulate fall". |
| 4:00–5:00 | **Integration only.** Run the full demo script on both laptops and fix whatever breaks. |
| 5:00 | **Feature freeze.** |
| 5:00–5:40 | Record a backup demo video, then make 3–4 slides (problem → demo → sensors used → what's next). |
| 5:40–6:00 | Rehearse twice. |

Priority order if time runs short: telemetry → family list → SOS + alert → check-in → direction arrow → health alerts → fall detection → seeded members.

## Demo script (about 3 minutes)

Two laptops side by side: Laptop 1 is **Dad's watch** (parent) and Laptop 2 is **Kid's watch** (child). Run `server/demo.sh reset` before you start.

1. "My little brother walks home from school, and my grandpa lives alone." Then the problem.
2. Dad's watch shows the family list: Kid, Mom and Grandpa with live HR and distance.
3. Open Kid on Dad's watch. Change Kid's GPS position and Dad's heading in the simulators, and the arrow swings toward Kid.
4. On Kid's laptop, raise the simulated heart rate above 150. Dad's watch vibrates with "Kid's heart rate is high (162)".
5. Dad picks **Check on Kid**. Kid's watch vibrates, Kid taps **OK**, and Dad's watch shows "Kid says OK ✅".
6. Check on Kid again and **don't answer**. After 30 s it escalates, and Dad's watch gets the SOS with an arrow to Kid.
7. On Kid's watch, choose **Simulate fall**. The 15 s countdown runs out and Dad's watch shows "Kid may have fallen, 350 m (you're closest)".
8. Close on the sensor list (HR, GPS, compass, accelerometer, barometer, SpO₂, temperature) and what comes next.

## Out of scope (say these as "next steps")

- A phone companion app with a map, real push notifications, and calling or texting emergency services
- A background service so sharing continues while the app is closed. Connect IQ background services can only wake every 5 minutes or more.
- Auth, real accounts, a database, multiple families, privacy controls
- Geofences ("arrived at school")

## Risks and mitigations

- **Simulator networking:** use the ngrok HTTPS URL, and get the first `makeWebRequest` working within the first hour. If ngrok's free-tier warning page breaks JSON responses, send the `ngrok-skip-browser-warning` header.
- **Two people in one Monkey C codebase:** stick to the `FamilyState` seam. Person A doesn't make web requests, and Person C doesn't draw. Commit small and often.
- **Monkey C learning curve:** plain `dc.drawText` and `dc.fillPolygon`, no layouts.
- **Live demo fails:** keep the backup video, and use `server/demo.sh` to trigger any alert from a terminal.
