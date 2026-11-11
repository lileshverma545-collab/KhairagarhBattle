extends CanvasLayer
## Touch HUD: joystick, look area, buttons, health, ammo, mini-map, timer, scoreboard, winner screen.

const Cfg = preload("res://scripts/cfg.gd")

class Joy extends Control:
	var knob := Vector2.ZERO
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_circle(c, r, Color(0, 0, 0, 0.30))
		draw_arc(c, r - 2.0, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
		draw_circle(c + knob, r * 0.38, Color(1, 1, 1, 0.45))

class Btn extends Control:
	var text := ""
	var held := false
	var finger := -1
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0, 0, 0, 0.35))
		draw_arc(c, r - 2.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8 if held else 0.45), 3.0)
		if held:
			draw_circle(c, r - 4.0, Color(1, 1, 1, 0.22))
		var f := ThemeDB.fallback_font
		var fs := int(r * 0.40)
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

class Overlay extends Control:
	var hud
	func _draw() -> void:
		hud.draw_overlay(self)

var world
var move_vec := Vector2.ZERO
var fire_held := false
var look_acc := Vector2.ZERO
var _jump := false
var _reload := false
var _swap := false
var joy_finger := -1
var look_finger := -1
var joy: Joy
var btn_fire: Btn
var btn_jump: Btn
var btn_reload: Btn
var btn_swap: Btn
var btn_score: Btn
var overlay: Overlay
var minimap_tex: ImageTexture
var timer_lbl: Label
var target_lbl: Label
var announce_lbl: Label
var score_lbl: Label
var feed_lbl: Label
var ping_lbl: Label
var msg_lbl: Label
var board_panel: PanelContainer
var board_grid: GridContainer
var board_title: Label
var board_info: Label
var leave_btn: Button
var feed: Array = []
var flash_t := 0.0
var hit_t := 0.0
var last_hp := 100
var result: Dictionary = {}
var result_until := 0.0
var _score_t := 0.0

