#!/usr/bin/env python3
"""Family Wellness data feeder: set fake vitals and position for Mom or Son.

    python3 tools/feeder.py                          # local server
    python3 tools/feeder.py http://<laptop-ip>:3000  # another laptop's server

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

import json
import math
import queue
import sys
import threading
import tkinter as tk
import urllib.error
import urllib.request
from tkinter import ttk

MEMBERS = [("mom", "Mom"), ("son", "Son")]
ALL_MEMBERS = ["mom", "son", "grandpa"]
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

    def __init__(self, member_id):
        self.values = {k: d for k, _, _, _, _, d in FIELDS}
        self.values["lat"], self.values["lon"] = START_POS[member_id]
        self.pinned = {k: False for k, *_ in FIELDS}
        self.pinned["pos"] = False
        self.stream = False

    def has_pins(self):
        return any(self.pinned.values())

    def pinned_values(self):
        return {k: v for k, v in self.body().items() if v is not None}

    def body(self):
        out = {}
        for k, *_ in FIELDS:
            out[k] = self.values[k] if self.pinned[k] else None
        for k in ("lat", "lon"):
            out[k] = self.values[k] if self.pinned["pos"] else None
        return out


class Feeder(tk.Tk):
    def __init__(self, server):
        super().__init__()
        self.title("Family Wellness feeder")
        self.resizable(False, False)
        self.feeds = {mid: MemberFeed(mid) for mid, _ in MEMBERS}
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
        self.member = tk.StringVar(value="son")
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
        ttk.Label(top, text="Server").pack(side="left")
        server_entry = ttk.Entry(top, textvariable=self.server, width=32)
        server_entry.pack(side="left", padx=4)
        server_entry.bind("<Return>", lambda _e: self._server_changed(tidy_entry=True))
        server_entry.bind("<FocusOut>", lambda _e: self._server_changed(tidy_entry=True))
        ttk.Label(top, text="Member").pack(side="left", padx=(12, 2))
        for mid, name in MEMBERS:
            ttk.Radiobutton(top, text=name, value=mid, variable=self.member,
                            command=self._load_member).pack(side="left")

        vitals = ttk.LabelFrame(self, text="Data feed (ticked = pinned on the server)")
        vitals.grid(row=1, column=0, sticky="ew", **pad)
        for row, (key, label, lo, hi, step, _) in enumerate(FIELDS):
            pin = tk.BooleanVar()
            self.pin_vars[key] = pin
            ttk.Checkbutton(vitals, variable=pin, command=self._on_pin_toggle).grid(row=row, column=0)
            ttk.Label(vitals, text=label, width=16).grid(row=row, column=1, sticky="w")
            var = tk.DoubleVar()
            self.vars[key] = var
            tk.Scale(vitals, variable=var, from_=lo, to=hi, resolution=step, orient="horizontal",
                     length=260, showvalue=True,
                     command=lambda _v, k=key: self._on_slider(k)).grid(row=row, column=2)

        pos = ttk.LabelFrame(self, text="Position")
        pos.grid(row=2, column=0, sticky="ew", **pad)
        self.pin_vars["pos"] = tk.BooleanVar()
        ttk.Checkbutton(pos, variable=self.pin_vars["pos"], command=self._on_pin_toggle).grid(row=0, column=0)
        for col, key in ((1, "lat"), (3, "lon")):
            ttk.Label(pos, text=key).grid(row=0, column=col, sticky="e")
            var = tk.StringVar()
            self.vars[key] = var
            entry = ttk.Entry(pos, textvariable=var, width=12)
            entry.grid(row=0, column=col + 1, padx=2)
            entry.bind("<FocusOut>", lambda _e: self._on_position_typed())
            entry.bind("<Return>", lambda _e: self._on_position_typed())
        nudge = ttk.Frame(pos)
        nudge.grid(row=1, column=0, columnspan=5, pady=2)
        ttk.Label(nudge, text="Move 100 m:").pack(side="left")
        for text, north, east in (("N", 100, 0), ("S", -100, 0), ("E", 0, 100), ("W", 0, -100)):
            ttk.Button(nudge, text=text, width=3,
                       command=lambda n=north, e=east: self._nudge(n, e)).pack(side="left")

        presets = ttk.Frame(self)
        presets.grid(row=3, column=0, sticky="ew", **pad)
        ttk.Label(presets, text="Presets:").pack(side="left")
        for name in PRESETS:
            ttk.Button(presets, text=name, command=lambda n=name: self._preset(n)).pack(side="left", padx=1)

        send = ttk.Frame(self)
        send.grid(row=4, column=0, sticky="ew", **pad)
        self.stream_var = tk.BooleanVar()
        ttk.Checkbutton(send, text="Keep sending every 5 s", variable=self.stream_var,
                        command=self._on_stream).pack(side="left")
        ttk.Button(send, text="Send now", command=self._send_current).pack(side="left", padx=4)
        ttk.Button(send, text="Release all", command=self._release).pack(side="left")

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
        self.loading = False

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

    def _send(self, mid):
        feed = self.feeds[mid]
        pinned = feed.pinned_values()
        label = f"{feed_name(mid)}: " + (", ".join(f"{k}={v}" for k, v in pinned.items()) or "nothing pinned")
        telemetry = ("POST", f"/members/{mid}/telemetry", pinned)
        if self.can_pin is False:
            if pinned:
                self._request(*telemetry, label + " (as telemetry)")
            else:
                self.status.set(f"{feed_name(mid)}: nothing ticked to send")
            return
        self._request("POST", f"/debug/override/{mid}", feed.body(), label,
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
        for feed in self.feeds.values():
            feed.stream = False
            for key in feed.pinned:
                feed.pinned[key] = False
        self._load_member()
        self._request("POST", "/debug/reset", {}, "server reset (events, statuses and pins cleared)")

    def _stream_tick(self):
        for mid, feed in self.feeds.items():
            if feed.stream:
                self._send(mid)
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
            # New server (or first contact): give it the values we already hold.
            self._resend_all("Connected")
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


def feed_name(mid):
    return dict(MEMBERS).get(mid, mid)


def reason(e):
    r = getattr(e, "reason", None)
    return str(r if r is not None else e)


if __name__ == "__main__":
    Feeder(sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3000").mainloop()
