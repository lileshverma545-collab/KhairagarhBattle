extends RefCounted
## KHAIRAGARH map (concept layout, NOT a geographic survey).
## Generated from code, identical on server and client (fixed random seed).
## Coordinates: X = east, Z = south, Y = up. Map size 200 x 200 m.

const HALF := 100.0
const WALLS := [Color(0.93, 0.87, 0.72), Color(0.95, 0.80, 0.50), Color(0.85, 0.62, 0.55), Color(0.70, 0.82, 0.90), Color(0.90, 0.90, 0.85), Color(0.80, 0.75, 0.60), Color(0.60, 0.75, 0.65)]
const ROOFS := [Color(0.70, 0.25, 0.20), Color(0.25, 0.40, 0.75), Color(0.55, 0.35, 0.25), Color(0.50, 0.50, 0.52)]
const BRIGHT := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.7, 0.1), Color(0.2, 0.7, 0.4), Color(0.9, 0.4, 0.7)]
const ROAD := Color(0.20, 0.20, 0.22)

var solids: Array[AABB] = []      # collision / line-of-sight boxes (server + client)
var visuals: Array = []           # drawing commands (client only uses them)
var spawns: Array[Vector3] = []
var reserved: Array[Rect2] = []   # no houses here
var roads: Array[Rect2] = []
var no_tree: Array[Rect2] = []
var landmarks: Dictionary = {}
var rng := RandomNumberGenerator.new()

# ---------- primitives ----------
func box(c: Vector3, s: Vector3, col: Color, solid: bool = true) -> void:
	visuals.append(["box", c, s, col])
	if solid:
		solids.append(AABB(c - s * 0.5, s))

func deco(c: Vector3, s: Vector3, col: Color) -> void:
	box(c, s, col, false)

func pyr(base_c: Vector3, size: Vector2, h: float, col: Color) -> void:
	visuals.append(["pyr", base_c, size, h, col])

func cyl(c: Vector3, r: float, h: float, col: Color, solid: bool = false) -> void:
	visuals.append(["cyl", c, r, h, col])
	if solid:
		solids.append(AABB(c - Vector3(r, h * 0.5, r), Vector3(r * 2.0, h, r * 2.0)))

func _pick(arr: Array) -> Color:
	return arr[rng.randi() % arr.size()]

func road(cx: float, cz: float, w: float, d: float) -> void:
	visuals.append(["box", Vector3(cx, 0.0, cz), Vector3(w, 0.04, d), ROAD])
	var r := Rect2(cx - w * 0.5, cz - d * 0.5, w, d)
	reserved.append(r)
	roads.append(r)
	if w > d:
		var x := cx - w * 0.5 + 3.0
		while x < cx + w * 0.5 - 3.0:
			deco(Vector3(x, 0.025, cz), Vector3(2.2, 0.02, 0.2), Color(0.9, 0.9, 0.85))
			x += 6.0
	else:
		var z := cz - d * 0.5 + 3.0
		while z < cz + d * 0.5 - 3.0:
			deco(Vector3(cx, 0.025, z), Vector3(0.2, 0.02, 2.2), Color(0.9, 0.9, 0.85))
			z += 6.0

func building(cx: float, cz: float, w: float, d: float, h: float, wall: Color, roof: Color, pitched: bool = false) -> void:
	box(Vector3(cx, h * 0.5, cz), Vector3(w, h, d), wall)
	if pitched:
		pyr(Vector3(cx, h, cz), Vector2(w + 0.6, d + 0.6), 1.8, roof)
	else:
		deco(Vector3(cx, h + 0.15, cz), Vector3(w + 0.5, 0.3, d + 0.5), roof)
	var nx: int = maxi(1, int(w / 3.2))
	for i in range(nx):
		var x := cx - w * 0.5 + (float(i) + 0.5) * w / float(nx)
		var y := 1.9
		while y < h - 1.0:
			deco(Vector3(x, y, cz + d * 0.5 + 0.03), Vector3(0.9, 1.2, 0.06), Color(0.22, 0.38, 0.55))
			deco(Vector3(x, y, cz - d * 0.5 - 0.03), Vector3(0.9, 1.2, 0.06), Color(0.22, 0.38, 0.55))
			y += 2.8
	deco(Vector3(cx, 1.1, cz + d * 0.5 + 0.04), Vector3(1.1, 2.2, 0.08), Color(0.35, 0.2, 0.1))

