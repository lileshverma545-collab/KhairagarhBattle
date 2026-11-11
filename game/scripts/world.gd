extends Node3D
## Client-side 3D world: map, lighting, local player (third-person), remote players, effects.

const Cfg = preload("res://scripts/cfg.gd")
const MeshUtil = preload("res://scripts/mesh_util.gd")
const Avatar = preload("res://scripts/avatar.gd")

var hud
var me: CharacterBody3D
var me_avatar
var cam: Camera3D
var light: DirectionalLight3D
var yaw := 0.0
var pitch := 0.1
var hp := 100
var alive := true
var weapon := 0
var mag := [30, 6]
var reserve := [120, 24]
var reload_until := 0.0
var reload_len := 1.0
var next_fire := 0.0
var others := {}
var state_timer := 0.0
var respawn_local := 0.0
var _speed := 0.0

func _ready() -> void:
	_build_environment()
	_build_map()
	_build_player()
	Net.spawned.connect(_on_spawned)
	Net.snapshot_received.connect(_on_snapshot)
	Net.hp_changed.connect(_on_hp)
	Net.ammo_changed.connect(_on_ammo)
	Net.shot_fx.connect(_on_shot_fx)
	Net.corrected.connect(_on_corrected)
	Net.room_updated.connect(_on_room_updated)
	Net.match_ended.connect(func(_r): alive = false)

func start(spawn: Vector3, yw: float) -> void:
	me.global_position = spawn + Vector3(0, 0.1, 0)
	me.velocity = Vector3.ZERO
	yaw = yw
	hp = 100
	alive = true
	weapon = 0
	me_avatar.set_weapon(0)
	me_avatar.set_dead(false)

# ---------------------------------------------------------------- build
func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.45, 0.85)
	sm.sky_horizon_color = Color(0.72, 0.84, 0.94)
	sm.ground_horizon_color = Color(0.72, 0.84, 0.94)
	sm.ground_bottom_color = Color(0.3, 0.4, 0.25)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.85, 0.95)
	env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -35, 0)
	light.light_energy = 1.15
	light.light_color = Color(1.0, 0.96, 0.88)
	light.shadow_enabled = Net.shadows_on
	light.directional_shadow_max_distance = 60.0
	add_child(light)

func _build_map() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in Net.map.visuals:
		match v[0]:
			"box":
				MeshUtil.add_box(st, v[1], v[2], v[3])
			"pyr":
				MeshUtil.add_pyr(st, v[1], v[2], v[3], v[4])
			"cyl":
				MeshUtil.add_cyl(st, v[1], v[2], v[3], v[4])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	mi.material_override = m
	add_child(mi)
	var body := StaticBody3D.new()
	add_child(body)
	for a in Net.map.solids:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = a.size
		cs.shape = bs
		cs.position = a.get_center()
		body.add_child(cs)
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(260, 2, 260)
	gs.shape = gb
	gs.position = Vector3(0, -1, 0)
	body.add_child(gs)

func _build_player() -> void:
	me = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	me.add_child(cs)
	add_child(me)
	me_avatar = Avatar.new()
	me.add_child(me_avatar)
	me_avatar.setup(Net.my_name, 0, false)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 250.0
	add_child(cam)
	cam.current = true

# ---------------------------------------------------------------- frame
func _physics_process(delta: float) -> void:
	if hud == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var look: Vector2 = hud.take_look()
	yaw -= look.x * 0.0045 * Net.sens
	pitch = clampf(pitch - look.y * 0.0035 * Net.sens, -0.8, 1.1)
	var mv: Vector2 = hud.move_vec
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := right * mv.x + fwd * -mv.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	if alive:
		me.velocity.x = wish.x * Cfg.RUN_SPEED
		me.velocity.z = wish.z * Cfg.RUN_SPEED
	else:
		me.velocity.x = 0.0
		me.velocity.z = 0.0
	var jump: bool = hud.take_jump()
	if me.is_on_floor():
		me.velocity.y = 0.0
		if jump and alive:
			me.velocity.y = 7.5
	else:
		me.velocity.y -= 22.0 * delta
	me.move_and_slide()
	var p := me.global_position
	p.x = clampf(p.x, -97.0, 97.0)
	p.z = clampf(p.z, -97.0, 97.0)
	if p.y < -5.0:
		p = Vector3(0, 1, 8)
		me.velocity = Vector3.ZERO
	me.global_position = p
	_speed = Vector2(me.velocity.x, me.velocity.z).length()
	me_avatar.rotation.y = yaw
	me_avatar.pitch = pitch
	me_avatar.animate(delta, _speed)
	_update_camera(right)
	# weapon switch / reload
	if hud.take_swap() and alive:
		var nw := 1 - weapon
		weapon = nw
		reload_until = 0.0
		me_avatar.set_weapon(nw)
		Net.send_switch(nw)
	if hud.take_reload() and alive:
		_request_reload(now)
	if alive and hud.fire_held and now >= next_fire and now >= reload_until:
		_fire(now)
	if reload_until > 0.0 and now >= reload_until:
		reload_until = 0.0
	state_timer += delta
	if state_timer >= 0.05:
		state_timer = 0.0
		Net.send_state(me.global_position, yaw, pitch)

