extends Node
## Net (autoload). Same script runs in BOTH places:
##  - on the dedicated server  (godot --headless -- --server)   -> authoritative game logic
##  - on the Android client                                     -> sends input, shows results
## Transport: Godot high-level multiplayer over ENet (UDP).

const Cfg = preload("res://scripts/cfg.gd")
const MapData = preload("res://scripts/map_data.gd")

# ---------------- client signals ----------------
signal net_connected
signal connect_failed
signal net_disconnected
signal error_msg(text: String)
signal server_info_changed
signal room_joined(info: Dictionary)
signal room_updated(info: Dictionary)
signal room_left
signal match_started(info: Dictionary, spawn: Vector3, yaw: float)
signal spawned(pos: Vector3, yaw: float)
signal snapshot_received(data: PackedFloat32Array)
signal hp_changed(hp: int, from_id: int)
signal ammo_changed(w: int, mag: int, reserve: int, reload_time: float)
signal shot_fx(shooter: int, origin: Vector3, ends: PackedVector3Array, w: int)
signal hit_confirm(victim: int, killed: bool)
signal kill_feed(text: String)
signal match_ended(result: Dictionary)
signal corrected(pos: Vector3)
signal ping_updated(ms: int)

var is_server_mode := false
var map = MapData.new()

# ---------------- client state ----------------
var my_name := "Player"
var my_pid := ""
var server_addr := ""
var shadows_on := true
var sens := 1.0
var room: Dictionary = {}
var room_end_local := 0.0
var server_info: Dictionary = {}
var announcement := ""
var ping_ms := 0
var connected_to_server := false
var pending_action: Callable = Callable()
var _peer: ENetMultiplayerPeer

# ---------------- server state ----------------
const SPH_Y := [0.45, 1.05, 1.6]
const SPH_R := [0.45, 0.45, 0.3]
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
var cfg: Dictionary = {}
var settings: Dictionary = {
	"matchmaking_enabled": true, "maintenance": false, "max_players": 10,
	"weapons_enabled": {"rifle": true, "shotgun": true},
	"damage": {"rifle": 18, "shotgun": 9}, "announcement": ""
}
var data_dir := "/data"
var rooms: Dictionary = {}
var players: Dictionary = {}
var _t_snap := 0.0
var _t_set := 0.0
var _t_stat := 0.0
var _started_at := 0.0
var _port := 7777

func _ready() -> void:
	map.generate()
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_fail)
	multiplayer.server_disconnected.connect(_on_server_gone)
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		_start_server(args)
	else:
		_load_local()

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

# =====================================================================
#                              LOCAL SETTINGS (client)
# =====================================================================
func _load_local() -> void:
	var c := ConfigFile.new()
	c.load("user://settings.cfg")
	my_pid = str(c.get_value("player", "pid", ""))
	if my_pid == "":
		my_pid = "KB%06d" % (randi() % 1000000)
	my_name = str(c.get_value("player", "name", "Player%d" % (randi() % 900 + 100)))
	var def_addr := Cfg.SERVER_HOST
	server_addr = str(c.get_value("player", "server", def_addr))
	shadows_on = bool(c.get_value("player", "shadows", true))
	sens = float(c.get_value("player", "sens", 1.0))
	save_local()

func save_local() -> void:
	var c := ConfigFile.new()
	c.set_value("player", "pid", my_pid)
	c.set_value("player", "name", my_name)
	c.set_value("player", "server", server_addr)
	c.set_value("player", "shadows", shadows_on)
	c.set_value("player", "sens", sens)
	c.save("user://settings.cfg")

func clean_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "[" and ch != "]":
			out += ch
	out = out.left(14)
	if out == "":
		out = "Player"
	return out

func my_id() -> int:
	return multiplayer.get_unique_id()

func name_of(id: int) -> String:
	for m in room.get("members", []):
		if int(m["id"]) == id:
			return str(m["name"])
	return "?"

