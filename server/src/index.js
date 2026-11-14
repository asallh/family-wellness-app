import { createApp } from "./app.js";
import { FamilyStore } from "./store.js";

const port = Number(process.env.PORT ?? 3000);
const store = new FamilyStore();
const app = createApp({ store, verbose: process.env.LOG === "verbose" });

// Check-in escalation and other time-based rules.
setInterval(() => store.tick(), 1000).unref();

app.listen(port, () => {
  console.log(`Family Wellness server on http://localhost:${port}`);
  console.log("Members: dad, kid (watches) + mom, grandpa (seeded). Set LOG=verbose to log every poll.");
});
