# KHAIRAGARH BATTLE (PIN 491881) — Hinglish README

3D third-person online shooting game (Godot 4, Android). Ek map: Khairagarh (Gol Bazar, Bus Stand, Indrakala, Arts College, Water Tank, Temple).
Real online multiplayer: 5–10 players, Room Code se, dedicated server par.

> ⚠️ **Sach baat (zaroor padhein):** Is ZIP ko banate waqt mere paas Godot engine, Android SDK aur internet nahi tha.
> Isliye **game code Godot me compile/test nahi hua** aur **APK maine nahi banaya**. Sirf Admin Panel (Python) ka test hua hai (`TESTING_REPORT.md`).
> Pehli baar GitHub Actions chalane par koi chhoti error aa sakti hai. Agar aaye to Actions ka red-error log copy karke mujhe bhejein, main fix kar dunga.

## ZIP me kya hai
| Folder | Kaam |
|---|---|
| `game/` | Godot 4 Android game project (client) |
| `server/` | Dockerfile, `server_config.json`, deploy files |
| `admin/` | Chhota web Admin Panel (Python) |
| `.github/workflows/build-apk.yml` | GitHub Actions: APK automatic banata hai |
| `TESTING_REPORT.md` | Kya test hua / kya nahi |

## Zaroori samajh
- **GitHub Actions sirf APK banata hai. Multiplayer server host nahi karta.**
- Multiplayer ke liye ek **server** chahiye jo 24x7 chale (UDP port **7777**). Free hosting ki guarantee nahi hai (neeche options).
- Bina server ke game menu khulega, par Room nahi ban sakta.

---
## STEP 1 — APK banana (GitHub Actions)
1. github.com par free account banayein → **New repository** (naam: `khairagarh-battle`). Public ya Private dono chalega.
2. Is ZIP ko khol (extract) lein. **Saari files/folders** (game, server, admin, `.github`, README…) repository me upload karein (Add file → Upload files). Dhyan: `.github` folder bhi upload hona chahiye (hidden folder hota hai; PC par "show hidden files" on karein. Ya `git` se push karein).
3. Repository me **Actions** tab → **Build Android APK** → **Run workflow**.
4. 5–10 minute baad green ✅ aayega. Us run par click karo → neeche **Artifacts → KhairagarhBattle-APK** download karo (zip hoga, andar `KhairagarhBattle.apk`).
5. Agar red ❌ aaye: us step ka error text copy karke mujhe bhej do.

### Server address kahan likhna hai
- Option A (aasan): game kholo → main menu me **Server address** box me IP/domain likho (jaise `203.0.113.10`). Yeh phone me save ho jata hai.
- Option B: `game/scripts/cfg.gd` me `SERVER_HOST := "YOUR_SERVER_IP_OR_DOMAIN"` badal do, phir APK dobara banao.
- Port badalna ho to `203.0.113.10:7777` format.

## STEP 2 — Server chalana
Server ko ek computer chahiye jo internet par hamesha on rahe, aur **UDP 7777** + **TCP 8080** open ho.
Options (koi bhi guarantee nahi, shartein badalti rehti hain):
- **Oracle Cloud "Always Free" VM** (credit card verification maangta hai; free tier region/availability par depend).
- Koi sasta VPS (kuch $/mahina).
- Apna PC/laptop: router me port-forward UDP 7777 (sirf test ke liye; PC on rahna chahiye).

VM par (Ubuntu) yeh commands:
```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 git
git clone https://github.com/<TUMHARA-USERNAME>/khairagarh-battle.git
cd khairagarh-battle
sudo docker compose -f server/docker-compose.yml up -d --build
```
Cloud firewall / Security List me **UDP 7777** aur **TCP 8080** allow karein (Ubuntu firewall ho to `sudo ufw allow 7777/udp && sudo ufw allow 8080/tcp`).

### Server online hai ya nahi?
1. Game menu me **Check Server** dabao → "Server is ONLINE." aana chahiye.
2. Ya Admin Panel khol ke dekho: **Server: ONLINE**.
3. Logs: `sudo docker logs khairagarh-battle` (line: `listening on UDP port 7777`).

Server settings: `server_config.json` (match 300 sec, kill target 20, respawn 4 sec). Badalne ke baad: `sudo docker compose -f server/docker-compose.yml restart`.
(Docker volume `kbdata` ke andar `/data/server_config.json` use hota hai; edit: `sudo docker exec -it khairagarh-battle sh -c "vi /data/server_config.json"` ya file replace karke restart.)