# =====================================================================
#                              CLIENT: connection
# =====================================================================
func connect_server() -> void:
	var host := server_addr.strip_edges()
	var port := Cfg.SERVER_PORT
	if ":" in host:
		var parts := host.split(":")
		host = parts[0]
		port = int(parts[1])
	if host == "" or host == "YOUR_SERVER_IP_OR_DOMAIN":
		error_msg.emit("Server address is empty. Type your server IP in the Server box.")
		connect_failed.emit()
		return
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(host, port)
	if err != OK:
		error_msg.emit("Could not start connection (error %d)" % err)
		connect_failed.emit()
		return
	multiplayer.multiplayer_peer = _peer
	get_tree().create_timer(9.0).timeout.connect(_check_timeout)

func _check_timeout() -> void:
	if not connected_to_server and _peer != null and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_peer.close()
		multiplayer.multiplayer_peer = null
		pending_action = Callable()
		error_msg.emit("Cannot reach server. Check the address, internet, and that the server is running.")
		connect_failed.emit()

func _when_connected(cb: Callable) -> void:
	if connected_to_server:
		cb.call()
		return
	pending_action = cb
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		connect_server()

func check_server() -> void:
	_when_connected(func(): error_msg.emit("Server is ONLINE."))

func _on_connected_ok() -> void:
	connected_to_server = true
	net_connected.emit()
	if pending_action.is_valid():
		var cb := pending_action
		pending_action = Callable()
		cb.call()
	get_tree().create_timer(1.0).timeout.connect(_ping_loop)

func _on_connect_fail() -> void:
	connected_to_server = false
	pending_action = Callable()
	error_msg.emit("Connection failed.")
	connect_failed.emit()

func _on_server_gone() -> void:
	connected_to_server = false
	room = {}
	_peer = null
	multiplayer.multiplayer_peer = null
	net_disconnected.emit()

func _ping_loop() -> void:
	if connected_to_server:
		c_ping.rpc_id(1, Time.get_ticks_msec())
		get_tree().create_timer(2.0).timeout.connect(_ping_loop)

func create_room() -> void:
	_when_connected(func(): c_create_room.rpc_id(1, clean_name(my_name), my_pid))

func join_room(code: String) -> void:
	_when_connected(func(): c_join_room.rpc_id(1, code.strip_edges().to_upper(), clean_name(my_name), my_pid))

func leave_room() -> void:
	if connected_to_server:
		c_leave_room.rpc_id(1)
	room = {}
	room_left.emit()

func start_match() -> void:
	if connected_to_server:
		c_start_match.rpc_id(1)

func send_state(pos: Vector3, yaw: float, pitch: float) -> void:
	if connected_to_server:
		c_state.rpc_id(1, pos, yaw, pitch)

func send_shoot(dir: Vector3) -> void:
	if connected_to_server:
		c_shoot.rpc_id(1, dir)

func send_reload() -> void:
	if connected_to_server:
		c_reload.rpc_id(1)

func send_switch(w: int) -> void:
	if connected_to_server:
		c_switch.rpc_id(1, w)

# =====================================================================
#                      CLIENT: RPCs received from server
# =====================================================================
func _set_room(info: Dictionary) -> void:
	room = info
	room_end_local = _now() + float(info.get("end_in", 0.0))

@rpc("authority", "call_remote", "reliable")
func s_server_info(info: Dictionary) -> void:
	server_info = info
	announcement = str(info.get("announcement", ""))
	server_info_changed.emit()

@rpc("authority", "call_remote", "reliable")
func s_announce(text: String) -> void:
	announcement = text
	server_info_changed.emit()

@rpc("authority", "call_remote", "reliable")
func s_error(text: String) -> void:
	error_msg.emit(text)

@rpc("authority", "call_remote", "reliable")
func s_room_joined(info: Dictionary) -> void:
	_set_room(info)
	room_joined.emit(info)

