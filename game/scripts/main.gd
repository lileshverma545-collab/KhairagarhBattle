extends Node
## Entry scene. Builds menu / game depending on network events. (Server mode shows nothing.)

const World = preload("res://scripts/world.gd")
const Hud = preload("res://scripts/hud.gd")
const Menu = preload("res://scripts/menu.gd")

var menu
var world
var hud

func _ready() -> void:
	if Net.is_server_mode:
		return
	menu = Menu.new()
	add_child(menu)
	Net.match_started.connect(_on_match_started)
	Net.room_updated.connect(_on_room_updated)
	Net.room_left.connect(_end_game)
	Net.net_disconnected.connect(_end_game)

func _on_match_started(_info: Dictionary, spawn: Vector3, yaw: float) -> void:
	if world != null:
		return
	menu.visible = false
	world = World.new()
	add_child(world)
	hud = Hud.new()
	hud.world = world
	world.hud = hud
	add_child(hud)
	world.start(spawn, yaw)

func _on_room_updated(info: Dictionary) -> void:
	if world != null and str(info.get("state", "")) == "lobby":
		_end_game()
		menu._on_room_joined(info)

func _end_game() -> void:
	if world != null:
		world.queue_free()
		world = null
	if hud != null:
		hud.queue_free()
		hud = null
	if menu != null:
		menu.visible = true