func tree(x: float, z: float) -> void:
	var s := rng.randf_range(0.8, 1.4)
	box(Vector3(x, 1.2 * s, z), Vector3(0.5, 2.4 * s, 0.5), Color(0.42, 0.28, 0.15))
	var g := Color(0.15 + rng.randf() * 0.1, 0.4 + rng.randf() * 0.2, 0.15)
	pyr(Vector3(x, 1.8 * s, z), Vector2(3.0 * s, 3.0 * s), 2.6 * s, g)
	pyr(Vector3(x, 3.2 * s, z), Vector2(2.2 * s, 2.2 * s), 2.2 * s, g.lightened(0.08))

func crate(x: float, z: float, stacked: bool) -> void:
	box(Vector3(x, 0.55, z), Vector3(1.1, 1.1, 1.1), Color(0.6, 0.42, 0.22))
	if stacked:
		box(Vector3(x + 0.1, 1.65, z), Vector3(1.1, 1.1, 1.1), Color(0.55, 0.38, 0.2))

func wall_seg(cx: float, cz: float, w: float, d: float, h: float, col: Color) -> void:
	box(Vector3(cx, h * 0.5, cz), Vector3(w, h, d), col)

# ---------- queries ----------
func _near_solid(x: float, z: float, r: float) -> bool:
	for a in solids:
		if x > a.position.x - r and x < a.end.x + r and z > a.position.z - r and z < a.end.z + r:
			return true
	return false

func _in_rects(rects: Array[Rect2], x: float, z: float, r: float) -> bool:
	for rc in rects:
		if rc.grow(r).has_point(Vector2(x, z)):
			return true
	return false

func _near_spawn(x: float, z: float, r: float) -> bool:
	for s in spawns:
		if absf(s.x - x) < r and absf(s.z - z) < r:
			return true
	return false

# ---------- generate ----------
func generate() -> void:
	rng.seed = 491881
	box(Vector3(0, -0.5, 0), Vector3(HALF * 2.0 + 40.0, 1.0, HALF * 2.0 + 40.0), Color(0.32, 0.52, 0.22), false)
	_spawns()
	_roads()
	_boundary()
	_gol_bazar()
	_bus_stand()
	_campus()
	_arts_college()
	_water_tank()
	_temple()
	_houses()
	_trees()
	_cover()
	_grass()

func _spawns() -> void:
	for p in [Vector2(-20, 2), Vector2(20, -2), Vector2(2, -20), Vector2(-2, 20), Vector2(-20, -32), Vector2(22, -33), Vector2(34, -18), Vector2(34, 18), Vector2(-32, -18), Vector2(-32, 18), Vector2(60, 0), Vector2(-60, 0), Vector2(0, -75), Vector2(0, 75), Vector2(34, 55), Vector2(-20, 34)]:
		spawns.append(Vector3(p.x, 0.0, p.y))

func _roads() -> void:
	road(0, 0, 200, 9)
	road(0, 0, 9, 200)
	road(0, -32, 200, 7)
	road(0, 34, 200, 7)
	road(34, 0, 7, 200)
	road(-32, 0, 6, 200)

func _boundary() -> void:
	var g := Color(0.55, 0.55, 0.52)
	box(Vector3(0, 2, -HALF), Vector3(HALF * 2.0 + 4.0, 4, 2), g)
	box(Vector3(0, 2, HALF), Vector3(HALF * 2.0 + 4.0, 4, 2), g)
	box(Vector3(-HALF, 2, 0), Vector3(2, 4, HALF * 2.0), g)
	box(Vector3(HALF, 2, 0), Vector3(2, 4, HALF * 2.0), g)

func _gol_bazar() -> void:
	landmarks["Gol Bazar"] = Vector3(0, 0, 0)
	reserved.append(Rect2(-30, -30, 60, 60))
	no_tree.append(Rect2(-14, -14, 28, 28))
	cyl(Vector3(0, 0.0, 0), 13.0, 0.04, ROAD)
	cyl(Vector3(0, 0.04, 0), 6.0, 0.08, Color(0.3, 0.55, 0.25))
	box(Vector3(0, 0.4, 0), Vector3(3, 0.8, 3), Color(0.75, 0.7, 0.6))
	box(Vector3(0, 4.3, 0), Vector3(1.2, 7, 1.2), Color(0.85, 0.8, 0.7))
	pyr(Vector3(0, 7.8, 0), Vector2(1.8, 1.8), 1.4, Color(0.95, 0.75, 0.2))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			for i in range(3):
				for j in range(3):
					var cx: float = float(sx) * (10.0 + float(i) * 7.5)
					var cz: float = float(sz) * (10.0 + float(j) * 7.5)
					if Vector2(cx, cz).length() < 15.5 or rng.randf() < 0.12:
						continue
					var h := rng.randf_range(4.0, 8.0)
					building(cx, cz, 5.5, 5.5, h, _pick(WALLS), _pick(ROOFS), rng.randf() < 0.3)
					var dirx: float = -float(sx)
					deco(Vector3(cx + dirx * 3.3, 3.0, cz), Vector3(1.2, 0.12, 4.8), _pick(BRIGHT))

