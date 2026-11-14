# Family Wellness

A family safety network that lives on Garmin watches: live heart rate, location and direction for every family member, fall detection, SOS alerts routed to the closest person, and "Are you OK?" check-ins sent from one watch to another.

**Start here: [PLAN.md](PLAN.md).** It has the architecture, the API contract everyone codes against, who owns what, the timeline and the demo script.

## Repo layout

| Path | What | Owner |
|---|---|---|
| `/` (`manifest.xml`, `source/`, `resources/`) | Connect IQ watch app (Monkey C): screens | Person A |
| `/` (`source/`, data layer + sensors) | Connect IQ watch app (Monkey C): `FamilyState`, networking, fall detection | Person C |
| `/server` | Node + Express API (in-memory) and `demo.sh` | Person B |

Nothing beyond the Connect IQ template is built yet.

## Demo setup

The Connect IQ simulator runs one instance per Mac, so the demo uses two laptops. Each one runs the same watch app with a different `memberId` (`dad` / `kid`) set in the app's settings, and both point at the shared server URL.
