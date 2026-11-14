# Family Wellness: Hackathon Plan

**Team:** 3 people · **Time:** 6 hours · **Demo:** Connect IQ simulator + React Native (Expo) app

## The pitch (one line)

A family safety network on Garmin watches. Everyone shares live heart rate, location and direction. A fall or SOS from any watch alerts the family, closest member first, and parents can send an "Are you OK?" check-in that the watch has to answer.

## Architecture

```
 ┌──────────────────┐   POST telemetry / poll inbox   ┌──────────────────┐   GET family / send check-in  ┌──────────────────┐
 │ Garmin watch app │ ───────── every 5 s ──────────▶ │  Node + Express  │ ◀──────── every 3 s ────────── │ Expo RN app      │
 │ (Monkey C, sim)  │ ◀──────── events ────────────── │  in-memory store │ ──────── family + alerts ────▶ │ (parent's phone) │
 └──────────────────┘                                 └──────────────────┘                                └──────────────────┘
        ▲                                                     ▲
        │ Connect IQ simulator = the "real" watch(es)         │ tools/family_sim.py = virtual watches for the
                                                              │ other family members (same API as the watch)
```

## Family Simulator panel (to build: `tools/family_sim.py`)

We're demoing on simulators only, so we'll build a small desktop app that plays the family members who don't have a Connect IQ simulator running. It acts as a "virtual watch" and talks to the server through the same API as the real watch app, so the server and phone app can't tell the difference.

**Tech:** Python 3 + Tkinter, standard library only (`urllib` for HTTP), so nobody needs to `pip install` anything. Network calls go on a background thread so the window never freezes, and the server URL comes from a `--url` flag or the `FAMILY_API` env var. Estimate: about 45 minutes.

```bash
python3 tools/family_sim.py --url https://<your-ngrok>.ngrok-free.app
```

**What it should do:**

- **Pick a member** (Dad / Mom / Kid / Grandpa) and tick *Simulate this member*. By default the panel drives Mom and Grandpa. Kid is the real CIQ simulator and Dad is the phone app.
- **Vitals:** sliders for target HR, SpO₂ and skin temperature, plus presets: Resting / Walking / Exercise / **Panic spike (185)** / **Low HR (38)**. HR eases toward the target with noise, so the graphs look real.
- **Behaviour:** *Walking* moves the member in a loop on the map and changes their heading, which exercises the compass arrow. *Go offline* stops sending so the member turns "stale". *Auto-answer check-ins*.
- **Emergencies:** **Trigger FALL** posts `/sos {type:"fall"}`, stops walking and raises HR. **Emergency SOS** posts `/sos {type:"manual"}`.
- **Incoming events:** shows check-ins and SOS alerts that reach simulated members, with buttons to answer a check-in **OK** or **HELP**. Ignore a check-in to demo the 30 s escalation.
- Every 2 s, each simulated member POSTs telemetry and polls its inbox, exactly like the watch app does.

Note that the panel **cannot control the Connect IQ simulator itself**. For the real watch, set HR, GPS and heading in the CIQ simulator's *Simulation* menu, or play back a FIT/GPX file. Use the watch's own debug "Simulate fall" menu item to show fall detection on the watch.

**Why a small Node server and not Firebase:** "notify the closest member" and the check-in timeout are server logic. With no auth and an in-memory store, everyone can be hitting a working API in about 20 minutes. Expose it with `ngrok http 3000` so the phone running Expo Go and every laptop's simulator use the same URL.