func _bus_stand() -> void:
	landmarks["Bus Stand"] = Vector3(60, 0, 19)
	reserved.append(Rect2(38, 5, 44, 46))
	no_tree.append(Rect2(40, 6, 42, 28))
	deco(Vector3(60, 0.0, 19), Vector3(40, 0.05, 26), Color(0.45, 0.45, 0.47))
	deco(Vector3(60, 4.4, 11), Vector3(30, 0.3, 6.5), Color(0.15, 0.4, 0.8))
	for x in [46.0, 53.0, 60.0, 67.0, 74.0]:
		box(Vector3(x, 2.1, 9.0), Vector3(0.5, 4.2, 0.5), Color(0.8, 0.8, 0.82))
		box(Vector3(x, 2.1, 13.0), Vector3(0.5, 4.2, 0.5), Color(0.8, 0.8, 0.82))
	var bus_cols := [Color(0.15, 0.4, 0.75), Color(0.9, 0.75, 0.15), Color(0.8, 0.2, 0.2), Color(0.2, 0.6, 0.4), Color(0.9, 0.5, 0.15)]
	var bus_pos := [Vector2(46, 22), Vector2(60, 22), Vector2(74, 22), Vector2(52, 28), Vector2(68, 28)]
	for i in range(5):
		var p: Vector2 = bus_pos[i]
		box(Vector3(p.x, 1.5, p.y), Vector3(10, 3.0, 2.6), bus_cols[i])
		deco(Vector3(p.x, 2.1, p.y + 1.32), Vector3(8.4, 0.9, 0.05), Color(0.15, 0.25, 0.4))
		deco(Vector3(p.x, 2.1, p.y - 1.32), Vector3(8.4, 0.9, 0.05), Color(0.15, 0.25, 0.4))
		deco(Vector3(p.x, 3.05, p.y), Vector3(10.1, 0.1, 2.7), Color(0.9, 0.9, 0.9))
	building(60, 44, 20, 8, 6.0, Color(0.9, 0.85, 0.7), Color(0.25, 0.4, 0.75))
	building(41, 12, 4, 4, 3.2, Color(0.85, 0.8, 0.65), Color(0.5, 0.35, 0.25), true)
	building(78, 12, 5, 5, 4.0, Color(0.8, 0.75, 0.7), Color(0.6, 0.3, 0.25), true)
	wall_seg(81, 28, 0.5, 40, 1.4, Color(0.7, 0.7, 0.68))

func _campus() -> void:
	landmarks["Indrakala"] = Vector3(52, 0, -50)
	reserved.append(Rect2(38, -92, 58, 54))
	no_tree.append(Rect2(46, -56, 12, 12))
	# rotunda
	cyl(Vector3(52, 0.06, -50), 6.8, 0.12, Color(0.85, 0.82, 0.75))
	for i in range(8):
		var a := TAU * float(i) / 8.0
		box(Vector3(52.0 + cos(a) * 5.0, 2.2, -50.0 + sin(a) * 5.0), Vector3(0.8, 4.4, 0.8), Color(0.95, 0.93, 0.88))
	cyl(Vector3(52, 4.6, -50), 5.8, 0.4, Color(0.95, 0.93, 0.88))
	pyr(Vector3(52, 4.8, -50), Vector2(11.0, 11.0), 3.2, Color(0.97, 0.97, 0.95))
	box(Vector3(52, 0.6, -50), Vector3(3, 1.2, 3), Color(0.8, 0.75, 0.65))
	box(Vector3(52, 2.7, -50), Vector3(0.9, 3.0, 0.9), Color(0.7, 0.6, 0.4))
	# blocks
	building(70, -78, 28, 10, 9.0, Color(0.95, 0.9, 0.8), Color(0.55, 0.3, 0.25))
	building(45, -80, 10, 10, 6.0, Color(0.9, 0.8, 0.6), Color(0.45, 0.45, 0.5))
	building(82, -55, 12, 14, 10.0, Color(0.85, 0.85, 0.9), Color(0.3, 0.35, 0.6))
	for x in range(58, 84, 6):
		box(Vector3(float(x), 2.0, -71.5), Vector3(0.6, 4.0, 0.6), Color(0.95, 0.93, 0.88))
	# boundary wall with gate
	var wc := Color(0.78, 0.74, 0.65)
	wall_seg(46, -40, 12, 0.4, 1.4, wc)
	wall_seg(75, -40, 30, 0.4, 1.4, wc)
	wall_seg(90, -65, 0.4, 50, 1.4, wc)
	wall_seg(65, -90, 50, 0.4, 1.4, wc)
	wall_seg(40, -65, 0.4, 50, 1.4, wc)