@rpc("authority", "call_remote", "reliable")
func s_room_update(info: Dictionary) -> void:
	_set_room(info)
	room_updated.emit(info)

@rpc("authority", "call_remote", "reliable")
func s_match_start(info: Dictionary, spawn: Vector3, yaw: float) -> void:
	_set_room(info)
	match_started.emit(info, spawn, yaw)

@rpc("authority", "call_remote", "reliable")
func s_spawn(pos: Vector3, yaw: float) -> void:
	spawned.emit(pos, yaw)

@rpc("authority", "call_remote", "unreliable")
func s_snapshot(data: PackedFloat32Array) -> void:
	snapshot_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func s_hp(hp: int, from_id: int) -> void:
	hp_changed.emit(hp, from_id)

@rpc("authority", "call_remote", "reliable")
func s_ammo(w: int, mag: int, reserve: int, reload_time: float) -> void:
	ammo_changed.emit(w, mag, reserve, reload_time)

@rpc("authority", "call_remote", "unreliable")
func s_shot_fx(shooter: int, origin: Vector3, ends: PackedVector3Array, w: int) -> void:
	shot_fx.emit(shooter, origin, ends, w)

@rpc("authority", "call_remote", "reliable")
func s_hit_confirm(victim: int, killed: bool) -> void:
	hit_confirm.emit(victim, killed)

@rpc("authority", "call_remote", "reliable")
func s_kill_feed(text: String) -> void:
	kill_feed.emit(text)

@rpc("authority", "call_remote", "reliable")
func s_match_end(result: Dictionary) -> void:
	match_ended.emit(result)

@rpc("authority", "call_remote", "unreliable")
func s_correct(pos: Vector3) -> void:
	corrected.emit(pos)

@rpc("authority", "call_remote", "unreliable")
func s_pong(t: int) -> void:
	ping_ms = Time.get_ticks_msec() - t
	ping_updated.emit(ping_ms)

