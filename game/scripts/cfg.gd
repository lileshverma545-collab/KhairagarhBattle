extends RefCounted
## Shared constants (used by both the game client and the dedicated server)

# >>> SERVER ADDRESS <<<
# Put your server IP or domain here (example: "203.0.113.10" or "game.example.com").
# Players can ALSO type the address inside the game (Server box on main menu).
const SERVER_HOST := "YOUR_SERVER_IP_OR_DOMAIN"
const SERVER_PORT := 7777

const VERSION := "1.0"
const RUN_SPEED := 6.0

const W_NAMES := ["Assault Rifle", "Shotgun"]
const W_KEYS := ["rifle", "shotgun"]
const W_MAG := [30, 6]
const W_RESERVE_START := [120, 24]
const W_RESERVE_MAX := [150, 40]
const W_RESERVE_KILL := [15, 4]
const W_INTERVAL := [0.11, 0.85]
const W_RELOAD := [1.8, 2.4]
const W_PELLETS := [1, 8]
const W_SPREAD := [0.012, 0.07]
const W_RANGE := [150.0, 35.0]
const W_DAMAGE := [18, 9]   # default damage per bullet / per pellet (admin panel can change)
