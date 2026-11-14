#!/usr/bin/env python3
"""Family Wellness data feeder: set fake vitals and position for Mom or Son.

    python3 tools/feeder.py                          # local server
    python3 tools/feeder.py http://<laptop-ip>:3000  # another laptop's server
    python3 tools/feeder.py --mock son               # only fake Son (Mom is a real watch)
    python3 tools/feeder.py --manual                 # start with nothing sent

Ready for a demo as soon as it opens: Mom and Son both start with every field
ticked (normal vitals, ~500 m apart) and "Keep sending" on, so both are fed
every 5 s with no setup. Heart rate drifts by a beat or two on each send so it
looks live (never across an alert threshold). --manual starts the old way, with
nothing ticked or sent.

The "Mock" boxes (or --mock) pick whose data is faked. Untick a member that's
wearing a real watch: the feeder stops sending for them and releases anything
it had pinned, so the real sensors show through. You can still send events
(SOS, fall, check-in) as them.

Moving a slider ticks that field and sends it at once. Ticked fields are
pinned on the server (POST /debug/override/:id), so the watch's own sensor
telemetry can't overwrite them. Unticked fields are released and the watch's
real readings take over again. With "Keep sending" on, the values are re-sent
every 5 s, which also keeps a member with no simulator running from going stale.

Servers without /debug/override (older builds, e.g. main) get the values as
plain telemetry instead. If the server can't be reached, the feeder keeps
retrying every few seconds, and when it comes back (or restarts and forgets the
pins) it sends every member's ticked values again. Only needs the Python
standard library.
"""

import argparse
import json
import math
import queue
import random
import sys
import threading
import tkinter as tk
import urllib.error
import urllib.request
from tkinter import ttk

MEMBERS = [("mom", "Mom"), ("son", "Son")]
ALL_MEMBERS = ["mom", "son"]
SEND_EVERY_MS = 5000
REFRESH_MS = 2000      # poll /family this often while connected
RETRY_MS = 3000        # and this often while the server can't be reached
EDIT_DEBOUNCE_MS = 250  # wait this long after a slider stops before sending
M_PER_DEG_LAT = 111_320

# key, label, min, max, step, default
FIELDS = [
    ("hr", "Heart rate (bpm)", 30, 200, 1, 75),
    ("spo2", "SpO2 (%)", 70, 100, 1, 98),
    ("temp", "Skin temp (C)", 25, 40, 0.1, 32.5),
    ("alt", "Altitude (m)", 0, 2000, 1, 310),
    ("battery", "Battery (%)", 0, 100, 1, 80),
    ("heading", "Heading (deg)", 0, 359, 1, 0),
]

# Starting positions, ~500 m apart, around the server's default anchor.
START_POS = {"mom": (38.8599, -94.7995), "son": (38.8554, -94.7995)}

# Demo starting values per member (anything not listed uses FIELDS' default).
START_VALUES = {
    "mom": {"hr": 72, "spo2": 98, "temp": 32.4, "alt": 310, "battery": 82, "heading": 0},
    "son": {"hr": 88, "spo2": 99, "temp": 33.1, "alt": 305, "battery": 64, "heading": 0},
}

# Heart rate drifts by up to this many bpm on each streamed send.
HR_DRIFT = 2
HR_HIGH, HR_LOW = 150, 40  # the server's alert thresholds


def drift_hr(base):
    """A live-looking HR near base that stays on the same side of each threshold."""
    value = base + random.randint(-HR_DRIFT, HR_DRIFT)
    if (value > HR_HIGH) != (base > HR_HIGH) or (value < HR_LOW) != (base < HR_LOW):
        return base
    return value

PRESETS = {
    "Normal": {"hr": 75, "spo2": 98},
    "High HR (165)": {"hr": 165},
    "Low HR (35)": {"hr": 35},
    "Low SpO2 (85)": {"spo2": 85},
}


