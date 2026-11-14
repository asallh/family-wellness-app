import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { FamilyStore, STALE_MS, CHECKIN_TIMEOUT_MS } from "../src/store.js";

// Two watches ~500 m apart (Mom north of Son).
const MOM = { lat: 38.86, lon: -94.8 };
const SON = { lat: 38.8555, lon: -94.8 };

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
  await post("/members/mom/telemetry", { hr: 70, spo2: 98, ...MOM, ...extra });
  await post("/members/son/telemetry", { hr: 90, spo2: 99, ...SON });
}

test("family lists all four members; watches start stale, seeded members are ok", async () => {
  const { status, body } = await get("/family");
  assert.equal(status, 200);
  assert.deepEqual(body.map((m) => m.id), ["mom", "son", "dad", "grandpa"]);
  assert.equal(body.find((m) => m.id === "mom").status, "stale");
  const dad = body.find((m) => m.id === "dad");
  assert.equal(dad.status, "ok");
  assert.equal(dad.seeded, true);
  assert.ok(dad.hr > 60 && dad.hr < 80);
  assert.ok(typeof dad.lat === "number");
});

test("telemetry updates the member, and they go stale after 30 s of silence", async () => {
  const r = await post("/members/mom/telemetry", { hr: 72, spo2: 97, temp: 31.24, ...MOM, heading: 90, alt: 300, battery: 80 });
  assert.deepEqual(r.body, { ok: true });
  let mom = await member("mom");
  assert.equal(mom.status, "ok");
  assert.equal(mom.hr, 72);
  assert.equal(mom.temp, 31.2);
  assert.equal(mom.lastSeen, 0);

  // A null reading keeps the last value.
  await post("/members/mom/telemetry", { hr: null, spo2: 96 });
  mom = await member("mom");
  assert.equal(mom.hr, 72);
  assert.equal(mom.spo2, 96);

  clock += STALE_MS + 1000;
  mom = await member("mom");
  assert.equal(mom.status, "stale");
  assert.equal(mom.lastSeen, 31);
});

test("a no-fix position (180, 180) is ignored, other fields still saved", async () => {
  await post("/members/mom/telemetry", { ...MOM });
  const r = await post("/members/mom/telemetry", { hr: 75, lat: 180, lon: 180 });
  assert.equal(r.status, 200);
  const mom = await member("mom");
  assert.equal(mom.lat, MOM.lat);
  assert.equal(mom.hr, 75);
});

test("seeded members are placed around the live watches", async () => {
  await bothWatchesOnline();
  const dad = await member("dad");
  // Dad is seeded ~400 m from the watches' midpoint.
  assert.ok(Math.abs(dad.lat - 38.8578) < 0.01, `dad.lat ${dad.lat}`);
});

test("health alert fires once per crossing and goes to everyone else", async () => {
  await bothWatchesOnline();
  await post("/members/mom/telemetry", { hr: 162 });
  await post("/members/mom/telemetry", { hr: 165 }); // still high: no new event

  const sonInbox = await inbox("son");
  assert.equal(sonInbox.length, 1);
  assert.deepEqual(
    { type: sonInbox[0].type, from: sonInbox[0].from, fromName: sonInbox[0].fromName, reason: sonInbox[0].reason, value: sonInbox[0].value },
    { type: "health", from: "mom", fromName: "Mom", reason: "hr_high", value: 162 },
  );
  assert.equal((await inbox("mom")).length, 0, "sender doesn't alert themselves");
  assert.equal((await member("mom")).status, "alert");

  // Recover, then cross again: a second event.
  await post("/members/mom/telemetry", { hr: 80 });
  assert.equal((await member("mom")).status, "ok");
  await post("/members/mom/telemetry", { hr: 155 });
  assert.equal((await inbox("son")).length, 2);

  await post("/members/son/telemetry", { spo2: 85 });
  const momInbox = await inbox("mom");
  assert.equal(momInbox.at(-1).reason, "spo2_low");
});

test("SOS goes to everyone else with distance; rank only counts live watches", async () => {
  await bothWatchesOnline();
  const r = await post("/members/grandpa/sos", { type: "manual" });
  assert.equal(r.status, 200);
  assert.equal(r.body.notified, 3);

  const momEv = (await inbox("mom"))[0];
  const sonEv = (await inbox("son"))[0];
  assert.equal(momEv.type, "sos");
  assert.equal(momEv.from, "grandpa");
  assert.ok(momEv.distanceM > 0 && sonEv.distanceM > 0);
  // Mom is further north, closer to Grandpa (who's seeded north-east).
  assert.ok(momEv.distanceM < sonEv.distanceM);
  assert.equal(momEv.rank, 1);
  assert.equal(sonEv.rank, 2);
  assert.equal((await member("grandpa")).status, "sos");
});

