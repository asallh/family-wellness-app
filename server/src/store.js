// All family state and server rules live here, separate from HTTP, so they can
// be tested with a fake clock. Everything is in memory: a restart is a clean slate.

export const STALE_MS = 30_000; // no telemetry for this long -> "stale"
export const CHECKIN_TIMEOUT_MS = 30_000; // unanswered check-in -> SOS
export const SOS_STATUS_MS = 120_000; // how long a member shows "sos" after raising one

export const THRESHOLDS = {
  hrHigh: 150, // bpm, alert when above
  hrLow: 40, // bpm, alert when below
  spo2Low: 90, // %, alert when below
};

// Where seeded members sit until a real watch reports a position. Seeded members
// are placed relative to the live watches, so distances stay realistic wherever
// the simulators' GPS is set.
const DEFAULT_ANCHOR = {
  lat: Number(process.env.SEED_LAT ?? 38.8554),
  lon: Number(process.env.SEED_LON ?? -94.7995),
};

const MEMBERS = [
  // The two watches (./start.sh mom, ./start.sh son).
  { id: "mom", name: "Mom" },
  { id: "son", name: "Son" },
  // Seeded: always "online", plausible vitals, never answer check-ins.
  { id: "dad", name: "Dad", seed: { north: 350, east: -200, hr: 72, spo2: 98, temp: 32.4, alt: 310, battery: 76 } },
  { id: "grandpa", name: "Grandpa", seed: { north: 900, east: 600, hr: 64, spo2: 95, temp: 31.8, alt: 325, battery: 54 } },
];

const TELEMETRY_FIELDS = ["hr", "spo2", "temp", "lat", "lon", "heading", "alt", "battery"];

