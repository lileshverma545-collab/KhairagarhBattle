# Testing Report (honest)

## Actually tested (in my sandbox, Python 3.12)
Admin Panel (`admin/admin_server.py`) — automated script, **20/20 checks passed**:
first-run redirect to /setup; wrong/short setup key & password rejected; first Super Admin created; setup key deleted afterwards;
password stored only as PBKDF2-SHA256 hash (600k iterations), file mode 600; setup closed after first admin; wrong password rejected;
API needs login; login works; CSRF token enforced; settings saved to `settings.json`; values clamped (players 5–10, damage 1–100);
announcement / player names HTML-escaped; status shown ONLINE, stale status shows OFFLINE; lockout (HTTP 429) after repeated wrong logins.

## NOT tested (could not be tested here)
- **Godot project**: no Godot engine/Android SDK/internet in my environment → GDScript was never compiled or run. There may be syntax/runtime errors.
- **APK build** via GitHub Actions: workflow written from Godot 4.3 documentation but never executed. **No APK was produced.**
- **Dedicated server in Docker**: Dockerfile never built; server never started.
- **Real multiplayer** (5–10 players), latency, hit registration, performance on phones: untested.
- Map visuals/layout (collisions, spawn positions) and touch controls: untested.

## What to do first
1. Run the GitHub Action. If it fails, send me the error log.
2. Start the server, press **Check Server** in the app.
3. Test with 2 phones, then more.