test("fall from a watch uses the posted position and becomes a fall event", async () => {
  await bothWatchesOnline();
  await post("/members/son/sos", { type: "fall", lat: 38.85, lon: -94.8 });
  const ev = (await inbox("mom"))[0];
  assert.equal(ev.type, "fall");
  assert.equal(ev.lat, 38.85);
  assert.ok(Math.abs(ev.distanceM - 1112) < 5, `distance ${ev.distanceM}`);
  assert.equal(ev.rank, 1);
});

test("check-in answered OK: reply goes back to the asker, both directions", async () => {
  await bothWatchesOnline();

  // Mom checks on Son.
  const { body } = await post("/members/son/checkin", { from: "mom" });
  const prompt = (await inbox("son"))[0];
  assert.equal(prompt.eventId, body.eventId);
  assert.equal(prompt.type, "checkin");
  assert.equal(prompt.from, "mom");

  await post(`/events/${prompt.eventId}/ack`, { by: "son", response: "ok" });
  assert.equal((await inbox("son")).length, 0, "acked prompt leaves the inbox");
  const reply = (await inbox("mom"))[0];
  assert.equal(reply.type, "checkin_reply");
  assert.equal(reply.from, "son");
  assert.equal(reply.response, "ok");

  // No escalation later.
  clock += CHECKIN_TIMEOUT_MS + 5000;
  await bothWatchesOnline();
  assert.equal((await inbox("mom")).length, 1);

  // Son checks on Mom: same flow the other way.
  await post("/members/mom/checkin", { from: "son" });
  const p2 = (await inbox("mom")).find((e) => e.type === "checkin");
  assert.equal(p2.from, "son");
});

test("check-in answered HELP: reply plus SOS to everyone", async () => {
  await bothWatchesOnline();
  await post("/members/son/checkin", { from: "mom" });
  const prompt = (await inbox("son"))[0];
  await post(`/events/${prompt.eventId}/ack`, { by: "son", response: "help" });

  const types = (await inbox("mom")).map((e) => `${e.type}:${e.response ?? e.reason}`);
  assert.deepEqual(types, ["checkin_reply:help", "sos:checkin_help"]);
  assert.equal((await member("son")).status, "sos");
});

test("unanswered check-in escalates to SOS after 30 s (seeded members never answer)", async () => {
  await bothWatchesOnline();
  await post("/members/grandpa/checkin", { from: "son" });

  clock += CHECKIN_TIMEOUT_MS - 1000;
  store.tick();
  assert.equal((await inbox("son")).length, 0);
  // Grandpa's prompt shows 1 s left on the countdown.
  assert.equal((await inbox("grandpa"))[0].expiresInSec, 1);

  clock += 2000;
  await bothWatchesOnline(); // keep watches live
  store.tick();
  const ev = (await inbox("son"))[0];
  assert.equal(ev.type, "sos");
  assert.equal(ev.from, "grandpa");
  assert.equal(ev.reason, "checkin_timeout");
  assert.equal((await inbox("mom"))[0].type, "sos");
});

test("acking 'seen' clears an alert without answering a check-in", async () => {
  await bothWatchesOnline();
  await post("/members/mom/sos", {});
  const ev = (await inbox("son"))[0];
  await post(`/events/${ev.eventId}/ack`, { by: "son", response: "seen" });
  assert.equal((await inbox("son")).length, 0);
});

test("bad input gets a JSON error", async () => {
  assert.equal((await get("/members/bob/inbox")).status, 404);
  assert.equal((await post("/members/mom/telemetry", { hr: "fast" })).status, 400);
  assert.equal((await post("/members/mom/checkin", { from: "mom" })).status, 400);
  assert.equal((await post("/members/mom/checkin", {})).status, 400);
  assert.equal((await post("/members/mom/sos", { type: "boom" })).status, 400);
  assert.equal((await post("/events/e999/ack", { by: "mom" })).status, 404);

  const res = await fetch(`${base}/members/mom/telemetry`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{not json",
  });
  assert.equal(res.status, 400);
  assert.equal((await res.json()).ok, false);
});

test("reset clears events and statuses but keeps watch telemetry", async () => {
  await bothWatchesOnline();
  await post("/members/son/sos", {});
  await post("/members/mom/telemetry", { hr: 170 });
  await post("/debug/reset");

  assert.equal((await inbox("mom")).length, 0);
  assert.equal((await inbox("son")).length, 0);
  const son = await member("son");
  assert.equal(son.status, "ok");
  assert.equal(son.hr, 90);
});
