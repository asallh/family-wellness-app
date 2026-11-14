# Family Wellness

A family safety network on Garmin watches: live heart rate, location and direction for every family member, fall detection, SOS alerts routed to the closest person, and "Are you OK?" check-ins.

**Start here: [PLAN.md](PLAN.md).** It has the architecture, the API contract everyone codes against, who owns what, the timeline and the demo script.

## Repo layout

| Path | What | Owner |
|---|---|---|
| `/` (`manifest.xml`, `source/`, `resources/`) | Connect IQ watch app (Monkey C) | Person A |
| `/server` | Node + Express API (in-memory) | Person B |
| `/app` | Expo React Native parent app | Person C |
| `/tools/family_sim.py` | Desktop panel that simulates family members (planned) | Person B |

Nothing beyond the Connect IQ template is built yet. Each folder appears as its owner starts work.
