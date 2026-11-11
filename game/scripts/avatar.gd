extends Node3D
## Low-poly 3D soldier built from primitives (no external assets) + weapon models + simple animation.

const PALETTE := [Color(0.15, 0.35, 0.85), Color(0.85, 0.2, 0.2), Color(0.2, 0.65, 0.3), Color(0.9, 0.6, 0.1), Color(0.6, 0.25, 0.8), Color(0.1, 0.7, 0.75), Color(0.9, 0.35, 0.6), Color(0.5, 0.5, 0.55), Color(0.55, 0.4, 0.2), Color(0.85, 0.85, 0.2)]

var root: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var gun_holder: Node3D
var gun: Node3D
var muzzle: Node3D
var flash_mesh: MeshInstance3D
var label: Label3D
var weapon := -1
var phase := 0.0
var pitch := 0.0
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var alive := true
var is_remote := false
var _last_pos := Vector3.ZERO

static func mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

static func part(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi

static func bx(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

func setup(pname: String, idx: int, show_label: bool) -> void:
	var shirt: Color = PALETTE[idx % PALETTE.size()]
	var skin := Color(0.85, 0.62, 0.45)
	var dark := Color(0.15, 0.15, 0.18)
	root = Node3D.new()
	add_child(root)
	part(root, bx(0.56, 0.66, 0.3), Vector3(0, 1.17, 0), shirt)
	part(root, bx(0.58, 0.14, 0.32), Vector3(0, 0.82, 0), dark)
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	part(root, head, Vector3(0, 1.68, 0), skin)
	part(root, bx(0.32, 0.12, 0.32), Vector3(0, 1.84, 0), Color(0.1, 0.07, 0.05))
	leg_l = Node3D.new()
	leg_l.position = Vector3(-0.14, 0.82, 0)
	root.add_child(leg_l)
	part(leg_l, bx(0.22, 0.8, 0.24), Vector3(0, -0.4, 0), Color(0.15, 0.18, 0.28))
	part(leg_l, bx(0.24, 0.1, 0.34), Vector3(0, -0.78, -0.04), Color(0.9, 0.9, 0.9))
	leg_r = Node3D.new()
	leg_r.position = Vector3(0.14, 0.82, 0)
	root.add_child(leg_r)
	part(leg_r, bx(0.22, 0.8, 0.24), Vector3(0, -0.4, 0), Color(0.15, 0.18, 0.28))
	part(leg_r, bx(0.24, 0.1, 0.34), Vector3(0, -0.78, -0.04), Color(0.9, 0.9, 0.9))
	gun_holder = Node3D.new()
	gun_holder.position = Vector3(0.0, 1.35, 0)
	root.add_child(gun_holder)
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.36, 0, 0)
	gun_holder.add_child(arm_r)
	part(arm_r, bx(0.16, 0.55, 0.16), Vector3(0, 0, -0.27), shirt).rotation.x = PI * 0.5
	arm_l = Node3D.new()
	arm_l.position = Vector3(-0.36, 0, 0)
	gun_holder.add_child(arm_l)
	part(arm_l, bx(0.16, 0.55, 0.16), Vector3(0.0, 0, -0.27), shirt).rotation.x = PI * 0.5
	arm_l.rotation.y = -0.45
	arm_r.rotation.y = 0.12
	label = Label3D.new()
	label.text = pname
	label.position = Vector3(0, 2.25, 0)
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 10
	label.font_size = 36
	label.visible = show_label
	add_child(label)
	var fm := SphereMesh.new()
	fm.radius = 0.12
	fm.height = 0.24
	flash_mesh = MeshInstance3D.new()
	flash_mesh.mesh = fm
	flash_mesh.material_override = mat(Color(1.0, 0.85, 0.3), true)
	flash_mesh.visible = false
	set_weapon(0)

func set_weapon(w: int) -> void:
	if w == weapon:
		return
	weapon = w
	if gun != null:
		gun.queue_free()
	gun = make_gun(w)
	gun.position = Vector3(0.22, -0.1, -0.1)
	gun_holder.add_child(gun)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.03, -1.05 if w == 0 else -1.0)
	gun.add_child(muzzle)
	if flash_mesh.get_parent() != null:
		flash_mesh.get_parent().remove_child(flash_mesh)
	muzzle.add_child(flash_mesh)

static func make_gun(w: int) -> Node3D:
	var g := Node3D.new()
	var metal := Color(0.12, 0.12, 0.14)
	var wood := Color(0.45, 0.28, 0.14)
	if w == 0:
		part(g, bx(0.08, 0.13, 0.55), Vector3(0, 0, -0.3), metal)
		part(g, bx(0.04, 0.04, 0.35), Vector3(0, 0.02, -0.75), Color(0.2, 0.2, 0.22))
		part(g, bx(0.07, 0.14, 0.26), Vector3(0, -0.02, 0.12), Color(0.2, 0.25, 0.15))
		part(g, bx(0.06, 0.22, 0.1), Vector3(0, -0.15, -0.25), metal).rotation.x = 0.2
		part(g, bx(0.04, 0.05, 0.12), Vector3(0, 0.09, -0.3), Color(0.3, 0.3, 0.32))
	else:
		part(g, bx(0.06, 0.06, 0.95), Vector3(0, 0.02, -0.5), metal)
		part(g, bx(0.09, 0.12, 0.3), Vector3(0, -0.01, -0.02), metal)
		part(g, bx(0.1, 0.08, 0.3), Vector3(0, -0.06, -0.5), wood)
		part(g, bx(0.08, 0.16, 0.34), Vector3(0, -0.03, 0.28), wood)
	return g

func flash() -> void:
	flash_mesh.visible = true
	get_tree().create_timer(0.05).timeout.connect(func(): if is_instance_valid(flash_mesh): flash_mesh.visible = false)

func muzzle_pos() -> Vector3:
	return muzzle.global_position

func set_dead(dead: bool) -> void:
	if dead == (not alive):
		return
	alive = not dead
	var tw := create_tween()
	if dead:
		tw.tween_property(root, "rotation:x", -PI * 0.5, 0.35)
		label.visible = false
	else:
		root.rotation.x = 0.0
		label.visible = is_remote
	visible = alive or is_remote or true

func set_target(pos: Vector3, yaw: float, pt: float, is_alive: bool, w: int) -> void:
	target_pos = pos
	target_yaw = yaw
	pitch = pt
	set_weapon(w)
	set_dead(not is_alive)

func animate(delta: float, speed: float) -> void:
	var sw := clampf(speed / 6.0, 0.0, 1.0)
	phase += delta * (4.0 + 7.0 * sw)
	var s := sin(phase) * 0.9 * sw
	leg_l.rotation.x = s
	leg_r.rotation.x = -s
	gun_holder.rotation.x = clampf(pitch, -0.9, 0.9)
	root.position.y = absf(sin(phase)) * 0.04 * sw

func _process(delta: float) -> void:
	if not is_remote:
		return
	var k := 1.0 - exp(-14.0 * delta)
	var old := global_position
	global_position = global_position.lerp(target_pos, k)
	rotation.y = lerp_angle(rotation.y, target_yaw, k)
	var sp := Vector2(global_position.x - old.x, global_position.z - old.z).length() / maxf(delta, 0.001)
	animate(delta, sp)