## STEP 3 — Admin Panel
- URL: `http://<SERVER-IP>:8080` (HTTPS ke liye `server/Caddyfile.example` dekho — internet par HTTPS strongly recommended, warna password plain-text me jata hai).
- **Pehla Super Admin banana (sirf ek baar):**
  - Tarika 1 (browser): `sudo docker logs khairagarh-battle` me **SETUP KEY** milegi. Browser me `http://<SERVER-IP>:8080/setup` kholo → key + username + password (min 10 characters) dalo.
  - Tarika 2 (command): `sudo docker exec -it khairagarh-battle python3 /app/admin/admin_server.py create-admin`
- Koi default password nahi hai. Password hash (PBKDF2-SHA256) hokar server ke `/data/admins.json` me rehta hai. APK me koi admin password/key nahi hai.
- Password bhool gaye: `sudo docker exec -it khairagarh-battle python3 /app/admin/admin_server.py reset-password`
- Panel me: server status, connected players, matchmaking on/off, maintenance mode, max players (5–10), weapon on/off, weapon damage, announcement.

## STEP 4 — Phone me install (Android)
1. `KhairagarhBattle.apk` phone me laao (WhatsApp se **Document** ke roop me bhejo, ya GitHub Release link se download).
2. APK par tap karo. Android bolega **"Install unknown apps"** — **Settings** dabao → apne browser/WhatsApp/Files app ke liye **Allow from this source** on karo → wapas aao → **Install**.
3. Play Protect warning aa sakti hai (kyunki yeh debug-signed test APK hai). **Yeh warning gayab hone ki koi guarantee nahi.** "Install anyway / More details" se aage badho.
4. App icon **Khairagarh Battle** se kholo (WhatsApp ke bahar chalta hai, yeh asli Android app hai).

### WhatsApp par share karna
- APK file ko WhatsApp me **Attach → Document** se bhejo (Gallery se nahi). Kabhi WhatsApp `.apk` block kare to **GitHub Release link** bhejo.
### GitHub Release link banana
- Tarika aasan: apne PC par `git tag v1.0 && git push origin v1.0` (ya GitHub → Releases → Draft a new release → tag `v1.0` → Publish). Workflow khud APK ko **Release** me laga dega. Release page ka link WhatsApp par bhejo.
- Note: Private repository ka Release link dusre log download nahi kar sakte — repository **Public** rakho.

## STEP 5 — Khelna
1. Ek dost **CREATE ROOM** dabaye → 5 akshar ka **Room Code** dikhega.
2. Baaki dost code likh kar **JOIN ROOM**. (Max 5–10, admin setting ke hisaab se.)
3. Host **START MATCH** (kam se kam 2 players). Pehle 20 kills ya 5 minute — jo pehle. Winner screen aati hai, phir room lobby me wapas.
4. Controls: left joystick = chalna, screen ka right side drag = camera, FIRE, JUMP, RELOAD, SWAP (Rifle/Shotgun), SCORE.

## Game ka design (short)
- Server **authoritative** hai: health, damage, ammo, reload, kills, respawn, winner — sab server decide karta hai. Goli ka hit server check karta hai (walls/buildings ke peeche hit nahi).
- Player ka chalna client par predict hota hai, server speed/boundary/building-ke-andar jaisi cheating ko reject karke wapas correct kar deta hai. (Full physics server-side nahi, taaki chhota aur halka rahe.)
- Koi bot/fake player nahi. Sirf real players.
- Graphics: low-poly procedural 3D (koi external asset nahi), 1 draw-call map, optional shadows (menu me checkbox). **Awaaz/sound abhi nahi hai.** Map ek concept layout hai, exact survey nahi.
- Android permission: sirf **INTERNET**.
- Transport: Godot ENet (UDP).

## Known limitations (imaandari se)
- Godot me compile/run test nahi hua (upar dekho). Pehli run me small fixes lag sakte hain.
- Debug-signed APK (sirf testing). Play Store ke liye alag release keystore chahiye.
- Admin Panel HTTP par chalta hai jab tak aap HTTPS (Caddy) na lagao.
- Sound, grenade, skins nahi (scope chhota rakha).
