extends CanvasLayer
## Main menu + room lobby (built entirely in code).

const Cfg = preload("res://scripts/cfg.gd")

var name_edit: LineEdit
var addr_edit: LineEdit
var code_edit: LineEdit
var status: Label
var announce: Label
var main_box: Control
var lobby_box: Control
var room_code_lbl: Label
var players_lbl: Label
var start_btn: Button
var lobby_info: Label

func _ready() -> void:
	layer = 1
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(0.95, 0.5, 0.1)
	stripe.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stripe.custom_minimum_size = Vector2(0, 10)
	stripe.size = Vector2(0, 10)
	add_child(stripe)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)
	var title := _label("KHAIRAGARH BATTLE", 56, Color(1.0, 0.65, 0.15))
	root.add_child(title)
	root.add_child(_label("PIN 491881  -  Online Multiplayer Shooter", 20, Color(0.7, 0.85, 1.0)))
	announce = _label("", 20, Color(1, 0.9, 0.3))
	root.add_child(announce)
	main_box = _build_main()
	lobby_box = _build_lobby()
	root.add_child(main_box)
	root.add_child(lobby_box)
	lobby_box.visible = false
	status = _label("", 20, Color(1, 0.8, 0.4))
	root.add_child(status)
	Net.error_msg.connect(func(t): status.text = t)
	Net.room_joined.connect(_on_room_joined)
	Net.room_updated.connect(_on_room_updated)
	Net.room_left.connect(show_main)
	Net.server_info_changed.connect(_on_server_info)
	Net.connect_failed.connect(func(): pass)
	Net.net_disconnected.connect(func(): status.text = "Disconnected from server."; show_main())

func _label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(t: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(300, 60)
	b.add_theme_font_size_override("font_size", 24)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if st == "normal" else (col.lightened(0.15) if st == "hover" else col.darkened(0.2))
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(8)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b

func _edit(placeholder: String, text: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(300, 52)
	e.add_theme_font_size_override("font_size", 22)
	return e

func _build_main() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 40)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.add_child(_label("Username", 18, Color.WHITE))
	name_edit = _edit("Your name", Net.my_name)
	name_edit.max_length = 14
	left.add_child(name_edit)
	left.add_child(_label("Player ID: %s" % Net.my_pid, 18, Color(0.6, 0.8, 1)))
	left.add_child(_label("Server address (IP or domain)", 18, Color.WHITE))
	addr_edit = _edit("e.g. 203.0.113.10", Net.server_addr if Net.server_addr != "YOUR_SERVER_IP_OR_DOMAIN" else "")
	left.add_child(addr_edit)
	left.add_child(_button("Check Server", Color(0.25, 0.35, 0.55), func(): _prepare(); status.text = "Checking server..."; Net.check_server()))
	var sh := CheckBox.new()
	sh.text = "Shadows (prettier, slower)"
	sh.button_pressed = Net.shadows_on
	sh.add_theme_font_size_override("font_size", 20)
	sh.toggled.connect(func(v): Net.shadows_on = v; Net.save_local())
	left.add_child(sh)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.add_child(_label("Play with friends", 18, Color.WHITE))
	right.add_child(_button("CREATE ROOM", Color(0.9, 0.45, 0.1), func(): _prepare(); status.text = "Connecting..."; Net.create_room()))
	code_edit = _edit("Room code", "")
	code_edit.max_length = 5
	code_edit.add_theme_font_size_override("font_size", 28)
	right.add_child(code_edit)
	right.add_child(_button("JOIN ROOM", Color(0.15, 0.55, 0.35), func(): _prepare(); status.text = "Connecting..."; Net.join_room(code_edit.text)))
	right.add_child(_label("Camera sensitivity", 18, Color.WHITE))
	var sl := HSlider.new()
	sl.min_value = 0.5
	sl.max_value = 2.0
	sl.step = 0.1
	sl.value = Net.sens
	sl.custom_minimum_size = Vector2(300, 30)
	sl.value_changed.connect(func(v): Net.sens = v; Net.save_local())
	right.add_child(sl)
	hb.add_child(left)
	hb.add_child(right)
	return hb

func _build_lobby() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.add_child(_label("ROOM CODE", 20, Color(0.7, 0.85, 1)))
	room_code_lbl = _label("-----", 72, Color(1, 0.85, 0.3))
	vb.add_child(room_code_lbl)
	vb.add_child(_label("Share this code with friends - they tap JOIN ROOM", 18, Color.WHITE))
	players_lbl = _label("", 24, Color.WHITE)
	vb.add_child(players_lbl)
	lobby_info = _label("", 18, Color(0.8, 0.8, 0.8))
	vb.add_child(lobby_info)
	start_btn = _button("START MATCH", Color(0.9, 0.45, 0.1), func(): Net.start_match())
	vb.add_child(start_btn)
	vb.add_child(_button("Leave Room", Color(0.5, 0.2, 0.2), func(): Net.leave_room()))
	for c in vb.get_children():
		if c is Button:
			c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return vb

func _prepare() -> void:
	Net.my_name = Net.clean_name(name_edit.text)
	Net.server_addr = addr_edit.text.strip_edges()
	Net.save_local()

func show_main() -> void:
	main_box.visible = true
	lobby_box.visible = false
	visible = true

func _on_server_info() -> void:
	announce.text = Net.announcement

func _on_room_joined(info: Dictionary) -> void:
	status.text = ""
	main_box.visible = false
	lobby_box.visible = true
	visible = true
	_on_room_updated(info)

func _on_room_updated(info: Dictionary) -> void:
	room_code_lbl.text = str(info["code"])
	var t := ""
	for m in info["members"]:
		t += str(m["name"]) + ("  (host)" if int(m["id"]) == int(info["host"]) else "") + "\n"
	players_lbl.text = t
	var is_host: bool = int(info["host"]) == Net.my_id()
	start_btn.visible = is_host
	lobby_info.text = "Players: %d / %d" % [info["members"].size(), info["max"]] + ("" if is_host else "   -   waiting for host to start")