export function haversineM(a, b) {
  const R = 6_371_000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function offset(anchor, north, east) {
  return {
    lat: anchor.lat + north / 111_320,
    lon: anchor.lon + east / (111_320 * Math.cos((anchor.lat * Math.PI) / 180)),
  };
}

/** True for a real coordinate pair. Missing values count as "nothing to ignore". */
function validPosition(lat, lon) {
  if (typeof lat !== "number" || typeof lon !== "number") return true;
  return Math.abs(lat) <= 90 && Math.abs(lon) < 180;
}

const round = (v, digits = 0) => (v == null ? null : Number(v.toFixed(digits)));

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export class FamilyStore {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.nextEventNum = 1;
    this.members = new Map();
    for (const m of MEMBERS) {
      this.members.set(m.id, { id: m.id, name: m.name, seed: m.seed ?? null });
    }
    this.reset();
  }

  // ---- state lifecycle ------------------------------------------------------

  /** Clears events, check-ins, SOS, alert state and feeder pins. Live watches keep their last telemetry. */
  reset() {
    this.events = new Map(); // eventId -> event (with per-recipient delivery state)
    this.checkins = new Map(); // eventId -> { target, asker, deadline, resolved }
    this.overrides = new Map(); // memberId -> { field: value } pinned by the data feeder
    for (const m of this.members.values()) {
      m.sosUntil = 0;
      m.breaches = { hrHigh: false, hrLow: false, spo2Low: false };
      if (m.seed) {
        Object.assign(m, {
          hr: m.seed.hr, spo2: m.seed.spo2, temp: m.seed.temp, alt: m.seed.alt,
          battery: m.seed.battery, heading: null, lat: null, lon: null,
          lastSeen: null, positionOverridden: false,
        });
      } else if (m.lastSeen === undefined) {
        Object.assign(m, {
          hr: null, spo2: null, temp: null, alt: null, battery: null,
          heading: null, lat: null, lon: null, lastSeen: null,
        });
      }
    }
  }

  /** Runs time-based rules. Call about once a second. */
  tick() {
    const now = this.now();
    for (const [eventId, c] of this.checkins) {
      if (c.resolved || now < c.deadline) continue;
      c.resolved = true;
      // The prompt has expired, so drop it from the target's inbox and alert everyone.
      const delivery = this.events.get(eventId)?.delivery.get(c.target);
      if (delivery) delivery.acked = true;
      this.raiseSos(c.target, { type: "manual", reason: "checkin_timeout" });
    }
  }

  // ---- members --------------------------------------------------------------

  getMember(id) {
    const m = this.members.get(id);
    if (!m) throw new HttpError(404, `Unknown member "${id}". Known: ${[...this.members.keys()].join(", ")}`);
    return m;
  }

  isLive(m) {
    if (m.seed) return true;
    return m.lastSeen != null && this.now() - m.lastSeen < STALE_MS;
  }

  /** Position of a member, placing seeded members around the live watches. */
  position(m) {
    if (m.lat != null && m.lon != null && (!m.seed || m.positionOverridden)) return { lat: m.lat, lon: m.lon };
    if (!m.seed) return null;
    return offset(this.anchor(), m.seed.north, m.seed.east);
  }

  anchor() {
    const live = [...this.members.values()].filter((m) => !m.seed && m.lat != null && m.lon != null);
    if (live.length === 0) return DEFAULT_ANCHOR;
    return {
      lat: live.reduce((s, m) => s + m.lat, 0) / live.length,
      lon: live.reduce((s, m) => s + m.lon, 0) / live.length,
    };
  }

  /** Seeded heart rates wander a little so they look live. */
  displayHr(m) {
    if (m.hr == null || !m.seed) return m.hr;
    const t = this.now() / 1000;
    return m.hr + Math.round(2 * Math.sin(t / 7 + m.seed.north));
  }

  status(m) {
    const now = this.now();
    if (m.sosUntil > now) return "sos";
    if (!this.isLive(m)) return "stale";
    if (Object.values(m.breaches).some(Boolean)) return "alert";
    return "ok";
  }

  family() {
    const now = this.now();
    return [...this.members.values()].map((m) => {
      const pos = this.position(m);
      return {
        id: m.id,
        name: m.name,
        hr: round(this.displayHr(m)),
        spo2: round(m.spo2),
        temp: round(m.temp, 1),
        alt: round(m.alt),
        battery: round(m.battery),
        heading: round(m.heading),
        lat: pos ? round(pos.lat, 6) : null,
        lon: pos ? round(pos.lon, 6) : null,
        status: this.status(m),
        // Seconds since the last telemetry (small integer, easy on the watch).
        lastSeen: m.seed ? 0 : m.lastSeen == null ? null : Math.round((now - m.lastSeen) / 1000),
        seeded: Boolean(m.seed),
      };
    });
  }

  // ---- telemetry + health rule ------------------------------------------------

  recordTelemetry(id, body) {
    const m = this.getMember(id);
    if (body == null || typeof body !== "object" || Array.isArray(body)) {
      throw new HttpError(400, "Body must be a JSON object");
    }
    // Watches without a GPS fix can report (180, 180); keep the last real position instead.
    const ignorePosition = !validPosition(body.lat, body.lon);
    const pinned = this.overrides.get(id) ?? {};
    for (const key of TELEMETRY_FIELDS) {
      if (!(key in body)) continue;
      if (key in pinned) continue; // the data feeder owns this field
      const v = body[key];
      if (v === null) continue; // a sensor with no reading keeps its last value
      if (typeof v !== "number" || !Number.isFinite(v)) throw new HttpError(400, `"${key}" must be a number or null`);
      if ((key === "lat" || key === "lon") && ignorePosition) continue;
      m[key] = v;
    }
    if (m.seed && ("lat" in body || "lon" in body) && m.lat != null && m.lon != null) m.positionOverridden = true;
    if (!m.seed) m.lastSeen = this.now();
    this.checkHealth(m);
    return { ok: true };
  }

  /** Sends a "health" event the moment a vital crosses a threshold, once per crossing. */
  checkHealth(m) {
    const checks = [
      ["hrHigh", m.hr, (v) => v > THRESHOLDS.hrHigh, "hr_high"],
      ["hrLow", m.hr, (v) => v < THRESHOLDS.hrLow, "hr_low"],
      ["spo2Low", m.spo2, (v) => v < THRESHOLDS.spo2Low, "spo2_low"],
    ];
    for (const [key, value, breached, reason] of checks) {
      if (value == null) continue;
      const now = breached(value);
      if (now && !m.breaches[key]) {
        this.broadcast(m, { type: "health", reason, value: round(value) });
      }
      m.breaches[key] = now;
    }
  }

  // ---- data feeder overrides --------------------------------------------------

  /**
   * Pins fake values for a member (from tools/feeder.py). A number pins that
   * field, so the watch's own telemetry can't overwrite it; null releases it.
   * Pinned values are applied right away as telemetry, so health alerts fire
   * and a member with no watch running stays live while the feeder sends.
   */
  setOverride(id, body) {
    const m = this.getMember(id);
    if (body == null || typeof body !== "object" || Array.isArray(body)) {
      throw new HttpError(400, "Body must be a JSON object");
    }
    const pins = { ...(this.overrides.get(id) ?? {}) };
    if (body.clear === true) for (const k of Object.keys(pins)) delete pins[k];
    for (const key of TELEMETRY_FIELDS) {
      if (!(key in body)) continue;
      const v = body[key];
      if (v === null) {
        delete pins[key];
      } else if (typeof v !== "number" || !Number.isFinite(v)) {
        throw new HttpError(400, `"${key}" must be a number or null`);
      } else {
        pins[key] = v;
      }
    }
    if (("lat" in pins) !== ("lon" in pins)) throw new HttpError(400, "pin lat and lon together");
    if ("lat" in pins && !validPosition(pins.lat, pins.lon)) throw new HttpError(400, "lat/lon out of range");
    if (Object.keys(pins).length === 0) this.overrides.delete(id);
    else this.overrides.set(id, pins);

    // Apply the pins as a telemetry report from this member.
    for (const [k, v] of Object.entries(pins)) m[k] = v;
    if (m.seed && "lat" in pins) m.positionOverridden = true;
    // Any feeder send counts as hearing from the member, except releasing everything.
    if (!m.seed && body.clear !== true) m.lastSeen = this.now();
    this.checkHealth(m);
    return { ok: true, pinned: pins };
  }

  overridesSnapshot() {
    return Object.fromEntries(this.overrides);
  }

  // ---- events -----------------------------------------------------------------

  newEventId() {
    return `e${this.nextEventNum++}`;
  }

  /**
   * Sends an event from `from` to every other member. Each recipient gets the
   * distance to the sender, and live recipients are ranked by distance
   * (rank 1 = closest member who can actually respond).
   */
  broadcast(from, fields) {
    const origin = this.position(from);
    const recipients = [...this.members.values()].filter((r) => r.id !== from.id);
    const withDistance = recipients.map((r) => {
      const pos = this.position(r);
      return { r, distanceM: origin && pos ? haversineM(origin, pos) : null };
    });
    const rankable = withDistance
      .filter((x) => !x.r.seed && this.isLive(x.r) && x.distanceM != null)
      .sort((a, b) => a.distanceM - b.distanceM);
    const rankOf = new Map(rankable.map((x, i) => [x.r.id, i + 1]));

    const event = {
      eventId: this.newEventId(),
      createdAt: this.now(),
      from: from.id,
      fromName: from.name,
      lat: origin ? round(origin.lat, 6) : null,
      lon: origin ? round(origin.lon, 6) : null,
      ...fields,
      delivery: new Map(
        withDistance.map(({ r, distanceM }) => [
          r.id,
          { distanceM: distanceM == null ? null : Math.round(distanceM), rank: rankOf.get(r.id) ?? null, acked: false },
        ]),
      ),
    };
    this.events.set(event.eventId, event);
    return event;
  }

  /** Sends an event to exactly one member. */
  sendTo(target, from, fields) {
    const origin = this.position(from);
    const pos = this.position(target);
    const event = {
      eventId: this.newEventId(),
      createdAt: this.now(),
      from: from.id,
      fromName: from.name,
      lat: origin ? round(origin.lat, 6) : null,
      lon: origin ? round(origin.lon, 6) : null,
      ...fields,
      delivery: new Map([
        [target.id, { distanceM: origin && pos ? Math.round(haversineM(origin, pos)) : null, rank: null, acked: false }],
      ]),
    };
    this.events.set(event.eventId, event);
    return event;
  }

  /** `type` "manual" (the SOS button) becomes an "sos" event; "fall" stays "fall". */
  raiseSos(id, { type = "manual", lat, lon, reason } = {}) {
    if (!["manual", "sos", "fall"].includes(type)) throw new HttpError(400, 'type must be "manual" or "fall"');
    const m = this.getMember(id);
    if (lat != null || lon != null) {
      if (typeof lat !== "number" || typeof lon !== "number") throw new HttpError(400, "lat and lon must both be numbers");
      if (validPosition(lat, lon)) {
        m.lat = lat;
        m.lon = lon;
        if (m.seed) m.positionOverridden = true;
      }
    }
    m.sosUntil = this.now() + SOS_STATUS_MS;
    const event = this.broadcast(m, { type: type === "fall" ? "fall" : "sos", ...(reason ? { reason } : {}) });
    return { ok: true, eventId: event.eventId, notified: event.delivery.size };
  }

  checkin(targetId, fromId) {
    const target = this.getMember(targetId);
    if (typeof fromId !== "string") throw new HttpError(400, '"from" is required');
    const asker = this.getMember(fromId);
    if (asker.id === target.id) throw new HttpError(400, "A member can't check in on themselves");
    const event = this.sendTo(target, asker, { type: "checkin" });
    this.checkins.set(event.eventId, {
      target: target.id,
      asker: asker.id,
      deadline: this.now() + CHECKIN_TIMEOUT_MS,
      resolved: false,
    });
    return { ok: true, eventId: event.eventId };
  }

  ack(eventId, by, response) {
    const event = this.events.get(eventId);
    if (!event) throw new HttpError(404, `Unknown event "${eventId}"`);
    this.getMember(by);
    const delivery = event.delivery.get(by);
    if (!delivery) throw new HttpError(400, `Event "${eventId}" wasn't sent to "${by}"`);
    if (!["ok", "help", "seen"].includes(response)) throw new HttpError(400, 'response must be "ok", "help" or "seen"');
    delivery.acked = true;

    const checkin = this.checkins.get(eventId);
    if (event.type === "checkin" && checkin && !checkin.resolved && response !== "seen") {
      checkin.resolved = true;
      const target = this.getMember(checkin.target);
      this.sendTo(this.getMember(checkin.asker), target, { type: "checkin_reply", response });
      if (response === "help") this.raiseSos(target.id, { type: "manual", reason: "checkin_help" });
    }
    return { ok: true };
  }

  inbox(id) {
    this.getMember(id);
    const out = [];
    for (const e of this.events.values()) {
      const d = e.delivery.get(id);
      if (!d || d.acked) continue;
      const checkin = this.checkins.get(e.eventId);
      out.push({
        eventId: e.eventId,
        type: e.type,
        from: e.from,
        fromName: e.fromName,
        lat: e.lat,
        lon: e.lon,
        distanceM: d.distanceM,
        rank: d.rank,
        response: e.response ?? null,
        reason: e.reason ?? null,
        value: e.value ?? null,
        ageSec: Math.round((this.now() - e.createdAt) / 1000),
        // Seconds left to answer a check-in before it escalates (drives the watch countdown).
        expiresInSec: checkin ? Math.max(0, Math.ceil((checkin.deadline - this.now()) / 1000)) : null,
      });
    }
    return out;
  }
}