def normalize_url(text):
    """'192.168.1.20:3000' -> 'http://192.168.1.20:3000'."""
    url = text.strip().rstrip("/")
    if url and "://" not in url:
        url = "http://" + url
    return url


class Api:
    def __init__(self, base):
        self.base = normalize_url(base)

    def call(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(
            self.base + path, data=data, method=method,
            headers={"Content-Type": "application/json", "ngrok-skip-browser-warning": "1"},
        )
        try:
            with urllib.request.urlopen(req, timeout=3) as res:
                return res.status, json.loads(res.read() or b"null")
        except urllib.error.HTTPError as e:
            try:
                return e.code, json.loads(e.read())
            except ValueError:
                return e.code, None


class MemberFeed:
    """What the feeder holds for one member: values, which are pinned, streaming."""

    def __init__(self, member_id, auto=True):
        self.values = {k: d for k, _, _, _, _, d in FIELDS}
        self.values.update(START_VALUES.get(member_id, {}))
        self.values["lat"], self.values["lon"] = START_POS[member_id]
        # auto: every field ticked and streaming from the start (demo mode).
        self.pinned = {k: auto for k, *_ in FIELDS}
        self.pinned["pos"] = auto
        self.stream = auto

    def has_pins(self):
        return any(self.pinned.values())

    def pinned_values(self, live=False):
        return {k: v for k, v in self.body(live).items() if v is not None}

    def body(self, live=False):
        """What to send. live=True (the 5 s stream) lets heart rate drift."""
        out = {}
        for k, *_ in FIELDS:
            out[k] = self.values[k] if self.pinned[k] else None
        if live and out["hr"] is not None:
            out["hr"] = drift_hr(out["hr"])
        for k in ("lat", "lon"):
            out[k] = self.values[k] if self.pinned["pos"] else None
        return out


class Feeder(tk.Tk):
    def __init__(self, server, auto=True, mock=None):
        super().__init__()
        self.title("Family Wellness feeder")
        self.resizable(False, False)
        mock = set(ALL_MEMBERS if mock is None else mock)
        self.feeds = {mid: MemberFeed(mid, auto and mid in mock) for mid, _ in MEMBERS}
        # Whose data this feeder fakes. A member with a real watch is unticked.
        self.mocked = {mid: tk.BooleanVar(value=mid in mock) for mid, _ in MEMBERS}
        self.mock_widgets = []  # widgets that only make sense for a mocked member
        self.results = queue.Queue()
        self.loading = False  # true while copying a feed into the widgets
        self.edit_job = None  # pending debounced send after a slider edit

        # Connection to the server. "can_pin" is None until we know whether the
        # server has /debug/override; False means send plain telemetry instead.
        self.connected = None
        self.can_pin = None
        self.failures = 0
        self.refreshing = False
        self.conn_text = tk.StringVar(value="Connecting...")

        self.server = tk.StringVar(value=server)
        first_mocked = next((mid for mid, _ in MEMBERS if mid in mock), "son")
        self.member = tk.StringVar(value=first_mocked)
        self.status = tk.StringVar(value="")
        self.vars = {}
        self.pin_vars = {}

        self._build()
        self._load_member()
        self.after(100, self._drain_results)
        self.after(300, self._refresh_family)
        self.after(SEND_EVERY_MS, self._stream_tick)

    # ---- layout -----------------------------------------------------------

    def _build(self):
        pad = {"padx": 6, "pady": 3}

        top = ttk.Frame(self)
        top.grid(row=0, column=0, sticky="ew", **pad)
        line1 = ttk.Frame(top)
        line1.pack(fill="x")
        ttk.Label(line1, text="Server").pack(side="left")
        server_entry = ttk.Entry(line1, textvariable=self.server, width=32)
        server_entry.pack(side="left", padx=4)
        server_entry.bind("<Return>", lambda _e: self._server_changed(tidy_entry=True))
        server_entry.bind("<FocusOut>", lambda _e: self._server_changed(tidy_entry=True))
        line2 = ttk.Frame(top)
        line2.pack(fill="x", pady=(4, 0))
        ttk.Label(line2, text="Mock").pack(side="left")
        for mid, name in MEMBERS:
            ttk.Checkbutton(line2, text=name, variable=self.mocked[mid],
                            command=lambda m=mid: self._on_mock_toggle(m)).pack(side="left")
        ttk.Label(line2, text="(untick anyone wearing a real watch)", foreground="#777").pack(side="left", padx=(2, 12))
        ttk.Label(line2, text="Edit").pack(side="left")
        for mid, name in MEMBERS:
            ttk.Radiobutton(line2, text=name, value=mid, variable=self.member,
                            command=self._load_member).pack(side="left")

        self.vitals_frame = vitals = ttk.LabelFrame(self, text="Data feed (ticked = pinned on the server)")
        vitals.grid(row=1, column=0, sticky="ew", **pad)
        for row, (key, label, lo, hi, step, _) in enumerate(FIELDS):
            pin = tk.BooleanVar()
            self.pin_vars[key] = pin
            box = ttk.Checkbutton(vitals, variable=pin, command=self._on_pin_toggle)
            box.grid(row=row, column=0)
            ttk.Label(vitals, text=label, width=16).grid(row=row, column=1, sticky="w")
            var = tk.DoubleVar()
            self.vars[key] = var
            scale = tk.Scale(vitals, variable=var, from_=lo, to=hi, resolution=step, orient="horizontal",
                             length=260, showvalue=True,
                             command=lambda _v, k=key: self._on_slider(k))
            scale.grid(row=row, column=2)
            self.mock_widgets += [box, scale]

        pos = ttk.LabelFrame(self, text="Position")
        pos.grid(row=2, column=0, sticky="ew", **pad)
        self.pin_vars["pos"] = tk.BooleanVar()
        pos_box = ttk.Checkbutton(pos, variable=self.pin_vars["pos"], command=self._on_pin_toggle)
        pos_box.grid(row=0, column=0)
        self.mock_widgets.append(pos_box)
        for col, key in ((1, "lat"), (3, "lon")):
            ttk.Label(pos, text=key).grid(row=0, column=col, sticky="e")
            var = tk.StringVar()
            self.vars[key] = var
            entry = ttk.Entry(pos, textvariable=var, width=12)
            entry.grid(row=0, column=col + 1, padx=2)
            entry.bind("<FocusOut>", lambda _e: self._on_position_typed())
            entry.bind("<Return>", lambda _e: self._on_position_typed())
            self.mock_widgets.append(entry)
        nudge = ttk.Frame(pos)
        nudge.grid(row=1, column=0, columnspan=5, pady=2)
        ttk.Label(nudge, text="Move 100 m:").pack(side="left")
        for text, north, east in (("N", 100, 0), ("S", -100, 0), ("E", 0, 100), ("W", 0, -100)):
            b = ttk.Button(nudge, text=text, width=3, command=lambda n=north, e=east: self._nudge(n, e))
            b.pack(side="left")
            self.mock_widgets.append(b)

        presets = ttk.Frame(self)
        presets.grid(row=3, column=0, sticky="ew", **pad)
        ttk.Label(presets, text="Presets:").pack(side="left")
        for name in PRESETS:
            b = ttk.Button(presets, text=name, command=lambda n=name: self._preset(n))
            b.pack(side="left", padx=1)
            self.mock_widgets.append(b)

        send = ttk.Frame(self)
        send.grid(row=4, column=0, sticky="ew", **pad)
        self.stream_var = tk.BooleanVar()
        for w, kw in (
            (ttk.Checkbutton(send, text="Keep sending every 5 s", variable=self.stream_var, command=self._on_stream), {}),
            (ttk.Button(send, text="Send now", command=self._send_current), {"padx": 4}),
            (ttk.Button(send, text="Release all", command=self._release), {}),
        ):
            w.pack(side="left", **kw)
            self.mock_widgets.append(w)

        actions = ttk.LabelFrame(self, text="Events (as the selected member)")
        actions.grid(row=5, column=0, sticky="ew", **pad)
        ttk.Button(actions, text="SOS", command=lambda: self._sos("manual")).pack(side="left", padx=2)
        ttk.Button(actions, text="Fall", command=lambda: self._sos("fall")).pack(side="left", padx=2)
        ttk.Label(actions, text="Check on").pack(side="left", padx=(10, 2))
        self.target = tk.StringVar(value="mom")
        self.target_box = ttk.Combobox(actions, textvariable=self.target, width=8, state="readonly")
        self.target_box.pack(side="left")
        ttk.Button(actions, text="Ask", command=self._checkin).pack(side="left", padx=2)
        ttk.Button(actions, text="Reset server", command=self._reset).pack(side="right", padx=2)

        fam = ttk.LabelFrame(self, text="Server view (GET /family)")
        fam.grid(row=6, column=0, sticky="ew", **pad)
        cols = ("name", "status", "hr", "spo2", "temp", "battery", "heading", "lastSeen", "pinned")
        self.table = ttk.Treeview(fam, columns=cols, show="headings", height=4)
        for c, w in zip(cols, (70, 60, 45, 45, 50, 55, 60, 65, 150)):
            self.table.heading(c, text=c)
            self.table.column(c, width=w, anchor="center")
        self.table.pack(fill="x")

        self.conn_label = tk.Label(self, textvariable=self.conn_text, anchor="w")
        self.conn_label.grid(row=7, column=0, sticky="w", **pad)
        ttk.Label(self, textvariable=self.status, foreground="#555").grid(row=8, column=0, sticky="w", **pad)

    # ---- state <-> widgets ---------------------------------------------------

    def _feed(self):
        return self.feeds[self.member.get()]

    def _load_member(self):
        feed = self._feed()
        self.loading = True
        for key, *_ in FIELDS:
            self.vars[key].set(feed.values[key])
            self.pin_vars[key].set(feed.pinned[key])
        self.vars["lat"].set(f"{feed.values['lat']:.6f}")
        self.vars["lon"].set(f"{feed.values['lon']:.6f}")
        self.pin_vars["pos"].set(feed.pinned["pos"])
        self.stream_var.set(feed.stream)
        others = [m for m in ALL_MEMBERS if m != self.member.get()]
        self.target_box["values"] = others
        if self.target.get() not in others:
            self.target.set(others[0])
        mid = self.member.get()
        name = feed_name(mid)
        mocked = self.mocked[mid].get()
        for w in self.mock_widgets:
            set_enabled(w, mocked)
        self.vitals_frame.configure(text=f"{name}'s data feed (ticked = pinned on the server)" if mocked
                                    else f"{name}: not mocked, real watch data (tick Mock {name} to fake it)")
        self.loading = False

    def _on_mock_toggle(self, mid):
        """Start or stop faking a member's data."""
        feed = self.feeds[mid]
        if self.mocked[mid].get():
            # Back to the demo values, ticked and streaming.
            fresh = MemberFeed(mid, auto=True)
            feed.values, feed.pinned, feed.stream = fresh.values, fresh.pinned, True
            self.member.set(mid)
            self._load_member()
            self._send(mid)
            self.status.set(f"{feed_name(mid)}: mocked, sending every 5 s")
        else:
            for key in feed.pinned:
                feed.pinned[key] = False
            feed.stream = False
            self._load_member()
            self._clear_pins(mid, f"{feed_name(mid)}: not mocked, the real watch's data shows now")

    def _clear_pins(self, mid, label):
        if self.can_pin is False:
            self.status.set(label)
            return
        self._request("POST", f"/debug/override/{mid}", {"clear": True}, label)

    def _save_widgets(self):
        feed = self._feed()
        for key, *_ in FIELDS:
            feed.values[key] = round(self.vars[key].get(), 1)
            feed.pinned[key] = self.pin_vars[key].get()
        feed.pinned["pos"] = self.pin_vars["pos"].get()
        for key in ("lat", "lon"):
            try:
                feed.values[key] = float(self.vars[key].get())
            except ValueError:
                self.vars[key].set(f"{feed.values[key]:.6f}")

    def _on_slider(self, key):
        """A slider moved: tick its field and send it once the slider settles."""
        if self.loading:
            return
        feed = self._feed()
        value = round(self.vars[key].get(), 1)
        # Tk also calls this when a value is set from code (switching member),
        # so only a real change counts as an edit.
        if value == feed.values[key]:
            return
        self.pin_vars[key].set(True)
        self._save_widgets()
        self._send_soon()

    def _on_pin_toggle(self):
        """A tick box changed: pin or release that field on the server now."""
        if self.loading:
            return
        self._save_widgets()
        self._send_soon()

    def _on_position_typed(self):
        if self.loading:
            return
        feed = self._feed()
        before = (feed.values["lat"], feed.values["lon"])
        self._save_widgets()
        if (feed.values["lat"], feed.values["lon"]) != before:
            self.pin_vars["pos"].set(True)
            feed.pinned["pos"] = True
            self._send_soon()

    def _send_soon(self):
        if self.edit_job is not None:
            self.after_cancel(self.edit_job)
        mid = self.member.get()
        self.edit_job = self.after(EDIT_DEBOUNCE_MS, lambda: self._edit_send(mid))

    def _edit_send(self, mid):
        self.edit_job = None
        self._send(mid)

    def _nudge(self, north, east):
        self._save_widgets()
        feed = self._feed()
        feed.values["lat"] += north / M_PER_DEG_LAT
        feed.values["lon"] += east / (M_PER_DEG_LAT * math.cos(math.radians(feed.values["lat"])))
        feed.pinned["pos"] = True
        self._load_member()
        self._send(self.member.get())

    def _preset(self, name):
        self._save_widgets()
        feed = self._feed()
        for key, value in PRESETS[name].items():
            feed.values[key] = value
            feed.pinned[key] = True
        self._load_member()
        self._send(self.member.get())

    def _on_stream(self):
        self._save_widgets()
        self._feed().stream = self.stream_var.get()
        if self._feed().stream:
            self._send(self.member.get())

    def _release(self):
        feed = self._feed()
        for key in feed.pinned:
            feed.pinned[key] = False
        feed.stream = False
        self._load_member()
        mid = self.member.get()
        if self.can_pin is False:
            self.status.set(f"released {mid} (this server can't pin, so nothing to clear)")
            return
        self._request("POST", f"/debug/override/{mid}", {"clear": True}, f"released {mid}")

    # ---- server calls (on a worker thread, results back via a queue) ----------

    def _request(self, method, path, body, label, fallback=None):
        """Runs a request on a worker thread. `fallback` (method, path, body) is
        tried instead when the server answers 404, i.e. an older server."""
        api = Api(self.server.get())

        def work():
            try:
                code, data = api.call(method, path, body)
                if code == 404 and fallback is not None:
                    self.results.put(("can_pin", False))
                    code, data = api.call(*fallback)
                    label_used = label + " (sent as telemetry: this server can't pin)"
                else:
                    label_used = label
                ok = 200 <= code < 300
                err = data.get("error") if isinstance(data, dict) else data
                self.results.put(("up", api.base))
                self.results.put(("status", label_used if ok else f"{label}: {code} {err}"))
            except (urllib.error.URLError, OSError, ValueError) as e:
                self.results.put(("down", f"{label}: can't reach {api.base} ({reason(e)})"))

        threading.Thread(target=work, daemon=True).start()

    def _send(self, mid, live=False):
        feed = self.feeds[mid]
        pinned = feed.pinned_values(live)
        label = f"{feed_name(mid)}: " + (", ".join(f"{k}={v}" for k, v in pinned.items()) or "nothing pinned")
        telemetry = ("POST", f"/members/{mid}/telemetry", pinned)
        if self.can_pin is False:
            if pinned:
                self._request(*telemetry, label + " (as telemetry)")
            else:
                self.status.set(f"{feed_name(mid)}: nothing ticked to send")
            return
        self._request("POST", f"/debug/override/{mid}", feed.body(live), label,
                      fallback=telemetry if pinned else None)

    def _resend_all(self, why):
        """Pushes every member's ticked values again (after a reconnect or restart)."""
        sent = [mid for mid, feed in self.feeds.items() if feed.has_pins() or feed.stream]
        for mid in sent:
            self._send(mid)
        if sent:
            self.status.set(f"{why}: re-sent {', '.join(feed_name(m) for m in sent)}")

    def _send_current(self):
        self._save_widgets()
        self._send(self.member.get())

    def _sos(self, kind):
        mid = self.member.get()
        self._request("POST", f"/members/{mid}/sos", {"type": kind}, f"{mid} sent {kind}")

    def _checkin(self):
        mid, target = self.member.get(), self.target.get()
        self._request("POST", f"/members/{target}/checkin", {"from": mid}, f"{mid} asked {target}: are you OK?")

    def _reset(self):
        # Clears events and statuses for a fresh demo run. The feeder keeps its
        # values: the next refresh sees the pins are gone and sends them again,
        # so Mom and Son stay fed. Use "Release all" to stop faking a member.
        self._request("POST", "/debug/reset", {}, "server reset (events and statuses cleared; still feeding)")

    def _stream_tick(self):
        for mid, feed in self.feeds.items():
            if feed.stream:
                self._send(mid, live=True)
        self.after(SEND_EVERY_MS, self._stream_tick)

    def _server_changed(self, tidy_entry=False):
        url = normalize_url(self.server.get())
        # Only rewrite the box when you leave it, never while you're typing.
        if tidy_entry and url != self.server.get():
            self.server.set(url)
        if url != getattr(self, "_last_server", None):
            self._last_server = url
            # A different server: find out again what it supports, then resync.
            self.connected = None
            self.can_pin = None
            self.failures = 0
            self.conn_text.set(f"Connecting to {url}...")

    def _refresh_family(self):
        """Polls the server, every REFRESH_MS while up and RETRY_MS while down.
        Only one poll is in flight at a time, so a dead address doesn't pile up threads."""
        if not self.refreshing:
            self._server_changed()
            self.refreshing = True
            api = Api(self.server.get())

            def work():
                try:
                    code, family = api.call("GET", "/family")
                    if code != 200 or not isinstance(family, list):
                        raise ValueError(f"GET /family answered {code}")
                    pcode, pins = api.call("GET", "/debug/override")
                    self.results.put(("family", (family, pins if pcode == 200 else None, pcode != 404)))
                except (urllib.error.URLError, OSError, ValueError) as e:
                    self.results.put(("down", f"can't reach {api.base} ({reason(e)})"))
                finally:
                    self.results.put(("refreshed", None))

            threading.Thread(target=work, daemon=True).start()
        self.after(REFRESH_MS if self.connected else RETRY_MS, self._refresh_family)

    def _drain_results(self):
        while not self.results.empty():
            kind, payload = self.results.get()
            if kind == "status":
                self.status.set(payload)
            elif kind == "family":
                self._on_family(payload)
            elif kind == "up":
                self._mark_up()
            elif kind == "down":
                self._mark_down(payload)
            elif kind == "can_pin":
                self.can_pin = payload
            elif kind == "refreshed":
                self.refreshing = False
        self.after(100, self._drain_results)

    # ---- connection state ------------------------------------------------------

    def _mark_up(self):
        was = self.connected
        self.connected = True
        self.failures = 0
        mode = "pinning" if self.can_pin else ("telemetry only (older server)" if self.can_pin is False else "")
        self.conn_text.set(f"Connected to {normalize_url(self.server.get())}" + (f"  [{mode}]" if mode else ""))
        self.conn_label.configure(fg="#1a7f37")
        if was is False:
            self._resend_all("Reconnected")

    def _mark_down(self, msg):
        self.connected = False
        self.failures += 1
        self.conn_text.set(f"Not connected: {msg}. Retrying every {RETRY_MS // 1000} s (attempt {self.failures})")
        self.conn_label.configure(fg="#c62828")
        self.table.delete(*self.table.get_children())
        self.table.insert("", "end", values=("(no server)",) + ("",) * 8)

    def _on_family(self, payload):
        family, pins, has_override = payload
        first = self.connected is None or self.can_pin is None
        self.can_pin = has_override
        self._mark_up()
        pins = pins if isinstance(pins, dict) else {}
        self._show_family(family, pins)
        if first:
            # New server (or first contact): give it the values we already hold,
            # and drop any old pins on members we're not mocking (a real watch
            # wearer shouldn't be stuck with values from an earlier feeder run).
            self._resend_all("Connected")
            for mid, var in self.mocked.items():
                if not var.get() and pins.get(mid):
                    self._clear_pins(mid, f"{feed_name(mid)}: cleared old pins, showing the real watch")
            return
        # Resync members that lost their values: the server restarted, someone
        # reset it, or the member went stale while we hold values for it.
        for m in family:
            mid = m["id"]
            feed = self.feeds.get(mid)
            if feed is None or not feed.has_pins():
                continue
            lost_pins = self.can_pin and set(feed.pinned_values()) - set(pins.get(mid, {}))
            if lost_pins or m["status"] == "stale":
                self._send(mid)
                self.status.set(f"{feed_name(mid)} had lost its values on the server; sent them again")

    def _show_family(self, family, pins):
        self.table.delete(*self.table.get_children())
        for m in family:
            fmt = lambda v: "-" if v is None else v
            self.table.insert("", "end", values=(
                m["name"], m["status"], fmt(m["hr"]), fmt(m["spo2"]), fmt(m["temp"]),
                fmt(m["battery"]), fmt(m["heading"]), fmt(m["lastSeen"]),
                ", ".join(pins.get(m["id"], {}).keys()) or "-",
            ))


def set_enabled(widget, on):
    if isinstance(widget, tk.Scale):
        widget.configure(state="normal" if on else "disabled")
    else:
        widget.state(["!disabled"] if on else ["disabled"])


def feed_name(mid):
    return dict(MEMBERS).get(mid, mid)


def reason(e):
    r = getattr(e, "reason", None)
    return str(r if r is not None else e)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fake Mom's and Son's vitals and position.")
    parser.add_argument("server", nargs="?", default="http://localhost:3000",
                        help="server URL (default http://localhost:3000; http:// is optional)")
    parser.add_argument("--mock", default=",".join(ALL_MEMBERS),
                        help="whose data to fake, comma-separated: mom,son (default), son, mom or none")
    parser.add_argument("--manual", action="store_true",
                        help="start with nothing ticked or sent, instead of feeding the mocked members")
    args = parser.parse_args()
    mock = [] if args.mock.strip().lower() == "none" else [m.strip().lower() for m in args.mock.split(",") if m.strip()]
    unknown = [m for m in mock if m not in ALL_MEMBERS]
    if unknown:
        parser.error(f"unknown member(s) for --mock: {', '.join(unknown)} (choose from {', '.join(ALL_MEMBERS)})")
    Feeder(args.server, auto=not args.manual, mock=mock).mainloop()