**What a real device would need** (say this to judges, but don't build it): on a real watch, traffic goes watch → Garmin Connect app on the phone → internet. Continuous sharing while the app is closed needs a Connect IQ background service, and those can only wake every 5 minutes or more. The demo runs the app in the foreground.

## Sensors used (for the bonus points)

| Sensor | API | Feature |
|---|---|---|
| Heart rate | `Sensor.Info.heartRate` | Live HR, high/low HR alerts |
| GPS | `Position.enableLocationEvents` | Family map, closest-member routing |
| Compass / magnetometer | `Sensor.Info.heading` | Arrow pointing toward a family member |
| Accelerometer | `Sensor.registerSensorDataListener` (25 Hz) | Fall detection |
| Barometer / altimeter | `Sensor.Info.pressure`, `altitude` | Sudden altitude drop as a second fall signal, shown on card |
| Pulse Ox | `Sensor.Info.oxygenSaturation` | SpO₂ on member card, low-SpO₂ alert |
| Temperature | `Sensor.Info.temperature` | Shown on member card |
| Vibration | `Attention.vibrate` | Alerts and check-in prompts on the watch |

The simulator can feed all of these (Simulation → Sensor Data / Activity Data, or play back a FIT/GPX file for GPS and HR).

## API contract (agree on this first, 0:00–0:20)

Base URL: the ngrok URL. Family is hardcoded as `family1`. Member ids and display names are hardcoded on the server: `dad` (Dad), `mom` (Mom), `kid` (Kid), `grandpa` (Grandpa). All bodies are JSON. **Don't rename fields without telling the team**, because the watch, the app and `family_sim.py` all depend on them.

| Method | Path | Body / returns | Who calls it |
|---|---|---|---|
| POST | `/members/:id/telemetry` | `{hr, spo2, temp, lat, lon, heading, alt, battery}` → `{ok}` | Watch |
| GET | `/family` | `[{id, name, hr, spo2, lat, lon, heading, status, lastSeen}]` | Watch + app |
| GET | `/members/:id/inbox` | `[{eventId, type: "checkin"\|"checkin_reply"\|"sos"\|"fall", from, lat, lon, distanceM, rank}]`, **unacked events only** | Watch + app + sim |
| POST | `/members/:id/sos` | `{type: "manual"\|"fall", lat, lon}` | Watch + sim |
| POST | `/members/:id/checkin` | `{from}` (parent asks "Are you OK?") | App |
| POST | `/events/:eventId/ack` | `{by, response: "ok"\|"help"}`. Removes it from `by`'s inbox. A check-in ack goes back to the asker as a `checkin_reply` event. | Watch + app + sim |
| POST | `/debug/reset` | Clears all events and statuses between demo runs | Anyone |

Clients poll the inbox and de-duplicate by `eventId`, so the server can return the same unacked event on every poll.

Server rules:
- **SOS / fall:** compute haversine distance from the person in trouble to every other member, sort ascending, and add the event to every inbox with `distanceM` and a `rank`. The closest member gets `rank: 1` and a stronger alert.
- **Check-in:** if there is no ack within 30 s, escalate it into an SOS automatically.
- **Status:** `ok` / `alert` / `stale` (no telemetry for 30 s or more) / `sos`.
- **HR alerts:** HR above 150 at rest or below 40 sets status to `alert`. Keep the thresholds hardcoded.

## Who does what

### Person A: Watch app (Monkey C), the critical path
1. Manifest: add permissions `Communications`, `Positioning`, `Sensor`, `SensorHistory`. Add a couple of simulator products (e.g. `fenix7pro`, `venu3`).
2. `TelemetryService`: a `Timer` every 5 s that reads sensors and calls `Communications.makeWebRequest` to POST telemetry, then GETs the inbox.
3. **Main view:** a list of family members showing name, ♥ HR, distance, and a status dot.
4. **Member detail view:** a large compass arrow. The arrow angle is `bearing(me → them) − myHeading`, with HR and distance underneath. This covers the "general direction" idea.
5. **Alert view:** vibrate, then show "Mom fell, 120 m away (you're closest)" with Ack.
6. **Check-in view:** "Are you OK?" with buttons ✅ OK / 🆘 Help, on a 30 s countdown.
7. **SOS:** a menu item, or holding the Back button, posts `/sos`.

### Person B: Backend + simulator panel, then fall detection
1. 0:20–1:30: Express server in `/server` with the endpoints above, an in-memory `Map`, and ngrok. Share the URL in the group chat right away.
2. 1:30–2:15: build the **Family Simulator panel** (`tools/family_sim.py`, see the section above) and use it to test SOS, closest-member and check-in escalation without waiting on the watch or the app. Include a log pane that shows every request failure.
3. 2:15 onward: pair with Person A on **fall detection** in Monkey C:
   - Accelerometer at 25 Hz. Magnitude = √(x²+y²+z²) in milli-g.
   - Rule: free fall (< 400 mg) followed within 1 s by an impact (> 2500 mg), then roughly still for 2 s. Optionally confirm with an altitude drop from the barometer.
   - On a trigger, show a "Did you fall?" screen with a 15 s countdown, then auto-POST `/sos {type:"fall"}`.
   - **Simulator caveat:** the simulator can't easily stream a realistic fall, so add a debug menu item, "Simulate fall", that pushes a recorded fall sample array through the *same* detector function. That way the algorithm is real and the demo is reliable.

### Person C: React Native app (Expo)
1. `npx create-expo-app family-app`, run in Expo Go on a phone.
2. **Family screen:** `react-native-maps` with a pin per member, plus cards below showing HR, SpO₂, temperature, battery, status color and last seen. Poll `/family` every 3 s.
3. **Member screen:** live HR line (a simple sparkline of the last ~60 points kept in app state), the "Send check-in" button, and a "Navigate" button that opens Maps.
4. **Alerts:** poll `/members/dad/inbox`. On an SOS or fall, show a full-screen red alert with distance, rank and a map, plus a local notification via `expo-notifications`. Skip remote push because it needs extra setup.
5. Polish the demo UI last: app name, icon, colors.

## Timeline

| Time | Milestone |
|---|---|
| 0:00–0:20 | Agree on the API contract and ids. Repo layout: the CIQ watch app stays at the repo root (moving it breaks the VS Code Monkey C setup), `/server`, `/app`, `/tools`. Everyone's toolchain runs. |
| 0:20–1:30 | Server up on ngrok. Watch posts HR and GPS. App shows a list from `/family` (test with `curl` POSTs until the panel exists). **First end-to-end data flow.** |
| 1:30–3:00 | Watch: family list + compass arrow. App: map + cards. Server: SOS/closest logic and check-in escalation. Simulator panel built, so Mom and Grandpa appear on the map. |
| 3:00–4:15 | SOS, check-in round trip, fall detection + "Simulate fall". |
| 4:15–5:00 | **Integration only.** Run the full demo script end to end and fix whatever breaks. |
| 5:00 | **Feature freeze.** |
| 5:00–5:40 | Record a backup demo video, then make 3–4 slides (problem → demo → sensors used → what's next). |
| 5:40–6:00 | Rehearse twice. |

## Demo script (about 3 minutes)

Have three windows on screen: the Connect IQ simulator (Kid), the Family Simulator panel (Mom + Grandpa), and the phone app (Dad), mirrored or on a projector camera. Hit `POST /debug/reset` before you start.

1. "My grandpa lives alone, and my little brother walks home from school." Then the problem.
2. The phone shows the family map: Kid (the CIQ simulator), plus Mom and Grandpa (the panel) walking, with live HR.
3. On the watch, open Mom. The arrow points toward her while you rotate the simulated heading.
4. In the panel, hit **Panic spike** on Grandpa. His card on the phone turns amber as HR climbs past 150.
5. Parent taps **"Are you OK?"** on the phone. The kid's watch vibrates, they tap ✅, and the phone shows a green check.
6. Send a check-in to Grandpa and **don't answer** it in the panel. After 30 s it escalates and the whole family is alerted.
7. In the panel, hit **Trigger FALL** on Grandpa. The phone goes red with "Grandpa fell, Mom is closest (400 m)", and the panel's event list shows Mom got the rank-1 alert.
8. Finally, show the *real* fall detector: "Simulate fall" on the watch counts down 15 s, then sends the alert.
7. Close on the sensor list (HR, GPS, compass, accelerometer, barometer, SpO₂, temperature) and what comes next: background service, real push, auth, geofences ("arrived at school").

## Out of scope (cut on purpose)

Auth and real accounts, a database, remote push notifications, the background service, multiple families, and privacy controls. Mention each one under "next steps" instead of building it.

## Risks and mitigations

- **Simulator HTTPS/network quirks:** use the ngrok HTTPS URL, and test the first `makeWebRequest` in the first hour.
- **Monkey C learning curve:** keep the watch UI to plain `dc.drawText` and `dc.fillPolygon` (for the arrow). No custom fonts or layouts.
- **Running out of time:** priority order is telemetry → family list → app map → SOS → check-in → compass arrow → fall detection.
- **Live demo fails:** keep the backup video. The simulator panel can trigger every alert even if the watch app misbehaves.
