#!/usr/bin/env python3
"""Khairagarh Battle - small secure Admin Panel (Python standard library only).

Commands:
  python3 admin_server.py serve            start web panel (default port 8080)
  python3 admin_server.py create-admin     create the first Super Admin (asks username + password)
  python3 admin_server.py reset-password   change the password of an existing admin

Data folder (env KB_DATA_DIR, default /data):
  admins.json     admin accounts (PBKDF2-SHA256 hashed passwords - never plain text)
  settings.json   settings that the game server reads every 3 seconds
  status.json     written by the game server (online players, rooms)
"""
import getpass, hashlib, hmac, html, json, os, secrets, sys, time
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

DATA = os.environ.get("KB_DATA_DIR", "/data")
PORT = int(os.environ.get("KB_ADMIN_PORT", "8080"))
STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
ITER = 600_000
SESSION_TTL = 3600 * 8
COOKIE_SECURE = os.environ.get("KB_COOKIE_SECURE", "0") == "1"

ADMINS_F = os.path.join(DATA, "admins.json")
SETTINGS_F = os.path.join(DATA, "settings.json")
STATUS_F = os.path.join(DATA, "status.json")
SETUPKEY_F = os.path.join(DATA, "setup_key.txt")

DEFAULT_SETTINGS = {
    "matchmaking_enabled": True, "maintenance": False, "max_players": 10,
    "weapons_enabled": {"rifle": True, "shotgun": True},
    "damage": {"rifle": 18, "shotgun": 9}, "announcement": "",
}

sessions = {}      # token -> {"user":..., "csrf":..., "exp":...}
fails = {}         # ip -> [timestamps]
lock_threads = __import__("threading").Lock()


# ------------------------------------------------------------------ storage
def read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def write_json(path, obj, private=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600 if private else 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    os.replace(tmp, path)


def hash_password(password, salt=None, iters=ITER):
    salt = salt or secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iters)
    return {"salt": salt.hex(), "hash": dk.hex(), "iters": iters}


def verify_password(password, rec):
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(rec["salt"]), int(rec["iters"]))
    return hmac.compare_digest(dk.hex(), rec["hash"])


def load_admins():
    return read_json(ADMINS_F, {"admins": {}})


def valid_username(u):
    return 3 <= len(u) <= 32 and all(c.isalnum() or c in "_-." for c in u)


def create_admin(username, password):
    if not valid_username(username):
        raise ValueError("Username must be 3-32 characters: letters, digits, _ - .")
    if len(password) < 10:
        raise ValueError("Password must be at least 10 characters.")
    data = load_admins()
    if data["admins"]:
        raise ValueError("A Super Admin already exists. Use 'reset-password' if you forgot it.")
    data["admins"][username] = {"role": "super_admin", "pw": hash_password(password), "created": int(time.time())}
    write_json(ADMINS_F, data, private=True)
    try:
        os.remove(SETUPKEY_F)
    except OSError:
        pass


def load_settings():
    s = read_json(SETTINGS_F, {})
    out = json.loads(json.dumps(DEFAULT_SETTINGS))
    if isinstance(s, dict):
        out["matchmaking_enabled"] = bool(s.get("matchmaking_enabled", True))
        out["maintenance"] = bool(s.get("maintenance", False))
        out["max_players"] = min(10, max(5, int(s.get("max_players", 10))))
        we = s.get("weapons_enabled", {}) if isinstance(s.get("weapons_enabled"), dict) else {}
        out["weapons_enabled"] = {"rifle": bool(we.get("rifle", True)), "shotgun": bool(we.get("shotgun", True))}
        dm = s.get("damage", {}) if isinstance(s.get("damage"), dict) else {}
        out["damage"] = {"rifle": min(100, max(1, int(dm.get("rifle", 18)))), "shotgun": min(100, max(1, int(dm.get("shotgun", 9))))}
        out["announcement"] = str(s.get("announcement", ""))[:140]
    return out


