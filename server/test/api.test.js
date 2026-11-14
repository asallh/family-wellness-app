import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { FamilyStore, STALE_MS, CHECKIN_TIMEOUT_MS } from "../src/store.js";

// Two watches ~500 m apart (Dad north of Kid).
const DAD = { lat: 38.86, lon: -94.8 };
const KID = { lat: 38.8555, lon: -94.8 };

let clock, store, server, base;

beforeEach(async () => {
  clock = 1_000_000;
  store = new FamilyStore({ now: () => clock });
  server = createApp({ store, log: () => {} }).listen(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});

afterEach(() => new Promise((r) => server.close(r)));

async function call(method, path, body) {
  const res = await fetch(base + path, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}
const get = (p) => call("GET", p);
const post = (p, b = {}) => call("POST", p, b);
const member = async (id) => (await get("/family")).body.find((m) => m.id === id);
const inbox = async (id) => (await get(`/members/${id}/inbox`)).body;

async function bothWatchesOnline(extra = {}) {
  await post("/members/dad/telemetry", { hr: 70, spo2: 98, ...DAD, ...extra });
  await post("/members/kid/telemetry", { hr: 90, spo2: 99, ...KID });
}

test("family lists all four members; watches start stale, seeded members are ok", async () => {
  const { status, body } = await get("/family");
  assert.equal(status, 200);
  assert.deepEqual(body.map((m) => m.id), ["dad", "kid", "mom", "grandpa"]);
  assert.equal(body.find((m) => m.id === "dad").status, "stale");
  const mom = body.find((m) => m.id === "mom");
  assert.equal(mom.status, "ok");
  assert.equal(mom.seeded, true);
  assert.ok(mom.hr > 60 && mom.hr < 80);
  assert.ok(typeof mom.lat === "number");
});

test("telemetry updates the member, and they go stale after 30 s of silence", async () => {
  const r = await post("/members/dad/telemetry", { hr: 72, spo2: 97, temp: 31.24, ...DAD, heading: 90, alt: 300, battery: 80 });
  assert.deepEqual(r.body, { ok: true });
  let dad = await member("dad");
  assert.equal(dad.status, "ok");
  assert.equal(dad.hr, 72);
  assert.equal(dad.temp, 31.2);
  assert.equal(dad.lastSeen, 0);

  // A null reading keeps the last value.
  await post("/members/dad/telemetry", { hr: null, spo2: 96 });
  dad = await member("dad");
  assert.equal(dad.hr, 72);
  assert.equal(dad.spo2, 96);

  clock += STALE_MS + 1000;
  dad = await member("dad");
  assert.equal(dad.status, "stale");
  assert.equal(dad.lastSeen, 31);
});

test("a no-fix position (180, 180) is ignored, other fields still saved", async () => {
  await post("/members/dad/telemetry", { ...DAD });
  const r = await post("/members/dad/telemetry", { hr: 75, lat: 180, lon: 180 });
  assert.equal(r.status, 200);
  const dad = await member("dad");
  assert.equal(dad.lat, DAD.lat);
  assert.equal(dad.hr, 75);
});

test("seeded members are placed around the live watches", async () => {
  await bothWatchesOnline();
  const mom = await member("mom");
  // Mom is seeded ~400 m from the watches' midpoint.
  assert.ok(Math.abs(mom.lat - 38.8578) < 0.01, `mom.lat ${mom.lat}`);
});

test("health alert fires once per crossing and goes to everyone else", async () => {
  await bothWatchesOnline();
  await post("/members/dad/telemetry", { hr: 162 });
  await post("/members/dad/telemetry", { hr: 165 }); // still high: no new event

  const kidInbox = await inbox("kid");
  assert.equal(kidInbox.length, 1);
  assert.deepEqual(
    { type: kidInbox[0].type, from: kidInbox[0].from, fromName: kidInbox[0].fromName, reason: kidInbox[0].reason, value: kidInbox[0].value },
    { type: "health", from: "dad", fromName: "Dad", reason: "hr_high", value: 162 },
  );
  assert.equal((await inbox("dad")).length, 0, "sender doesn't alert themselves");
  assert.equal((await member("dad")).status, "alert");

  // Recover, then cross again: a second event.
  await post("/members/dad/telemetry", { hr: 80 });
  assert.equal((await member("dad")).status, "ok");
  await post("/members/dad/telemetry", { hr: 155 });
  assert.equal((await inbox("kid")).length, 2);

  await post("/members/kid/telemetry", { spo2: 85 });
  const dadInbox = await inbox("dad");
  assert.equal(dadInbox.at(-1).reason, "spo2_low");
});

test("SOS goes to everyone else with distance; rank only counts live watches", async () => {
  await bothWatchesOnline();
  const r = await post("/members/grandpa/sos", { type: "manual" });
  assert.equal(r.status, 200);
  assert.equal(r.body.notified, 3);

  const dadEv = (await inbox("dad"))[0];
  const kidEv = (await inbox("kid"))[0];
  assert.equal(dadEv.type, "sos");
  assert.equal(dadEv.from, "grandpa");
  assert.ok(dadEv.distanceM > 0 && kidEv.distanceM > 0);
  // Dad is further north, closer to Grandpa (who's seeded north-east).
  assert.ok(dadEv.distanceM < kidEv.distanceM);
  assert.equal(dadEv.rank, 1);
  assert.equal(kidEv.rank, 2);
  assert.equal((await member("grandpa")).status, "sos");
});

test("fall from a watch uses the posted position and becomes a fall event", async () => {
  await bothWatchesOnline();
  await post("/members/kid/sos", { type: "fall", lat: 38.85, lon: -94.8 });
  const ev = (await inbox("dad"))[0];
  assert.equal(ev.type, "fall");
  assert.equal(ev.lat, 38.85);
  assert.ok(Math.abs(ev.distanceM - 1112) < 5, `distance ${ev.distanceM}`);
  assert.equal(ev.rank, 1);
});

test("check-in answered OK: reply goes back to the asker, both directions", async () => {
  await bothWatchesOnline();

  // Dad checks on Kid.
  const { body } = await post("/members/kid/checkin", { from: "dad" });
  const prompt = (await inbox("kid"))[0];
  assert.equal(prompt.eventId, body.eventId);
  assert.equal(prompt.type, "checkin");
  assert.equal(prompt.from, "dad");

  await post(`/events/${prompt.eventId}/ack`, { by: "kid", response: "ok" });
  assert.equal((await inbox("kid")).length, 0, "acked prompt leaves the inbox");
  const reply = (await inbox("dad"))[0];
  assert.equal(reply.type, "checkin_reply");
  assert.equal(reply.from, "kid");
  assert.equal(reply.response, "ok");

  // No escalation later.
  clock += CHECKIN_TIMEOUT_MS + 5000;
  await bothWatchesOnline();
  assert.equal((await inbox("dad")).length, 1);

  // Kid checks on Dad: same flow the other way.
  await post("/members/dad/checkin", { from: "kid" });
  const p2 = (await inbox("dad")).find((e) => e.type === "checkin");
  assert.equal(p2.from, "kid");
});

test("check-in answered HELP: reply plus SOS to everyone", async () => {
  await bothWatchesOnline();
  await post("/members/kid/checkin", { from: "dad" });
  const prompt = (await inbox("kid"))[0];
  await post(`/events/${prompt.eventId}/ack`, { by: "kid", response: "help" });

  const types = (await inbox("dad")).map((e) => `${e.type}:${e.response ?? e.reason}`);
  assert.deepEqual(types, ["checkin_reply:help", "sos:checkin_help"]);
  assert.equal((await member("kid")).status, "sos");
});

test("unanswered check-in escalates to SOS after 30 s (seeded members never answer)", async () => {
  await bothWatchesOnline();
  await post("/members/grandpa/checkin", { from: "kid" });

  clock += CHECKIN_TIMEOUT_MS - 1000;
  store.tick();
  assert.equal((await inbox("kid")).length, 0);
  // Grandpa's prompt shows 1 s left on the countdown.
  assert.equal((await inbox("grandpa"))[0].expiresInSec, 1);

  clock += 2000;
  await bothWatchesOnline(); // keep watches live
  store.tick();
  const ev = (await inbox("kid"))[0];
  assert.equal(ev.type, "sos");
  assert.equal(ev.from, "grandpa");
  assert.equal(ev.reason, "checkin_timeout");
  assert.equal((await inbox("dad"))[0].type, "sos");
});

test("acking 'seen' clears an alert without answering a check-in", async () => {
  await bothWatchesOnline();
  await post("/members/dad/sos", {});
  const ev = (await inbox("kid"))[0];
  await post(`/events/${ev.eventId}/ack`, { by: "kid", response: "seen" });
  assert.equal((await inbox("kid")).length, 0);
});

test("bad input gets a JSON error", async () => {
  assert.equal((await get("/members/bob/inbox")).status, 404);
  assert.equal((await post("/members/dad/telemetry", { hr: "fast" })).status, 400);
  assert.equal((await post("/members/dad/checkin", { from: "dad" })).status, 400);
  assert.equal((await post("/members/dad/checkin", {})).status, 400);
  assert.equal((await post("/members/dad/sos", { type: "boom" })).status, 400);
  assert.equal((await post("/events/e999/ack", { by: "dad" })).status, 404);

  const res = await fetch(`${base}/members/dad/telemetry`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{not json",
  });
  assert.equal(res.status, 400);
  assert.equal((await res.json()).ok, false);
});

test("reset clears events and statuses but keeps watch telemetry", async () => {
  await bothWatchesOnline();
  await post("/members/kid/sos", {});
  await post("/members/dad/telemetry", { hr: 170 });
  await post("/debug/reset");

  assert.equal((await inbox("dad")).length, 0);
  assert.equal((await inbox("kid")).length, 0);
  const kid = await member("kid");
  assert.equal(kid.status, "ok");
  assert.equal(kid.hr, 90);
});
