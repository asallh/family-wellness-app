import express from "express";
import { FamilyStore, HttpError } from "./store.js";

/** Builds the Express app around a store. Tests pass in a store with a fake clock. */
export function createApp({ store = new FamilyStore(), log = console.log, verbose = false } = {}) {
  const app = express();
  app.use(express.json({ limit: "16kb" }));

  // Watches poll every 5 s, so only log writes (and everything when verbose).
  app.use((req, res, next) => {
    const started = Date.now();
    res.on("finish", () => {
      if (verbose || req.method !== "GET" || res.statusCode >= 400) {
        const body = req.method === "GET" ? "" : ` ${JSON.stringify(req.body ?? {})}`;
        log(`${req.method} ${req.originalUrl} → ${res.statusCode} (${Date.now() - started} ms)${body}`);
      }
    });
    next();
  });

  // Run time-based rules (check-in escalation) on every request too, so they
  // fire promptly even between ticks.
  app.use((_req, _res, next) => {
    store.tick();
    next();
  });

  app.get("/", (_req, res) => res.json({ ok: true, service: "family-wellness" }));

  app.get("/family", (_req, res) => res.json(store.family()));

  app.post("/members/:id/telemetry", (req, res) => res.json(store.recordTelemetry(req.params.id, req.body)));

  app.get("/members/:id/inbox", (req, res) => res.json(store.inbox(req.params.id)));

  app.post("/members/:id/sos", (req, res) => {
    const { type, lat, lon } = req.body ?? {};
    res.json(store.raiseSos(req.params.id, { type, lat, lon }));
  });

  app.post("/members/:id/checkin", (req, res) => res.json(store.checkin(req.params.id, req.body?.from)));

  app.post("/events/:eventId/ack", (req, res) => {
    const { by, response = "seen" } = req.body ?? {};
    if (typeof by !== "string") throw new HttpError(400, '"by" is required');
    res.json(store.ack(req.params.eventId, by, response));
  });

  app.post("/debug/reset", (_req, res) => {
    store.reset();
    res.json({ ok: true });
  });

  app.use((_req, res) => res.status(404).json({ ok: false, error: "Not found" }));

  // Always answer in JSON: the watch's makeWebRequest expects a JSON body.
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    const status = err.status ?? err.statusCode ?? 500;
    if (status >= 500) log(err);
    res.status(status).json({ ok: false, error: status >= 500 ? "Internal error" : err.message });
  });

  return app;
}