func _update_camera(right: Vector3) -> void:
	var head := me.global_position + Vector3(0, 1.55, 0)
	var cd := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var start := head + right * 0.75
	var want := start - cd * 3.4 + Vector3(0, 0.35, 0)
	var q := PhysicsRayQueryParameters3D.create(start, want)
	q.exclude = [me.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = hit["position"] + (start - want).normalized() * 0.2
	cam.global_position = want
	cam.look_at(want + cd * 50.0, Vector3.UP)

func _aim_point() -> Vector3:
	var from := cam.global_position
	var cd := -cam.global_transform.basis.z
	var far := from + cd * 150.0
	var q := PhysicsRayQueryParameters3D.create(from, far)
	q.exclude = [me.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or from.distance_to(hit["position"]) < 5.0:
		return far
	return hit["position"]

func _fire(now: float) -> void:
	if int(mag[weapon]) <= 0:
		_request_reload(now)
		return
	var origin := me.global_position + Vector3(0, 1.5, 0)
	var target := _aim_point()
	var d := target - origin
	if d.length() < 1.5:
		d = -cam.global_transform.basis.z
	d = d.normalized()
	Net.send_shoot(d)
	mag[weapon] = int(mag[weapon]) - 1
	next_fire = now + float(Cfg.W_INTERVAL[weapon])
	me_avatar.flash()
	_tracer(me_avatar.muzzle_pos(), target)
	if origin.distance_to(target) < 140.0:
		_impact(target, Color(0.9, 0.8, 0.5))

func _request_reload(now: float) -> void:
	if reload_until > 0.0 or int(mag[weapon]) >= int(Cfg.W_MAG[weapon]) or int(reserve[weapon]) <= 0:
		return
	Net.send_reload()
	reload_len = float(Cfg.W_RELOAD[weapon])
	reload_until = now + reload_len

# ---------------------------------------------------------------- effects
func _tracer(a: Vector3, b: Vector3) -> void:
	var dist := a.distance_to(b)
	if dist < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, dist)
	mi.mesh = bm
	mi.material_override = Avatar.mat(Color(1.0, 0.9, 0.5), true)
	add_child(mi)
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, up)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)

func _impact(pos: Vector3, col: Color) -> void:
	var pt := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 4
	sm.rings = 2
	pt.mesh = sm
	pt.material_override = Avatar.mat(col, true)
	pt.amount = 8
	pt.lifetime = 0.35
	pt.one_shot = true
	pt.explosiveness = 1.0
	pt.direction = Vector3.UP
	pt.spread = 80.0
	pt.initial_velocity_min = 2.0
	pt.initial_velocity_max = 4.0
	pt.gravity = Vector3(0, -9, 0)
	add_child(pt)
	pt.global_position = pos
	pt.emitting = true
	get_tree().create_timer(0.7).timeout.connect(pt.queue_free)

# ---------------------------------------------------------------- network events
func _on_spawned(pos: Vector3, yw: float) -> void:
	me.global_position = pos + Vector3(0, 0.1, 0)
	me.velocity = Vector3.ZERO
	yaw = yw
	alive = true
	me_avatar.set_dead(false)

func _on_corrected(pos: Vector3) -> void:
	if alive:
		me.global_position = pos

func _on_hp(h: int, _from: int) -> void:
	var was_alive := alive
	hp = h
	alive = h > 0
	if was_alive and not alive:
		respawn_local = Time.get_ticks_msec() / 1000.0 + 4.0
		me_avatar.set_dead(true)
	elif alive:
		me_avatar.set_dead(false)

func _on_ammo(w: int, m: int, r: int, reload_time: float) -> void:
	weapon = w
	mag[w] = m
	reserve[w] = r
	me_avatar.set_weapon(w)
	if reload_time <= 0.0:
		reload_until = 0.0
	else:
		reload_len = reload_time
		reload_until = Time.get_ticks_msec() / 1000.0 + reload_time

func _on_room_updated(_info: Dictionary) -> void:
	var ids := []
	for m in Net.room.get("members", []):
		ids.append(int(m["id"]))
	for id in others.keys():
		if not ids.has(id):
			others[id].queue_free()
			others.erase(id)
		else:
			others[id].label.text = Net.name_of(id)

func _on_snapshot(a: PackedFloat32Array) -> void:
	var i := 0
	var myid := Net.my_id()
	while i + 9 <= a.size():
		var id := int(a[i])
		var pos := Vector3(a[i + 1], a[i + 2], a[i + 3])
		var yw := a[i + 4]
		var pt := a[i + 5]
		var fl := int(a[i + 6])
		var wp := int(a[i + 8])
		i += 9
		if id == myid:
			continue
		var av = others.get(id)
		if av == null:
			av = Avatar.new()
			av.is_remote = true
			add_child(av)
			av.setup(Net.name_of(id), id, true)
			av.global_position = pos
			others[id] = av
		av.set_target(pos, yw, pt, (fl & 1) != 0, wp)

func _on_shot_fx(shooter: int, origin: Vector3, ends: PackedVector3Array, w: int) -> void:
	var av = others.get(shooter)
	var from := origin
	if av != null:
		av.flash()
		from = av.muzzle_pos()
	var n := 0
	for e in ends:
		if n < 4:
			_tracer(from, e)
		_impact(e, Color(0.9, 0.8, 0.5))
		n += 1