# =====================================================================
#                              SERVER
# =====================================================================
func _load_json(path: String, def: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return def
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return def
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		return def
	return data

func _dict(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}

func _start_server(args: PackedStringArray) -> void:
	is_server_mode = true
	Engine.max_fps = 60
	var dd := OS.get_environment("KB_DATA_DIR")
	data_dir = dd if dd != "" else "/data"
	DirAccess.make_dir_recursive_absolute(data_dir)
	var defaults := {"port": 7777, "max_clients": 120, "match_seconds": 300, "kill_target": 20, "respawn_seconds": 4, "snapshot_hz": 15, "min_players_to_start": 2}
	cfg = _dict(_load_json(data_dir + "/server_config.json", {}))
	for k in defaults:
		if not cfg.has(k):
			cfg[k] = defaults[k]
	_port = int(cfg["port"])
	for a in args:
		if a.begins_with("--port="):
			_port = int(a.get_slice("=", 1))
	_reload_settings()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(_port, int(cfg["max_clients"]))
	if err != OK:
		push_error("[KB-SERVER] cannot open UDP port %d (error %d)" % [_port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_started_at = _now()
	print("[KB-SERVER] Khairagarh Battle server v%s listening on UDP port %d, data dir %s" % [Cfg.VERSION, _port, data_dir])
	_write_status()

func _reload_settings() -> void:
	var s := _dict(_load_json(data_dir + "/settings.json", {}))
	if s.is_empty():
		return
	settings["matchmaking_enabled"] = bool(s.get("matchmaking_enabled", true))
	settings["maintenance"] = bool(s.get("maintenance", false))
	settings["max_players"] = clampi(int(s.get("max_players", 10)), 5, 10)
	var we := _dict(s.get("weapons_enabled", {}))
	settings["weapons_enabled"] = {"rifle": bool(we.get("rifle", true)), "shotgun": bool(we.get("shotgun", true))}
	var dm := _dict(s.get("damage", {}))
	settings["damage"] = {"rifle": clampi(int(dm.get("rifle", 18)), 1, 100), "shotgun": clampi(int(dm.get("shotgun", 9)), 1, 100)}
	var ann := str(s.get("announcement", "")).left(140)
	if ann != str(settings["announcement"]):
		settings["announcement"] = ann
		if multiplayer.multiplayer_peer != null and is_server_mode:
			for pid in multiplayer.get_peers():
				s_announce.rpc_id(pid, ann)

func _server_info() -> Dictionary:
	return {"maintenance": settings["maintenance"], "matchmaking": settings["matchmaking_enabled"], "announcement": settings["announcement"], "online": players.size(), "version": Cfg.VERSION}

func _write_status() -> void:
	var pl := []
	for id in players:
		var p = players[id]
		pl.append({"name": p["name"], "pid": p["pid"], "room": p["room"], "kills": p["kills"], "deaths": p["deaths"]})
	var rl := []
	for code in rooms:
		var r = rooms[code]
		rl.append({"code": code, "state": r["state"], "players": r["members"].size()})
	var st := {"online": true, "time": Time.get_unix_time_from_system(), "uptime": int(_now() - _started_at), "port": _port, "version": Cfg.VERSION, "players": pl, "rooms": rl}
	var tmp := data_dir + "/status.json.tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(st))
	f.close()
	DirAccess.rename_absolute(tmp, data_dir + "/status.json")

func _on_peer_connected(id: int) -> void:
	players[id] = {"id": id, "name": "Player", "pid": "", "room": "", "pos": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "hp": 100, "alive": false, "weapon": 0,
		"mag": Cfg.W_MAG.duplicate(), "reserve": Cfg.W_RESERVE_START.duplicate(), "next_fire": 0.0, "reload_end": 0.0, "kills": 0, "deaths": 0,
		"respawn_at": 0.0, "last_state": 0.0, "ignore_until": 0.0, "protect_until": 0.0, "fired_at": -10.0}
	s_server_info.rpc_id(id, _server_info())

func _on_peer_disconnected(id: int) -> void:
	_remove_from_room(id)
	players.erase(id)

func _process(delta: float) -> void:
	if not is_server_mode:
		return
	var now := _now()
	_t_set += delta
	if _t_set >= 3.0:
		_t_set = 0.0
		_reload_settings()
	_t_stat += delta
	if _t_stat >= 2.0:
		_t_stat = 0.0
		_write_status()
	for code in rooms.keys():
		_tick_room(rooms[code], now)
	_t_snap += delta
	if _t_snap >= 1.0 / float(cfg["snapshot_hz"]):
		_t_snap = 0.0
		_send_snapshots(now)

func _tick_room(room_d: Dictionary, now: float) -> void:
	if room_d["state"] == "playing":
		if now >= float(room_d["end_time"]):
			_end_match(room_d, "Time is up")
			return
		for m in room_d["members"]:
			var p = players[m]
			if not p["alive"] and now >= float(p["respawn_at"]):
				_spawn_player(room_d, p, false)
			if float(p["reload_end"]) > 0.0 and now >= float(p["reload_end"]):
				var w: int = p["weapon"]
				var need: int = int(Cfg.W_MAG[w]) - int(p["mag"][w])
				var take: int = mini(need, int(p["reserve"][w]))
				p["mag"][w] += take
				p["reserve"][w] -= take
				p["reload_end"] = 0.0
				_send_ammo(p, 0.0)
	elif room_d["state"] == "ended":
		if now >= float(room_d["lobby_at"]):
			room_d["state"] = "lobby"
			for m in room_d["members"]:
				players[m]["alive"] = false
			_room_broadcast_info(room_d)

func _send_snapshots(now: float) -> void:
	for code in rooms:
		var r = rooms[code]
		if r["state"] == "lobby":
			continue
		var arr := PackedFloat32Array()
		for m in r["members"]:
			var p = players[m]
			var fl := 0
			if p["alive"]:
				fl |= 1
			if now - float(p["fired_at"]) < 0.25:
				fl |= 2
			var pos: Vector3 = p["pos"]
			arr.append_array(PackedFloat32Array([float(m), pos.x, pos.y, pos.z, float(p["yaw"]), float(p["pitch"]), float(fl), float(p["hp"]), float(p["weapon"])]))
		for m in r["members"]:
			s_snapshot.rpc_id(m, arr)

func _room_info(r: Dictionary) -> Dictionary:
	var ms := []
	for id in r["members"]:
		var p = players[id]
		ms.append({"id": id, "name": p["name"], "kills": p["kills"], "deaths": p["deaths"]})
	return {"code": r["code"], "host": r["host"], "state": r["state"], "members": ms, "max": settings["max_players"], "target": r["target"], "end_in": maxf(0.0, float(r["end_time"]) - _now()), "min": int(cfg["min_players_to_start"])}

func _room_broadcast_info(r: Dictionary) -> void:
	var info := _room_info(r)
	for m in r["members"]:
		s_room_update.rpc_id(m, info)

func _new_code() -> String:
	while true:
		var c := ""
		for i in range(5):
			c += ALPHABET[randi() % ALPHABET.length()]
		if not rooms.has(c):
			return c
	return ""

func _can_matchmake(id: int) -> bool:
	if settings["maintenance"]:
		s_error.rpc_id(id, "Server is under maintenance. Try again later.")
		return false
	if not settings["matchmaking_enabled"]:
		s_error.rpc_id(id, "Matchmaking is currently disabled by the admin.")
		return false
	return true

func _set_identity(id: int, pname: String, pid: String) -> void:
	var p = players[id]
	p["name"] = clean_name(pname)
	p["pid"] = pid.left(20)
	p["kills"] = 0
	p["deaths"] = 0
	p["alive"] = false

@rpc("any_peer", "call_remote", "reliable")
func c_create_room(pname: String, pid: String) -> void:
	if not is_server_mode:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or players[id]["room"] != "" or not _can_matchmake(id):
		return
	_set_identity(id, pname, pid)
	var code := _new_code()
	var r := {"code": code, "host": id, "state": "lobby", "members": [id], "target": int(cfg["kill_target"]), "end_time": 0.0, "lobby_at": 0.0}
	rooms[code] = r
	players[id]["room"] = code
	s_room_joined.rpc_id(id, _room_info(r))

@rpc("any_peer", "call_remote", "reliable")
func c_join_room(code: String, pname: String, pid: String) -> void:
	if not is_server_mode:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or players[id]["room"] != "" or not _can_matchmake(id):
		return
	code = code.strip_edges().to_upper()
	if not rooms.has(code):
		s_error.rpc_id(id, "Room code not found: %s" % code)
		return
	var r = rooms[code]
	if r["members"].size() >= int(settings["max_players"]):
		s_error.rpc_id(id, "Room is full.")
		return
	_set_identity(id, pname, pid)
	r["members"].append(id)
	players[id]["room"] = code
	s_room_joined.rpc_id(id, _room_info(r))
	if r["state"] == "playing":
		_reset_player(players[id])
		_spawn_player(r, players[id], true)
	_room_broadcast_info(r)

@rpc("any_peer", "call_remote", "reliable")
func c_leave_room() -> void:
	if not is_server_mode:
		return
	_remove_from_room(multiplayer.get_remote_sender_id())

func _remove_from_room(id: int) -> void:
	if not players.has(id):
		return
	var code: String = players[id]["room"]
	players[id]["room"] = ""
	players[id]["alive"] = false
	if not rooms.has(code):
		return
	var r = rooms[code]
	r["members"].erase(id)
	if r["members"].is_empty():
		rooms.erase(code)
		return
	if r["host"] == id:
		r["host"] = r["members"][0]
	if r["state"] == "playing" and r["members"].size() < 2:
		_end_match(r, "Other players left")
	_room_broadcast_info(r)

@rpc("any_peer", "call_remote", "reliable")
func c_start_match() -> void:
	if not is_server_mode:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var code: String = players[id]["room"]
	if not rooms.has(code):
		return
	var r = rooms[code]
	if r["host"] != id or r["state"] != "lobby":
		return
	if settings["maintenance"]:
		s_error.rpc_id(id, "Server is under maintenance.")
		return
	if r["members"].size() < int(cfg["min_players_to_start"]):
		s_error.rpc_id(id, "Need at least %d players to start." % int(cfg["min_players_to_start"]))
		return
	r["state"] = "playing"
	r["end_time"] = _now() + float(cfg["match_seconds"])
	for m in r["members"]:
		_reset_player(players[m])
		players[m]["kills"] = 0
		players[m]["deaths"] = 0
	for m in r["members"]:
		var sp := _pick_spawn(r, m)
		_place(players[m], sp)
		var info := _room_info(r)
		s_match_start.rpc_id(m, info, sp, players[m]["yaw"])
		_send_ammo(players[m], 0.0)
		s_hp.rpc_id(m, 100, 0)

func _reset_player(p: Dictionary) -> void:
	p["hp"] = 100
	p["weapon"] = 0
	p["mag"] = Cfg.W_MAG.duplicate()
	p["reserve"] = Cfg.W_RESERVE_START.duplicate()
	p["reload_end"] = 0.0
	p["next_fire"] = 0.0

func _pick_spawn(r: Dictionary, me: int) -> Vector3:
	var best: Vector3 = map.spawns[0]
	var best_d := -1.0
	for i in range(6):
		var sp: Vector3 = map.spawns[randi() % map.spawns.size()]
		var md := 1000000.0
		for oid in r["members"]:
			if oid == me:
				continue
			var o = players[oid]
			if o["alive"]:
				md = minf(md, sp.distance_to(o["pos"]))
		if md > best_d:
			best_d = md
			best = sp
	return best

func _place(p: Dictionary, sp: Vector3) -> void:
	p["pos"] = sp
	p["yaw"] = randf() * TAU
	p["alive"] = true
	p["hp"] = 100
	p["last_state"] = _now()
	p["ignore_until"] = _now() + 0.5
	p["protect_until"] = _now() + 2.0

func _spawn_player(r: Dictionary, p: Dictionary, with_match_start: bool) -> void:
	_reset_player(p)
	var sp := _pick_spawn(r, p["id"])
	_place(p, sp)
	if with_match_start:
		s_match_start.rpc_id(p["id"], _room_info(r), sp, p["yaw"])
	else:
		s_spawn.rpc_id(p["id"], sp, p["yaw"])
	s_hp.rpc_id(p["id"], 100, 0)
	_send_ammo(p, 0.0)

func _send_ammo(p: Dictionary, reload_time: float) -> void:
	var w: int = p["weapon"]
	s_ammo.rpc_id(p["id"], w, int(p["mag"][w]), int(p["reserve"][w]), reload_time)

# ---------------- movement (client-predicted, server-validated) ----------------
@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(pos: Vector3, yaw: float, pitch: float) -> void:
	if not is_server_mode:
		return
	var id := multiplayer.get_remote_sender_id()
	var p = players.get(id)
	if p == null or not p["alive"]:
		return
	var now := _now()
	if now < float(p["ignore_until"]):
		return
	var dt := clampf(now - float(p["last_state"]), 0.02, 0.6)
	var old: Vector3 = p["pos"]
	var flat := Vector2(pos.x - old.x, pos.z - old.z).length()
	var ok := flat <= Cfg.RUN_SPEED * 1.4 * dt + 0.8
	ok = ok and absf(pos.x) < HALF_LIMIT and absf(pos.z) < HALF_LIMIT and pos.y > -1.0 and pos.y < 14.0
	if ok and _inside_solid(pos):
		ok = false
	if not ok:
		s_correct.rpc_id(id, old)
		p["last_state"] = now
		return
	p["pos"] = pos
	p["yaw"] = yaw
	p["pitch"] = clampf(pitch, -1.2, 1.2)
	p["last_state"] = now

const HALF_LIMIT := 98.0

func _inside_solid(pos: Vector3) -> bool:
	for a in map.solids:
		if pos.x > a.position.x + 0.12 and pos.x < a.end.x - 0.12 and pos.z > a.position.z + 0.12 and pos.z < a.end.z - 0.12 and pos.y < a.end.y - 0.35 and pos.y > a.position.y - 0.2:
			return true
	return false

# ---------------- weapons ----------------
@rpc("any_peer", "call_remote", "reliable")
func c_switch(w: int) -> void:
	if not is_server_mode:
		return
	var p = players.get(multiplayer.get_remote_sender_id())
	if p == null or not p["alive"] or w < 0 or w > 1:
		return
	if not settings["weapons_enabled"][Cfg.W_KEYS[w]]:
		s_error.rpc_id(p["id"], "%s is disabled by the admin." % Cfg.W_NAMES[w])
		return
	p["weapon"] = w
	p["reload_end"] = 0.0
	_send_ammo(p, 0.0)

@rpc("any_peer", "call_remote", "reliable")
func c_reload() -> void:
	if not is_server_mode:
		return
	var p = players.get(multiplayer.get_remote_sender_id())
	if p != null and p["alive"]:
		_start_reload(p)

func _start_reload(p: Dictionary) -> void:
	var w: int = p["weapon"]
	if float(p["reload_end"]) > 0.0 or int(p["mag"][w]) >= int(Cfg.W_MAG[w]) or int(p["reserve"][w]) <= 0:
		return
	p["reload_end"] = _now() + float(Cfg.W_RELOAD[w])
	_send_ammo(p, float(Cfg.W_RELOAD[w]))

func _spread_dir(d: Vector3, amt: float) -> Vector3:
	if amt <= 0.0:
		return d
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var right := d.cross(up).normalized()
	var u2 := right.cross(d).normalized()
	return (d + right * randf_range(-amt, amt) + u2 * randf_range(-amt, amt)).normalized()

func _wall_dist(origin: Vector3, d: Vector3, max_t: float) -> float:
	var best := max_t
	if d.y < -0.0001:
		best = minf(best, -origin.y / d.y)
	for a in map.solids:
		var hit = a.intersects_ray(origin, d)
		if hit != null:
			var t := origin.distance_to(hit)
			if t > 0.0 and t < best:
				best = t
	return best

@rpc("any_peer", "call_remote", "reliable")
func c_shoot(dir: Vector3) -> void:
	if not is_server_mode:
		return
	var id := multiplayer.get_remote_sender_id()
	var p = players.get(id)
	if p == null or not p["alive"] or not rooms.has(p["room"]):
		return
	var r = rooms[p["room"]]
	if r["state"] != "playing" or dir.length() < 0.5:
		return
	var now := _now()
	var w: int = p["weapon"]
	if float(p["reload_end"]) > 0.0 or now < float(p["next_fire"]):
		return
	if not settings["weapons_enabled"][Cfg.W_KEYS[w]]:
		return
	if int(p["mag"][w]) <= 0:
		_start_reload(p)
		return
	dir = dir.normalized()
	p["mag"][w] -= 1
	p["next_fire"] = now + float(Cfg.W_INTERVAL[w]) * 0.9
	p["fired_at"] = now
	p["protect_until"] = 0.0
	var origin: Vector3 = p["pos"] + Vector3(0, 1.5, 0)
	var dmg_each: float = float(settings["damage"][Cfg.W_KEYS[w]])
	var dmg_map := {}
	var ends := PackedVector3Array()
	for i in range(int(Cfg.W_PELLETS[w])):
		var d := _spread_dir(dir, float(Cfg.W_SPREAD[w]))
		var best_t := _wall_dist(origin, d, float(Cfg.W_RANGE[w]))
		var victim := 0
		var head := false
		for oid in r["members"]:
			if oid == id:
				continue
			var o = players[oid]
			if not o["alive"] or now < float(o["protect_until"]):
				continue
			var opos: Vector3 = o["pos"]
			if (opos + Vector3(0, 1.0, 0)).distance_to(origin) > best_t + 2.0:
				continue
			for k in range(3):
				var c: Vector3 = opos + Vector3(0, SPH_Y[k], 0)
				var res := Geometry3D.segment_intersects_sphere(origin, origin + d * best_t, c, SPH_R[k])
				if res.size() > 0:
					var t := origin.distance_to(res[0])
					if t < best_t:
						best_t = t
						victim = oid
						head = (k == 2)
		ends.append(origin + d * best_t)
		if victim != 0:
			dmg_map[victim] = int(dmg_map.get(victim, 0)) + int(dmg_each * (1.5 if head else 1.0))
	for m in r["members"]:
		if m != id:
			s_shot_fx.rpc_id(m, id, origin, ends, w)
	for v in dmg_map:
		if players[v]["alive"]:
			_damage(r, id, v, int(dmg_map[v]))
	if players.has(id):
		_send_ammo(p, 0.0)

func _damage(r: Dictionary, attacker: int, victim: int, amount: int) -> void:
	var v = players[victim]
	var a = players[attacker]
	v["hp"] = int(v["hp"]) - amount
	var killed: bool = int(v["hp"]) <= 0
	if killed:
		v["hp"] = 0
		v["alive"] = false
		v["deaths"] += 1
		v["respawn_at"] = _now() + float(cfg["respawn_seconds"])
		v["reload_end"] = 0.0
		a["kills"] += 1
		var w: int = a["weapon"]
		a["reserve"][w] = mini(int(a["reserve"][w]) + int(Cfg.W_RESERVE_KILL[w]), int(Cfg.W_RESERVE_MAX[w]))
	s_hp.rpc_id(victim, v["hp"], attacker)
	s_hit_confirm.rpc_id(attacker, victim, killed)
	if killed:
		var txt := "%s eliminated %s" % [a["name"], v["name"]]
		for m in r["members"]:
			s_kill_feed.rpc_id(m, txt)
		_send_ammo(a, 0.0)
		_room_broadcast_info(r)
		if int(a["kills"]) >= int(r["target"]):
			_end_match(r, "Kill target reached")

func _end_match(r: Dictionary, reason: String) -> void:
	if r["state"] != "playing":
		return
	r["state"] = "ended"
	r["lobby_at"] = _now() + 12.0
	var board := []
	for m in r["members"]:
		var p = players[m]
		board.append({"id": m, "name": p["name"], "kills": p["kills"], "deaths": p["deaths"]})
	board.sort_custom(func(x, y): return x["kills"] > y["kills"] or (x["kills"] == y["kills"] and x["deaths"] < y["deaths"]))
	var winner := "Nobody"
	if board.size() > 0:
		winner = str(board[0]["name"])
		if board.size() > 1 and board[0]["kills"] == board[1]["kills"] and board[0]["deaths"] == board[1]["deaths"]:
			winner = "Draw"
	for m in r["members"]:
		players[m]["alive"] = false
		s_match_end.rpc_id(m, {"board": board, "winner": winner, "reason": reason, "back_in": 12})
	_room_broadcast_info(r)

@rpc("any_peer", "call_remote", "unreliable")
func c_ping(t: int) -> void:
	if is_server_mode:
		s_pong.rpc_id(multiplayer.get_remote_sender_id(), t)