func _arts_college() -> void:
	landmarks["Arts College"] = Vector3(-58, 0, -60)
	reserved.append(Rect2(-92, -82, 66, 48))
	no_tree.append(Rect2(-74, -52, 32, 16))
	building(-58, -62, 40, 10, 9.0, Color(0.93, 0.78, 0.62), Color(0.7, 0.3, 0.25))
	building(-80, -45, 10, 14, 8.0, Color(0.93, 0.78, 0.62), Color(0.7, 0.3, 0.25))
	building(-41, -45, 10, 14, 8.0, Color(0.93, 0.78, 0.62), Color(0.7, 0.3, 0.25))
	for x in range(-72, -44, 6):
		box(Vector3(float(x), 2.0, -55.5), Vector3(0.6, 4.0, 0.6), Color(0.97, 0.95, 0.9))
	deco(Vector3(-60, 0.03, -45), Vector3(30, 0.05, 14), Color(0.38, 0.68, 0.28))
	# mobile tower
	box(Vector3(-88, 1.5, -30), Vector3(2, 3, 2), Color(0.5, 0.5, 0.5))
	deco(Vector3(-88, 0.0, -30), Vector3(0.1, 0.1, 0.1), Color(1, 1, 1))
	pyr(Vector3(-88, 3.0, -30), Vector2(3.0, 3.0), 22.0, Color(0.85, 0.2, 0.15))

func _water_tank() -> void:
	landmarks["Water Tank"] = Vector3(15, 0, -52)
	reserved.append(Rect2(4, -66, 24, 24))
	for dx in [-3.0, 3.0]:
		for dz in [-3.0, 3.0]:
			box(Vector3(15.0 + dx, 7.0, -52.0 + dz), Vector3(0.8, 14, 0.8), Color(0.75, 0.75, 0.72))
	for y in [4.0, 9.0]:
		deco(Vector3(15, y, -55), Vector3(6, 0.3, 0.3), Color(0.6, 0.6, 0.58))
		deco(Vector3(15, y, -49), Vector3(6, 0.3, 0.3), Color(0.6, 0.6, 0.58))
		deco(Vector3(12, y, -52), Vector3(0.3, 0.3, 6), Color(0.6, 0.6, 0.58))
		deco(Vector3(18, y, -52), Vector3(0.3, 0.3, 6), Color(0.6, 0.6, 0.58))
	cyl(Vector3(15, 17, -52), 4.5, 6.0, Color(0.88, 0.9, 0.92), true)
	pyr(Vector3(15, 20, -52), Vector2(9.4, 9.4), 2.5, Color(0.55, 0.6, 0.65))
	building(23, -58, 5, 4, 3.0, Color(0.85, 0.8, 0.7), Color(0.5, 0.35, 0.25), true)

