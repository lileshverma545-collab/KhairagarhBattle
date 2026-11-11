extends RefCounted
## Tiny helpers to build low-poly vertex-coloured geometry into one SurfaceTool (1 draw call for the whole map)

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(p)

static func quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, col: Color) -> void:
	_v(st, p0, n, col)
	_v(st, p1, n, col)
	_v(st, p2, n, col)
	_v(st, p0, n, col)
	_v(st, p2, n, col)
	_v(st, p3, n, col)

static func add_box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var x0 := c.x - h.x
	var x1 := c.x + h.x
	var y0 := c.y - h.y
	var y1 := c.y + h.y
	var z0 := c.z - h.z
	var z1 := c.z + h.z
	var side := col.darkened(0.10)
	var side2 := col.darkened(0.22)
	quad(st, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, col)
	quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, side)
	quad(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.FORWARD, side)
	quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3.RIGHT, side2)
	quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, side2)

static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(((a + b + c) / 3.0) - inside) < 0.0:
		n = -n
	_v(st, a, n, col)
	_v(st, b, n, col)
	_v(st, c, n, col)

## Square pyramid. base_c = centre of the base (y = base height)
static func add_pyr(st: SurfaceTool, base_c: Vector3, size: Vector2, height: float, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var a := base_c + Vector3(-hx, 0, -hz)
	var b := base_c + Vector3(hx, 0, -hz)
	var c := base_c + Vector3(hx, 0, hz)
	var d := base_c + Vector3(-hx, 0, hz)
	var apex := base_c + Vector3(0, height, 0)
	var inside := base_c + Vector3(0, height * 0.3, 0)
	_tri_out(st, a, b, apex, inside, col)
	_tri_out(st, b, c, apex, inside, col.darkened(0.1))
	_tri_out(st, c, d, apex, inside, col)
	_tri_out(st, d, a, apex, inside, col.darkened(0.1))

## Cylinder, c = centre
static func add_cyl(st: SurfaceTool, c: Vector3, r: float, h: float, col: Color, seg: int = 12) -> void:
	var y0 := c.y - h * 0.5
	var y1 := c.y + h * 0.5
	for i in range(seg):
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := Vector3(c.x + cos(a0) * r, 0, c.z + sin(a0) * r)
		var p1 := Vector3(c.x + cos(a1) * r, 0, c.z + sin(a1) * r)
		var nm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		quad(st, Vector3(p0.x, y0, p0.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, y1, p1.z), Vector3(p0.x, y1, p0.z), nm, col.darkened(0.08 * (i % 2)))
		_v(st, Vector3(c.x, y1, c.z), Vector3.UP, col)
		_v(st, Vector3(p0.x, y1, p0.z), Vector3.UP, col)
		_v(st, Vector3(p1.x, y1, p1.z), Vector3.UP, col)