def ensure_setup_key():
    """When no admin exists, create a one-time setup key and print it in the server log."""
    if load_admins()["admins"]:
        return None
    os.makedirs(DATA, exist_ok=True)
    if os.path.exists(SETUPKEY_F):
        key = open(SETUPKEY_F).read().strip()
    else:
        key = secrets.token_urlsafe(12)
        fd = os.open(SETUPKEY_F, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(key)
    print("=" * 60)
    print("[ADMIN] No admin exists yet. Open  http://<server>:%d/setup" % PORT)
    print("[ADMIN] One-time SETUP KEY: %s" % key)
    print("[ADMIN] (or run:  python3 admin_server.py create-admin)")
    print("=" * 60, flush=True)
    return key


# ------------------------------------------------------------------ HTML
def page(title, body, extra_head=""):
    return ("<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>%s</title><link rel='stylesheet' href='/static/style.css'>%s</head><body>%s</body></html>" % (html.escape(title), extra_head, body)).encode()


def esc(x):
    return html.escape(str(x), quote=True)


def login_page(msg=""):
    m = "<p class='err'>%s</p>" % esc(msg) if msg else ""
    return page("Admin Login", "<div class='card narrow'><h1>Khairagarh Battle</h1><h2>Admin Login</h2>%s"
                "<form method='post' action='/login' autocomplete='off'>"
                "<label>Username</label><input name='username' required autofocus>"
                "<label>Password</label><input name='password' type='password' required>"
                "<button>Login</button></form></div>" % m)


def setup_page(msg=""):
    m = "<p class='err'>%s</p>" % esc(msg) if msg else ""
    return page("First Admin Setup", "<div class='card narrow'><h1>First Super Admin</h1>"
                "<p>The setup key is printed in the server log (<code>docker logs khairagarh-battle</code>).</p>%s"
                "<form method='post' action='/setup' autocomplete='off'>"
                "<label>Setup key</label><input name='key' required>"
                "<label>Choose username</label><input name='username' required>"
                "<label>Choose password (min 10 characters)</label><input name='password' type='password' minlength='10' required>"
                "<button>Create Super Admin</button></form></div>" % m)


def fmt_uptime(sec):
    sec = int(sec)
    return "%dh %02dm %02ds" % (sec // 3600, sec % 3600 // 60, sec % 60)


def status_view():
    st = read_json(STATUS_F, None)
    online = bool(st) and (time.time() - float(st.get("time", 0))) < 8
    return st or {}, online


def dashboard(sess, msg=""):
    s = load_settings()
    st, online = status_view()
    players = st.get("players", []) if online else []
    prow = "".join("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
        esc(p.get("name")), esc(p.get("pid")), esc(p.get("room") or "-"), esc(p.get("kills")), esc(p.get("deaths"))) for p in players) or "<tr><td colspan=5>No players connected</td></tr>"
    rrow = "".join("<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (esc(r.get("code")), esc(r.get("state")), esc(r.get("players"))) for r in st.get("rooms", [])) if online else ""
    chk = lambda b: "checked" if b else ""
    sel = "".join("<option %s>%d</option>" % ("selected" if s["max_players"] == n else "", n) for n in range(5, 11))
    m = "<p class='ok'>%s</p>" % esc(msg) if msg else ""
    body = ("<div class='top'><h1>Khairagarh Battle - Admin</h1><form method='post' action='/logout'><input type='hidden' name='csrf' value='%s'>"
            "<span>%s</span> <button class='small'>Logout</button></form></div>%s"
            "<div class='grid'><div class='card'><h2>Server status</h2><div id='status'>"
            "<p>Server: <b class='%s'>%s</b></p><p>Uptime: %s</p><p>Connected players: <b>%d</b></p><p>Game port (UDP): %s</p></div>"
            "<h3>Rooms</h3><table><tr><th>Code</th><th>State</th><th>Players</th></tr>%s</table></div>"
            "<div class='card'><h2>Connected players</h2><table><tr><th>Name</th><th>Player ID</th><th>Room</th><th>Kills</th><th>Deaths</th></tr>%s</table></div></div>"
            "<div class='card'><h2>Game settings</h2><form method='post' action='/settings'><input type='hidden' name='csrf' value='%s'>"
            "<label class='row'><input type='checkbox' name='matchmaking_enabled' %s> Matchmaking enabled (create / join rooms)</label>"
            "<label class='row'><input type='checkbox' name='maintenance' %s> Maintenance mode (blocks new rooms and joins)</label>"
            "<label>Maximum players per room (5-10)</label><select name='max_players'>%s</select>"
            "<label class='row'><input type='checkbox' name='w_rifle' %s> Assault Rifle enabled</label>"
            "<label class='row'><input type='checkbox' name='w_shotgun' %s> Shotgun enabled</label>"
            "<label>Rifle damage per bullet (1-100)</label><input type='number' name='d_rifle' min='1' max='100' value='%d'>"
            "<label>Shotgun damage per pellet (1-100, 8 pellets)</label><input type='number' name='d_shotgun' min='1' max='100' value='%d'>"
            "<label>Announcement (shown to all players, max 140 characters)</label><input name='announcement' maxlength='140' value='%s'>"
            "<button>Save settings</button></form><p class='hint'>The game server picks up changes within about 3 seconds.</p></div>"
            "<script src='/static/app.js'></script>") % (
        sess["csrf"], esc(sess["user"]), m, "up" if online else "down", "ONLINE" if online else "OFFLINE", fmt_uptime(st.get("uptime", 0)) if online else "-", len(players),
        esc(st.get("port", "-")), rrow, prow, sess["csrf"], chk(s["matchmaking_enabled"]), chk(s["maintenance"]), sel,
        chk(s["weapons_enabled"]["rifle"]), chk(s["weapons_enabled"]["shotgun"]), s["damage"]["rifle"], s["damage"]["shotgun"], esc(s["announcement"]))
    return page("Admin", body)


# ------------------------------------------------------------------ HTTP
class Handler(BaseHTTPRequestHandler):
    server_version = "KBAdmin"
    sys_version = ""

    def log_message(self, fmt, *a):
        pass

    def _send(self, code, body, ctype="text/html; charset=utf-8", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; frame-ancestors 'none'; form-action 'self'")
        for k, v in (headers or []):
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _redirect(self, where, headers=None):
        self.send_response(303)
        self.send_header("Location", where)
        self.send_header("Content-Length", "0")
        for k, v in (headers or []):
            self.send_header(k, v)
        self.end_headers()

    def _ip(self):
        return self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()

    def _session(self):
        c = SimpleCookie(self.headers.get("Cookie", ""))
        if "kb_session" not in c:
            return None
        s = sessions.get(c["kb_session"].value)
        if not s or s["exp"] < time.time():
            return None
        return s

    def _form(self):
        n = min(int(self.headers.get("Content-Length", "0") or 0), 20000)
        raw = self.rfile.read(n).decode("utf-8", "replace")
        return {k: v[0] for k, v in parse_qs(raw, keep_blank_values=True).items()}

    def _cookie(self, token, max_age):
        flags = "HttpOnly; SameSite=Strict; Path=/; Max-Age=%d" % max_age
        if COOKIE_SECURE or self.headers.get("X-Forwarded-Proto") == "https":
            flags += "; Secure"
        return ("Set-Cookie", "kb_session=%s; %s" % (token, flags))

    def do_GET(self):
        path = self.path.split("?")[0]
        if path.startswith("/static/"):
            name = os.path.basename(path)
            fp = os.path.join(STATIC, name)
            if os.path.isfile(fp):
                ct = "text/css" if name.endswith(".css") else "application/javascript"
                return self._send(200, open(fp, "rb").read(), ct)
            return self._send(404, b"not found", "text/plain")
        if path == "/setup":
            if load_admins()["admins"]:
                return self._redirect("/")
            return self._send(200, setup_page())
        if path == "/api/status":
            if not self._session():
                return self._send(401, b"{}", "application/json")
            st, online = status_view()
            out = {"online": online, "uptime": st.get("uptime", 0) if online else 0, "players": st.get("players", []) if online else [], "rooms": st.get("rooms", []) if online else []}
            return self._send(200, json.dumps(out).encode(), "application/json")
        sess = self._session()
        if path in ("/", "/index.html"):
            if not load_admins()["admins"]:
                return self._redirect("/setup")
            if not sess:
                return self._send(200, login_page())
            return self._send(200, dashboard(sess, self._flash()))
        return self._send(404, b"not found", "text/plain")

    def _flash(self):
        return "Settings saved." if "saved=1" in self.path else ""

    def do_POST(self):
        path = self.path.split("?")[0]
        form = self._form()
        if path == "/setup":
            if load_admins()["admins"]:
                return self._redirect("/")
            key = open(SETUPKEY_F).read().strip() if os.path.exists(SETUPKEY_F) else None
            if not key or not hmac.compare_digest(form.get("key", ""), key):
                time.sleep(1.5)
                return self._send(403, setup_page("Wrong setup key."))
            try:
                create_admin(form.get("username", "").strip(), form.get("password", ""))
            except ValueError as e:
                return self._send(400, setup_page(str(e)))
            return self._redirect("/")
        if path == "/login":
            ip = self._ip()
            now = time.time()
            with lock_threads:
                fails[ip] = [t for t in fails.get(ip, []) if now - t < 300]
                if len(fails[ip]) >= 5:
                    return self._send(429, login_page("Too many wrong attempts. Wait 5 minutes."))
            u, p = form.get("username", ""), form.get("password", "")
            rec = load_admins()["admins"].get(u)
            ok = verify_password(p, rec["pw"]) if rec else (hash_password("x", b"0" * 16, 1000) and False)
            if not ok:
                with lock_threads:
                    fails.setdefault(ip, []).append(now)
                time.sleep(1.0)
                return self._send(401, login_page("Wrong username or password."))
            tok = secrets.token_urlsafe(32)
            sessions[tok] = {"user": u, "csrf": secrets.token_urlsafe(24), "exp": now + SESSION_TTL}
            return self._redirect("/", [self._cookie(tok, SESSION_TTL)])
        sess = self._session()
        if not sess or not hmac.compare_digest(form.get("csrf", ""), sess["csrf"]):
            return self._send(403, login_page("Session expired. Please login again."))
        if path == "/logout":
            c = SimpleCookie(self.headers.get("Cookie", ""))
            sessions.pop(c["kb_session"].value, None)
            return self._redirect("/", [self._cookie("", 0)])
        if path == "/settings":
            try:
                s = {
                    "matchmaking_enabled": "matchmaking_enabled" in form,
                    "maintenance": "maintenance" in form,
                    "max_players": min(10, max(5, int(form.get("max_players", "10")))),
                    "weapons_enabled": {"rifle": "w_rifle" in form, "shotgun": "w_shotgun" in form},
                    "damage": {"rifle": min(100, max(1, int(form.get("d_rifle", "18")))), "shotgun": min(100, max(1, int(form.get("d_shotgun", "9"))))},
                    "announcement": "".join(ch for ch in form.get("announcement", "") if ch.isprintable())[:140],
                }
            except ValueError:
                return self._send(400, dashboard(sess, "Invalid number."))
            write_json(SETTINGS_F, s)
            return self._redirect("/?saved=1")
        return self._send(404, b"not found", "text/plain")


def serve():
    os.makedirs(DATA, exist_ok=True)
    if not os.path.exists(SETTINGS_F):
        write_json(SETTINGS_F, DEFAULT_SETTINGS)
    ensure_setup_key()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print("[ADMIN] Admin panel running on port %d (data dir %s)" % (PORT, DATA), flush=True)
    srv.serve_forever()


def cli_create():
    if load_admins()["admins"]:
        print("A Super Admin already exists. Use: python3 admin_server.py reset-password")
        return
    u = input("New Super Admin username: ").strip()
    p = getpass.getpass("Password (min 10 characters): ")
    if p != getpass.getpass("Repeat password: "):
        print("Passwords do not match.")
        return
    try:
        create_admin(u, p)
        print("Super Admin '%s' created. Now open the admin panel and login." % u)
    except ValueError as e:
        print("Error:", e)


def cli_reset():
    data = load_admins()
    u = input("Admin username: ").strip()
    if u not in data["admins"]:
        print("No such admin.")
        return
    p = getpass.getpass("New password (min 10 characters): ")
    if len(p) < 10 or p != getpass.getpass("Repeat password: "):
        print("Password too short or not matching.")
        return
    data["admins"][u]["pw"] = hash_password(p)
    write_json(ADMINS_F, data, private=True)
    print("Password changed.")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "serve"
    {"serve": serve, "create-admin": cli_create, "reset-password": cli_reset}.get(cmd, serve)()