func _temple() -> void:
	landmarks["Khairagarh Temple"] = Vector3(-62, 0, 60)
	reserved.append(Rect2(-86, 38, 50, 48))
	no_tree.append(Rect2(-84, 40, 46, 44))
	var wc := Color(0.92, 0.85, 0.75)
	wall_seg(-83, 62, 0.5, 40, 1.6, wc)
	wall_seg(-42, 62, 0.5, 40, 1.6, wc)
	wall_seg(-63, 82, 40, 0.5, 1.6, wc)
	wall_seg(-72, 42, 20, 0.5, 1.6, wc)
	wall_seg(-52, 42, 20, 0.5, 1.6, wc)
	deco(Vector3(-62, 0.03, 62), Vector3(40, 0.05, 40), Color(0.78, 0.6, 0.5))
	box(Vector3(-62, 0.6, 65), Vector3(14, 1.2, 14), Color(0.92, 0.82, 0.7))
	box(Vector3(-62, 4.7, 65), Vector3(8, 7.0, 8), Color(0.95, 0.75, 0.5))
	pyr(Vector3(-62, 8.2, 65), Vector2(9.0, 9.0), 4.5, Color(0.95, 0.55, 0.2))
	pyr(Vector3(-62, 11.5, 65), Vector2(6.0, 6.0), 3.5, Color(0.97, 0.6, 0.25))
	pyr(Vector3(-62, 14.2, 65), Vector2(3.0, 3.0), 2.5, Color(0.95, 0.75, 0.2))
	deco(Vector3(-62, 17.2, 65), Vector3(0.1, 2.0, 0.1), Color(0.9, 0.2, 0.1))
	deco(Vector3(-62, 1.9, 60.9), Vector3(1.6, 1.4, 0.1), Color(0.35, 0.2, 0.1))
	box(Vector3(-62, 0.2, 55.4), Vector3(5, 0.4, 1.2), Color(0.88, 0.8, 0.7))
	box(Vector3(-62, 0.4, 56.6), Vector3(5, 0.8, 1.2), Color(0.88, 0.8, 0.7))
	for x in [-74.0, -50.0]:
		box(Vector3(x, 1.5, 55), Vector3(4, 3.0, 4), Color(0.95, 0.78, 0.55))
		pyr(Vector3(x, 3.0, 55), Vector2(4.6, 4.6), 2.6, Color(0.95, 0.55, 0.2))
		pyr(Vector3(x, 5.6, 55), Vector2(1.4, 1.4), 1.2, Color(0.95, 0.75, 0.2))

func _houses() -> void:
	var placed := 0
	var tries := 0
	while placed < 42 and tries < 900:
		tries += 1
		var x := rng.randf_range(-90.0, 90.0)
		var z := rng.randf_range(-90.0, 90.0)
		var w := rng.randf_range(5.0, 7.0)
		var d := rng.randf_range(5.0, 7.0)
		if _in_rects(reserved, x, z, 5.0) or _near_solid(x, z, 5.5) or _near_spawn(x, z, 6.0):
			continue
		building(x, z, w, d, rng.randf_range(3.2, 4.6), _pick(WALLS), _pick(ROOFS), rng.randf() < 0.6)
		placed += 1

func _trees() -> void:
	var x := -90.0
	while x < 90.0:
		for z in [-7.0, 7.0]:
			if not _near_solid(x, z, 2.0) and not _in_rects(no_tree, x, z, 0.0):
				tree(x + rng.randf_range(-2, 2), z)
		x += 11.0
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 700:
		tries += 1
		var tx := rng.randf_range(-92.0, 92.0)
		var tz := rng.randf_range(-92.0, 92.0)
		if _in_rects(roads, tx, tz, 2.0) or _in_rects(no_tree, tx, tz, 1.0) or _near_solid(tx, tz, 2.5) or _near_spawn(tx, tz, 4.0):
			continue
		tree(tx, tz)
		placed += 1

func _cover() -> void:
	var placed := 0
	var tries := 0
	while placed < 60 and tries < 900:
		tries += 1
		var x := rng.randf_range(-92.0, 92.0)
		var z := rng.randf_range(-92.0, 92.0)
		if _near_solid(x, z, 2.0) or _near_spawn(x, z, 4.5):
			continue
		var k := rng.randi() % 4
		if k == 0:
			crate(x, z, rng.randf() < 0.4)
			crate(x + 1.3, z + 0.2, false)
		elif k == 1:
			box(Vector3(x, 1.3, z), Vector3(6, 2.6, 2.4), _pick([Color(0.2, 0.4, 0.7), Color(0.7, 0.25, 0.2), Color(0.25, 0.55, 0.35)]))
		elif k == 2:
			box(Vector3(x, 0.5, z), Vector3(3, 1.0, 0.7), Color(0.6, 0.6, 0.6))
		else:
			wall_seg(x, z, 4.0, 0.4, 1.5, Color(0.75, 0.7, 0.62))
		placed += 1

func _grass() -> void:
	var placed := 0
	var tries := 0
	while placed < 350 and tries < 1200:
		tries += 1
		var x := rng.randf_range(-95.0, 95.0)
		var z := rng.randf_range(-95.0, 95.0)
		if _in_rects(roads, x, z, 0.5) or _in_rects(no_tree, x, z, 0.0) or _near_solid(x, z, 0.8):
			continue
		pyr(Vector3(x, 0.0, z), Vector2(0.3, 0.3), rng.randf_range(0.4, 0.8), Color(0.25 + rng.randf() * 0.15, 0.55 + rng.randf() * 0.2, 0.2))
		placed += 1