func _ready() -> void:
	layer = 5
	overlay = Overlay.new()
	overlay.hud = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	joy = Joy.new()
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(joy)
	btn_fire = _mkbtn("FIRE")
	btn_jump = _mkbtn("JUMP")
	btn_reload = _mkbtn("RELOAD")
	btn_swap = _mkbtn("SWAP")
	btn_score = _mkbtn("SCORE")
	timer_lbl = _mklabel(36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	target_lbl = _mklabel(18, Color(1, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	announce_lbl = _mklabel(20, Color(1, 0.9, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
	score_lbl = _mklabel(20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	feed_lbl = _mklabel(18, Color(1, 0.8, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	ping_lbl = _mklabel(16, Color(0.8, 1, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	msg_lbl = _mklabel(46, Color(1, 0.3, 0.2), HORIZONTAL_ALIGNMENT_CENTER)
	_build_board()
	_build_minimap_texture()
	get_viewport().size_changed.connect(_layout)
	_layout()
	Net.kill_feed.connect(func(t): feed.append([t, Time.get_ticks_msec() / 1000.0 + 6.0]))
	Net.hit_confirm.connect(func(_v, _k): hit_t = 0.25)
	Net.hp_changed.connect(_on_hp)
	Net.match_ended.connect(_on_match_end)
	Net.room_updated.connect(func(_i): _refresh_board())
	Net.ping_updated.connect(func(ms): ping_lbl.text = "Ping %d ms" % ms)

func _mkbtn(t: String) -> Btn:
	var b := Btn.new()
	b.text = t
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	return b

func _mklabel(fs: int, col: Color, al: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = al
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _place_btn(b: Btn, c: Vector2, r: float) -> void:
	b.position = c - Vector2(r, r)
	b.size = Vector2(r * 2.0, r * 2.0)

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	overlay.position = Vector2.ZERO
	overlay.size = s
	joy.size = Vector2(190, 190)
	joy.position = Vector2(70, s.y - 260)
	_place_btn(btn_fire, Vector2(s.x - 170, s.y - 150), 78)
	_place_btn(btn_jump, Vector2(s.x - 62, s.y - 255), 46)
	_place_btn(btn_reload, Vector2(s.x - 305, s.y - 85), 44)
	_place_btn(btn_swap, Vector2(s.x - 310, s.y - 200), 44)
	_place_btn(btn_score, Vector2(s.x - 70, s.y - 360), 38)
	timer_lbl.position = Vector2(s.x * 0.5 - 100, 4)
	timer_lbl.size = Vector2(200, 44)
	target_lbl.position = Vector2(s.x * 0.5 - 150, 50)
	target_lbl.size = Vector2(300, 26)
	announce_lbl.position = Vector2(s.x * 0.5 - 300, 78)
	announce_lbl.size = Vector2(600, 28)
	score_lbl.position = Vector2(16, 12)
	feed_lbl.position = Vector2(16, 150)
	ping_lbl.position = Vector2(16, s.y - 30)
	msg_lbl.position = Vector2(s.x * 0.5 - 300, s.y * 0.3)
	msg_lbl.size = Vector2(600, 60)
	board_panel.position = Vector2(s.x * 0.5 - 260, 40)
	board_panel.size = Vector2(520, 200)

func _build_board() -> void:
	board_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	board_panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	board_panel.add_child(vb)
	board_title = Label.new()
	board_title.add_theme_font_size_override("font_size", 34)
	board_title.add_theme_color_override("font_color", Color(1, 0.75, 0.25))
	board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(board_title)
	board_info = Label.new()
	board_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(board_info)
	board_grid = GridContainer.new()
	board_grid.columns = 4
	board_grid.add_theme_constant_override("h_separation", 28)
	vb.add_child(board_grid)
	leave_btn = Button.new()
	leave_btn.text = "Leave match"
	leave_btn.custom_minimum_size = Vector2(200, 54)
	leave_btn.pressed.connect(func(): Net.leave_room())
	vb.add_child(leave_btn)
	board_panel.visible = false
	add_child(board_panel)

func _refresh_board() -> void:
	for c in board_grid.get_children():
		c.queue_free()
	var rows: Array = []
	if not result.is_empty():
		rows = result["board"]
	else:
		rows = Net.room.get("members", []).duplicate()
		rows.sort_custom(func(a, b): return a["kills"] > b["kills"])
	for h in ["#", "Player", "Kills", "Deaths"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(0.6, 0.8, 1))
		board_grid.add_child(l)
	var i := 1
	for r in rows:
		for t in [str(i), str(r["name"]), str(r["kills"]), str(r["deaths"])]:
			var l := Label.new()
			l.text = t
			if int(r["id"]) == Net.my_id():
				l.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
			board_grid.add_child(l)
		i += 1
	board_panel.size = Vector2(520, 100)

func _build_minimap_texture() -> void:
	var img := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.28, 0.45, 0.2))
	for r in Net.map.roads:
		img.fill_rect(Rect2i(int(r.position.x + 100.0), int(r.position.y + 100.0), int(r.size.x), int(r.size.y)).intersection(Rect2i(0, 0, 200, 200)), Color(0.22, 0.22, 0.25))
	for a in Net.map.solids:
		if a.size.x > 2.5 and a.size.z > 2.5 and a.size.y > 2.0:
			var rc := Rect2i(int(a.position.x + 100.0), int(a.position.z + 100.0), int(a.size.x), int(a.size.z)).intersection(Rect2i(0, 0, 200, 200))
			img.fill_rect(rc, Color(0.85, 0.62, 0.35))
	minimap_tex = ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- input
func take_look() -> Vector2:
	var v := look_acc
	look_acc = Vector2.ZERO
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT): k.x -= 14.0
	if Input.is_key_pressed(KEY_RIGHT): k.x += 14.0
	if Input.is_key_pressed(KEY_UP): k.y -= 10.0
	if Input.is_key_pressed(KEY_DOWN): k.y += 10.0
	return v + k

func take_jump() -> bool:
	var j := _jump or Input.is_key_pressed(KEY_SPACE)
	_jump = false
	return j

func take_reload() -> bool:
	var j := _reload or Input.is_key_pressed(KEY_R)
	_reload = false
	return j

func take_swap() -> bool:
	var j := _swap
	_swap = false
	return j

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_move(event.index, event.position, event.relative)

func _hit_btn(b: Btn, p: Vector2) -> bool:
	var c := b.position + b.size * 0.5
	return p.distance_to(c) <= b.size.x * 0.5 + 8.0

func _touch_down(idx: int, p: Vector2) -> void:
	if board_panel.visible and board_panel.get_global_rect().has_point(p):
		return
	for b in [btn_fire, btn_jump, btn_reload, btn_swap, btn_score]:
		if b.finger == -1 and _hit_btn(b, p):
			b.finger = idx
			b.held = true
			b.queue_redraw()
			if b == btn_fire:
				fire_held = true
			elif b == btn_jump:
				_jump = true
			elif b == btn_reload:
				_reload = true
			elif b == btn_swap:
				_swap = true
			elif b == btn_score:
				_toggle_board()
			return
	var jc := joy.position + joy.size * 0.5
	if joy_finger == -1 and p.distance_to(jc) < 150.0:
		joy_finger = idx
		_joy_update(p)
		return
	if look_finger == -1 and p.x > get_viewport().get_visible_rect().size.x * 0.35:
		look_finger = idx

func _touch_move(idx: int, p: Vector2, rel: Vector2) -> void:
	if idx == joy_finger:
		_joy_update(p)
	elif idx == look_finger:
		look_acc += rel

func _touch_up(idx: int) -> void:
	for b in [btn_fire, btn_jump, btn_reload, btn_swap, btn_score]:
		if b.finger == idx:
			b.finger = -1
			b.held = false
			b.queue_redraw()
			if b == btn_fire:
				fire_held = false
	if idx == joy_finger:
		joy_finger = -1
		move_vec = Vector2.ZERO
		joy.knob = Vector2.ZERO
		joy.queue_redraw()
	if idx == look_finger:
		look_finger = -1

func _joy_update(p: Vector2) -> void:
	var jc := joy.position + joy.size * 0.5
	var d := p - jc
	var r := joy.size.x * 0.5
	var v := d / r
	if v.length() > 1.0:
		v = v.normalized()
	move_vec = v if v.length() > 0.12 else Vector2.ZERO
	joy.knob = v * r * 0.6
	joy.queue_redraw()

func _toggle_board() -> void:
	if result.is_empty():
		board_title.text = "SCOREBOARD"
		board_info.text = ""
		leave_btn.text = "Leave match"
		board_panel.visible = not board_panel.visible
		if board_panel.visible:
			_refresh_board()

func _on_hp(h: int, _from: int) -> void:
	if h < last_hp and h > 0:
		flash_t = 0.5
	last_hp = h

func _on_match_end(res: Dictionary) -> void:
	result = res
	result_until = Time.get_ticks_msec() / 1000.0 + float(res.get("back_in", 12))
	board_title.text = "WINNER: %s" % str(res.get("winner", "-"))
	board_info.text = str(res.get("reason", ""))
	leave_btn.text = "Back to menu"
	board_panel.visible = true
	_refresh_board()
	fire_held = false

# ---------------------------------------------------------------- per-frame
func _process(delta: float) -> void:
	if world == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	# keyboard fallback (desktop testing)
	if joy_finger == -1:
		var k := Vector2.ZERO
		if Input.is_key_pressed(KEY_W): k.y -= 1.0
		if Input.is_key_pressed(KEY_S): k.y += 1.0
		if Input.is_key_pressed(KEY_A): k.x -= 1.0
		if Input.is_key_pressed(KEY_D): k.x += 1.0
		move_vec = k.normalized()
	if btn_fire.finger == -1:
		fire_held = Input.is_key_pressed(KEY_F)
	flash_t = maxf(0.0, flash_t - delta)
	hit_t = maxf(0.0, hit_t - delta)
	var left := maxf(0.0, Net.room_end_local - now)
	timer_lbl.text = "%02d:%02d" % [int(left) / 60, int(left) % 60]
	target_lbl.text = "First to %d kills" % int(Net.room.get("target", 20))
	announce_lbl.text = Net.announcement
	_score_t -= delta
	if _score_t <= 0.0:
		_score_t = 0.5
		var rows: Array = Net.room.get("members", []).duplicate()
		rows.sort_custom(func(a, b): return a["kills"] > b["kills"])
		var t := ""
		var n := 0
		for r in rows:
			if n >= 4:
				break
			n += 1
			t += "%d. %s  %d\n" % [n, r["name"], r["kills"]]
		score_lbl.text = t
		if not result.is_empty():
			_refresh_board()
	var ft := ""
	for i in range(feed.size() - 1, -1, -1):
		if now > float(feed[i][1]):
			feed.remove_at(i)
	for f in feed:
		ft += str(f[0]) + "\n"
	feed_lbl.text = ft
	if not world.alive and result.is_empty():
		var rem := maxf(0.0, world.respawn_local - now)
		msg_lbl.text = "ELIMINATED\nRespawning in %d" % int(ceil(rem))
	else:
		msg_lbl.text = ""
	overlay.queue_redraw()

func draw_overlay(c: Control) -> void:
	if world == null:
		return
	var s := c.size
	var now := Time.get_ticks_msec() / 1000.0
	var f := ThemeDB.fallback_font
	if flash_t > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 0, 0, flash_t * 0.4))
	# crosshair
	var ctr := s * 0.5
	c.draw_line(ctr + Vector2(-16, 0), ctr + Vector2(-6, 0), Color(1, 1, 1, 0.9), 2.0)
	c.draw_line(ctr + Vector2(6, 0), ctr + Vector2(16, 0), Color(1, 1, 1, 0.9), 2.0)
	c.draw_line(ctr + Vector2(0, -16), ctr + Vector2(0, -6), Color(1, 1, 1, 0.9), 2.0)
	c.draw_line(ctr + Vector2(0, 6), ctr + Vector2(0, 16), Color(1, 1, 1, 0.9), 2.0)
	if hit_t > 0.0:
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			c.draw_line(ctr + d * 7.0, ctr + d * 15.0, Color(1, 0.2, 0.2), 3.0)
	# health bar
	var bw := 380.0
	var bx := s.x * 0.5 - bw * 0.5
	var by := s.y - 46.0
	var ratio := clampf(float(world.hp) / 100.0, 0.0, 1.0)
	c.draw_rect(Rect2(bx - 3, by - 3, bw + 6, 28), Color(0, 0, 0, 0.6))
	c.draw_rect(Rect2(bx, by, bw * ratio, 22), Color(1.0 - ratio, 0.25 + 0.6 * ratio, 0.15))
	c.draw_string(f, Vector2(bx + 10, by + 18), "HP %d/100" % world.hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# weapon panel
	var px := s.x - 250.0
	for w in range(2):
		var py := 200.0 + float(w) * 52.0
		var active: bool = (w == world.weapon)
		c.draw_rect(Rect2(px, py, 236, 46), Color(0.1, 0.12, 0.2, 0.8) if not active else Color(0.8, 0.5, 0.1, 0.8))
		c.draw_string(f, Vector2(px + 10, py + 20), Cfg.W_NAMES[w], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		c.draw_string(f, Vector2(px + 10, py + 40), "%d / %d" % [world.mag[w], world.reserve[w]], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.7))
	# reload bar
	if world.reload_until > now:
		var pr := 1.0 - (world.reload_until - now) / maxf(world.reload_len, 0.1)
		c.draw_rect(Rect2(ctr.x - 60, ctr.y + 40, 120, 10), Color(0, 0, 0, 0.6))
		c.draw_rect(Rect2(ctr.x - 60, ctr.y + 40, 120 * clampf(pr, 0.0, 1.0), 10), Color(1, 0.8, 0.2))
		c.draw_string(f, Vector2(ctr.x - 40, ctr.y + 36), "RELOADING", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	# mini-map (100 m window around player)
	var ms := 176.0
	var mp := Vector2(s.x - ms - 10.0, 10.0)
	var pp: Vector3 = world.me.global_position
	var org := Vector2(clampf(pp.x + 100.0 - 50.0, 0.0, 100.0), clampf(pp.z + 100.0 - 50.0, 0.0, 100.0))
	c.draw_rect(Rect2(mp - Vector2(3, 3), Vector2(ms + 6, ms + 6)), Color(0, 0, 0, 0.7))
	c.draw_texture_rect_region(minimap_tex, Rect2(mp, Vector2(ms, ms)), Rect2(org, Vector2(100, 100)))
	var k := ms / 100.0
	for lm in Net.map.landmarks:
		var lp: Vector3 = Net.map.landmarks[lm]
		var q := Vector2(lp.x + 100.0 - org.x, lp.z + 100.0 - org.y) * k
		if q.x > 0 and q.y > 0 and q.x < ms and q.y < ms:
			c.draw_string(f, mp + q + Vector2(-20, 0), lm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.9))
	for id in world.others:
		var av = world.others[id]
		if av.alive:
			var q2 := Vector2(av.global_position.x + 100.0 - org.x, av.global_position.z + 100.0 - org.y) * k
			if q2.x > 0 and q2.y > 0 and q2.x < ms and q2.y < ms:
				c.draw_circle(mp + q2, 4.0, Color(1, 0.2, 0.2))
	var me2 := Vector2(pp.x + 100.0 - org.x, pp.z + 100.0 - org.y) * k
	var ang: float = world.yaw
	var dirv := Vector2(-sin(ang), -cos(ang))
	var side := Vector2(-dirv.y, dirv.x)
	var tip := mp + me2 + dirv * 9.0
	c.draw_colored_polygon(PackedVector2Array([tip, mp + me2 - dirv * 5.0 + side * 5.0, mp + me2 - dirv * 5.0 - side * 5.0]), Color(0.3, 0.9, 1.0))
