extends RefCounted
## Level 1's weapons, built from simple shapes: the axe, the saw (a throwing disc),
## the crossbow, and the rope launcher. Each model is about hand-sized, with its grip
## at the origin and pointing up (+Y), so it can sit in a hand or float over a step.

static var _mats := {}


static func _m(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"wood":
			m.albedo_color = Color(0.42, 0.28, 0.17)
			m.roughness = 0.8
		"steel":
			m.albedo_color = Color(0.78, 0.8, 0.84)
			m.metallic = 0.9
			m.roughness = 0.25
		"edge":
			m.albedo_color = Color(1.0, 0.85, 0.55)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.65, 0.25)
			m.emission_energy_multiplier = 2.5
		"saw":
			m.albedo_color = Color(0.85, 0.87, 0.9)
			m.metallic = 0.95
			m.roughness = 0.2
			m.emission_enabled = true
			m.emission = Color(0.4, 0.8, 1.0)
			m.emission_energy_multiplier = 0.6
		"rope":
			m.albedo_color = Color(0.75, 0.62, 0.42)
			m.roughness = 0.9
		"gold":
			m.albedo_color = Color(1.0, 0.8, 0.4)
			m.metallic = 0.8
			m.roughness = 0.3
			m.emission_enabled = true
			m.emission = Color(1.0, 0.7, 0.3)
			m.emission_energy_multiplier = 1.2
	_mats[key] = m
	return m


static func _add(parent: Node3D, mesh: Mesh, mat: String, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _m(mat)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _cyl(r: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	return c


static func make(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	match kind:
		"axe":
			_add(n, _cyl(0.03, 0.75), "wood", Vector3(0, 0.3, 0))
			_add(n, _box(0.26, 0.2, 0.035), "steel", Vector3(0.12, 0.6, 0))
			_add(n, _box(0.05, 0.26, 0.04), "edge", Vector3(0.26, 0.6, 0))
			_add(n, _box(0.08, 0.1, 0.05), "steel", Vector3(-0.06, 0.6, 0))
		"saw":
			var disc := _cyl(0.24, 0.025, 20)
			_add(n, disc, "saw", Vector3(0, 0.3, 0), Vector3(PI / 2.0, 0, 0))
			var teeth := TorusMesh.new()
			teeth.inner_radius = 0.22
			teeth.outer_radius = 0.28
			teeth.rings = 16
			teeth.ring_segments = 3
			_add(n, teeth, "edge", Vector3(0, 0.3, 0), Vector3(PI / 2.0, 0, 0))
			_add(n, _cyl(0.05, 0.05), "gold", Vector3(0, 0.3, 0), Vector3(PI / 2.0, 0, 0))
		"bow":
			_add(n, _box(0.06, 0.06, 0.62), "wood", Vector3(0, 0.12, -0.16))
			_add(n, _box(0.05, 0.05, 0.12), "wood", Vector3(0, 0.02, 0.05))
			for s in [-1.0, 1.0]:
				_add(n, _box(0.3, 0.035, 0.035), "steel", Vector3(0.14 * s, 0.14, -0.42), Vector3(0, -0.45 * s, 0))
			_add(n, _box(0.56, 0.008, 0.008), "rope", Vector3(0, 0.14, -0.3))
			_add(n, _box(0.015, 0.015, 0.5), "edge", Vector3(0, 0.17, -0.22))
		"rope":
			var coil := TorusMesh.new()
			coil.inner_radius = 0.14
			coil.outer_radius = 0.24
			coil.rings = 16
			coil.ring_segments = 8
			_add(n, coil, "rope", Vector3(0, 0.12, 0), Vector3(PI / 2.0, 0, 0))
			_add(n, _box(0.07, 0.07, 0.36), "steel", Vector3(0, 0.12, -0.18))
			_add(n, _cyl(0.02, 0.22), "gold", Vector3(0, 0.12, -0.42), Vector3(PI / 2.0, 0, 0))
			for s in [-1.0, 1.0]:
				_add(n, _box(0.12, 0.025, 0.025), "gold", Vector3(0.05 * s, 0.12, -0.52), Vector3(0, 0.6 * s, 0))
	return n
