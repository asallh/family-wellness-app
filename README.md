# Family Wellness

A two-way family safety network that lives on Garmin watches. Every member sees every other member's live heart rate, location and direction. Anyone can send "Are you OK?" to anyone. An SOS or fall on any watch alerts the whole family, closest person first. Parents keep an eye on kids, and kids keep an eye on parents and grandparents.

**The full plan is in [PLAN.md](PLAN.md):** the architecture, the API contract, who owns what, the timeline and the demo script.

> **Status:** only the Connect IQ template exists so far. The `/server` folder, `source/Config.mc` and the in-app menus described below are still to be built. The commands are the ones we'll use once they are.

## Two ways to run it

| | **Local mode** (day-to-day dev) | **Shared mode** (testing together, and the demo) |
|---|---|---|
| Server | Each person runs their own on `localhost:3000` | **One** person runs it and shares it through ngrok |
| Watch app points at | `http://localhost:3000` | `https://<team-domain>.ngrok-free.app` |
| Who's in the family | Your simulator + seeded Mom and Grandpa (driven with `demo.sh`) | Both laptops' simulators (Dad + Kid) + seeded Mom and Grandpa |
| Two-way features between laptops | ❌ Each local server is its own separate family | ✅ |

**Important:** watches only see each other if they talk to the *same* server. Local mode is for building and testing alone. Whenever the two laptops' simulators need to see each other, switch both to shared mode.

We're building and demoing **on simulators only**. The physical fēnix 7 is a stretch goal (see the end of this file).

> **One simulator per Mac.** The Connect IQ simulator can't run twice on the same machine. We tested this, so don't try to work around it. To see two watches talk to each other, use **two machines** (one simulator each) pointed at the same server.

## One-time setup (everyone)

1. **VS Code + the Monkey C extension** (by Garmin).
2. **Connect IQ SDK 9.x**, installed through the Connect IQ SDK Manager. In the SDK Manager's **Devices** tab, download **fēnix® 7 Pro**, the device we simulate. (The manifest also lists `fenix7` for the stretch goal. Ignore it unless you're doing that, and always pick `fenix7pro` when VS Code asks for a device.)
3. **A developer key** to sign builds. In VS Code, run **"Monkey C: Generate a Developer Key"**. Keep it outside the repo; `.gitignore` blocks key files anyway.
4. **Node.js 20+** for the server.
5. Optional, for running the CLI commands below: put the SDK's `bin` folder on your `PATH`.

   ```bash
   export PATH="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/$(ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" | tail -1)/bin:$PATH"
   ```

## Local mode: run your own instance

**1. Start the server.** It keeps everything in memory, so a restart is a clean slate.

```bash
cd server && npm install && npm start
```

It listens on `http://localhost:3000` and seeds a fake "Mom". Check it's up:

```bash
curl http://localhost:3000/family
```

**2. Allow plain HTTP in the simulator.** Open the simulator. In its **Settings** menu, untick **"Use Device HTTPS Requirements"**, so it can call `http://localhost`.

**3. Run the watch app in the simulator.** In VS Code, open the repo folder and press **F5** (Run → Start Debugging), then pick `fenix7pro`. Or use the CLI:

```bash
connectiq
```

```bash
monkeyc -f monkey.jungle -d fenix7pro -o bin/app.prg -y /path/to/developer_key
```

```bash
monkeydo bin/app.prg fenix7pro
```

**4. In the watch app:** choose who you are (usually Dad or Kid; Mom and Grandpa are seeded on the server) on first launch. Leave **Menu → Server** on **Local** (the default).

**5. Fake the rest of the family** while you work alone. `server/demo.sh` sends events as any member:

```bash
./server/demo.sh checkin kid dad
```

```bash
./server/demo.sh sos grandpa
```

```bash
./server/demo.sh reset
```

Set sensor values for *your* watch in the simulator's **Simulation** menu: heart rate, GPS position, heading, or play back a FIT/GPX file.

## Shared mode: everyone on one network

**On the laptop hosting the server** (one person only):

```bash
cd server && npm start
```

```bash
ngrok http --url=<team-domain>.ngrok-free.app 3000
```

Use ngrok's **free static domain** (one per ngrok account, under Domains in the ngrok dashboard), so the URL never changes and nobody needs to rebuild. Put that domain in `SHARED_URL` in `source/Config.mc`, and commit it once.

**On both laptops' simulators:** in the watch app, set **Menu → Server** to **Shared**, and pick a different identity on each (Dad on one, Kid on the other). Two devices claiming the same member will overwrite each other.

**Quick pairing on the same Wi-Fi (no ngrok):** for testing between two machines, the second laptop can talk straight to the first one's server. The server listens on all network interfaces.

1. On the hosting laptop, run `npm start` in `server/`, then find its local IP:

   ```bash
   ipconfig getifaddr en0
   ```

2. On the other laptop, check it can reach the server:

   ```bash
   curl http://<host-ip>:3000/family
   ```

3. Temporarily set `SHARED_URL` in `source/Config.mc` to `http://<host-ip>:3000`. Don't commit this change. Keep "Use Device HTTPS Requirements" unticked in the simulator.

If the venue Wi-Fi blocks laptop-to-laptop traffic, use ngrok as described above.

## Repo layout

| Path | What | Owner |
|---|---|---|
| `manifest.xml`, `resources/`, `source/` (views) | Watch app screens (Monkey C) | Person A |
| `source/` (`FamilyState`, networking, sensors, `Config.mc`) | Watch app data layer + fall detection | Person C |
| `server/` | Node + Express API (in-memory) and `demo.sh` | Person B |

## FAQ

**Do we need a database?** No. The server keeps the family's latest telemetry and pending events in memory, which is all the features need. Losing state on restart is fine for a demo, and `/debug/reset` does it on purpose. A database only matters once you have real accounts, history or multiple families, which are all out of scope.

## Stretch: physical watch (fēnix 7)

Not part of the main build. Only try this after the feature freeze if the simulator demo is solid. The steps are in [PLAN.md → Stretch: physical watch](PLAN.md#stretch-physical-watch).
