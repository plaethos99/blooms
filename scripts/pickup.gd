extends Node3D
## Ember Bloom (heal), Light Shard (small heal, dropped by hollows), a weapon, a
## Sunflare (left by a drop: +2 flares, some light and the first relic), the Sky Fruit
## and Moon Potion (the other two relics), an extinguisher or a Sun Ward.

var kind := "bloom"
var heal := 12.0
var tool_name := ""
var age := 0.0
var lifetime := -1.0
var vis: Node3D
var glow: OmniLight3D
var glow_base := 1.0
var reserved_for = null
var reserved_until := 0


## A reserved pickup (the starter bloom) can only be taken by its owner for a while.
func can_take(s) -> bool:
	return reserved_for == null or reserved_for == s or Time.get_ticks_msec() > reserved_until


func _ready() -> void:
	vis = Node3D.new()
	add_child(vis)
	match kind:
		"bloom":
			_build_bloom()
		"shard":
			_build_shard()
			lifetime = 25.0
		"flare":
			_build_flare()
		"fruit":
			_build_fruit()
		"potion":
			_build_potion()
		"extinguisher":
			_build_extinguisher()
		"ward":
			_build_ward()
		_:
			_build_tool()
	vis.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(vis, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	age += delta
	vis.position.y = 0.12 * sin(age * 2.2)
	vis.rotation.y += delta * (2.5 if kind == "flare" or kind == "ward" else 0.8)
	if glow:
		glow.light_energy = glow_base * (0.85 + 0.15 * sin(age * 3.3))
	if lifetime > 0.0:
		if age > lifetime - 3.0:
			vis.visible = fmod(age, 0.3) < 0.18
		if age > lifetime:
			queue_free()


func _mat(col: Color, emis := Color.BLACK, e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5
	if e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = e
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	vis.add_child(mi)
	return mi


func _light(col: Color, base: float, rng: float, y: float) -> void:
	glow = OmniLight3D.new()
	glow.light_color = col
	glow_base = base
	glow.omni_range = rng
	glow.position = Vector3(0, y, 0)
	vis.add_child(glow)


func _beam(col: Color, h: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.16
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position.y = h * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_bloom() -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = 0.025
	stem.bottom_radius = 0.04
	stem.height = 0.8
	_add(stem, _mat(Color(0.25, 0.5, 0.3)), Vector3(0, 0.4, 0))
	var petal_mat := _mat(Color(1.0, 0.75, 0.85), Color(1.0, 0.45, 0.65), 2.5)
	for i in 6:
		var a := TAU * i / 6.0
		var pm := SphereMesh.new()
		pm.radius = 0.14
		pm.height = 0.07
		var mi := _add(pm, petal_mat, Vector3(cos(a) * 0.15, 0.86, sin(a) * 0.15))
		mi.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
	var core := SphereMesh.new()
	core.radius = 0.09
	core.height = 0.18
	_add(core, _mat(Color(1, 0.9, 0.5), Color(1.0, 0.8, 0.35), 6.0), Vector3(0, 0.9, 0))
	_light(Color(1.0, 0.6, 0.7), 1.6, 4.5, 0.9)
	_beam(Color(1.0, 0.5, 0.7), 18.0)


func _build_shard() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 4
	sm.rings = 2
	var mi := _add(sm, _mat(Color(0.7, 0.95, 1.0), Color(0.55, 0.9, 1.0), 5.0), Vector3(0, 0.6, 0))
	mi.scale = Vector3(0.18, 0.34, 0.18)
	_light(Color(0.55, 0.9, 1.0), 1.0, 3.0, 0.6)
	_beam(Color(0.5, 0.9, 1.0), 7.0)


func _build_tool() -> void:
	var holder := Node3D.new()
	holder.rotation.z = 0.35
	holder.position.y = 0.9
	vis.add_child(holder)
	var staff := CylinderMesh.new()
	staff.top_radius = 0.04
	staff.bottom_radius = 0.05
	staff.height = 1.5
	var s := MeshInstance3D.new()
	s.mesh = staff
	s.material_override = _mat(Color(0.45, 0.32, 0.22))
	holder.add_child(s)
	var head := TorusMesh.new()
	head.inner_radius = 0.1
	head.outer_radius = 0.18
	var h := MeshInstance3D.new()
	h.mesh = head
	h.material_override = _mat(Color(1.0, 0.8, 0.4), Color(1.0, 0.75, 0.35), 3.0)
	h.position.y = 0.8
	h.rotation.x = PI / 2.0
	holder.add_child(h)
	_light(Color(1.0, 0.85, 0.6), 1.2, 4.0, 1.2)
	_beam(Color(1.0, 0.8, 0.35), 14.0)


func _build_flare() -> void:
	var core := SphereMesh.new()
	core.radius = 0.28
	core.height = 0.56
	_add(core, _mat(Color(1.0, 0.95, 0.75), Color(1.0, 0.7, 0.3), 9.0), Vector3(0, 1.0, 0))
	var ray := CylinderMesh.new()
	ray.top_radius = 0.0
	ray.bottom_radius = 0.09
	ray.height = 0.75
	ray.radial_segments = 4
	ray.rings = 1
	var rm := _mat(Color(1.0, 0.6, 0.2), Color(1.0, 0.45, 0.1), 6.0)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector3(cos(a), sin(a) * 0.6, sin(a))
		var mi := _add(ray, rm, Vector3(0, 1.0, 0) + d.normalized() * 0.45)
		var up := Vector3.UP if absf(d.normalized().y) < 0.9 else Vector3.RIGHT
		mi.basis = Basis.looking_at(d.normalized(), up) * Basis(Vector3.RIGHT, -PI / 2.0)
	_light(Color(1.0, 0.55, 0.2), 2.6, 7.0, 1.0)
	_beam(Color(1.0, 0.45, 0.12), 26.0)


func _build_fruit() -> void:
	var skin := _mat(Color(1.0, 0.72, 0.22), Color(1.0, 0.55, 0.12), 3.5)
	skin.roughness = 0.25
	var fm := SphereMesh.new()
	fm.radius = 0.3
	fm.height = 0.56
	_add(fm, skin, Vector3(0, 0.9, 0))
	var stem := CylinderMesh.new()
	stem.top_radius = 0.015
	stem.bottom_radius = 0.025
	stem.height = 0.16
	_add(stem, _mat(Color(0.35, 0.25, 0.15)), Vector3(0, 1.22, 0)).rotation.z = 0.3
	var leaf := SphereMesh.new()
	leaf.radius = 0.13
	leaf.height = 0.04
	for sx in [-1.0, 1.0]:
		var l := _add(leaf, _mat(Color(0.3, 0.65, 0.25)), Vector3(0.1 * sx, 1.24, 0))
		l.scale = Vector3(1.0, 1.0, 0.45)
		l.rotation.z = -0.5 * sx
	_light(Color(1.0, 0.7, 0.3), 2.0, 5.0, 0.9)
	_beam(Color(1.0, 0.75, 0.25), 22.0)


func _build_potion() -> void:
	var glass := _mat(Color(0.75, 0.5, 1.0, 0.55), Color(0.6, 0.3, 1.0), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var body := SphereMesh.new()
	body.radius = 0.24
	body.height = 0.48
	_add(body, glass, Vector3(0, 0.62, 0))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.06
	neck.bottom_radius = 0.08
	neck.height = 0.26
	_add(neck, glass, Vector3(0, 0.93, 0))
	var cork := CylinderMesh.new()
	cork.top_radius = 0.07
	cork.bottom_radius = 0.06
	cork.height = 0.1
	_add(cork, _mat(Color(0.6, 0.45, 0.3)), Vector3(0, 1.1, 0))
	var swirl := SphereMesh.new()
	swirl.radius = 0.15
	swirl.height = 0.3
	_add(swirl, _mat(Color(0.5, 0.95, 1.0), Color(0.4, 0.9, 1.0), 5.0), Vector3(0, 0.6, 0))
	_light(Color(0.65, 0.4, 1.0), 2.2, 5.0, 0.7)
	_beam(Color(0.7, 0.4, 1.0), 20.0)


func _build_extinguisher() -> void:
	var red := _mat(Color(0.85, 0.08, 0.06), Color(0.6, 0.05, 0.03), 0.6)
	red.roughness = 0.3
	red.metallic = 0.3
	var can := CylinderMesh.new()
	can.top_radius = 0.16
	can.bottom_radius = 0.17
	can.height = 0.75
	_add(can, red, Vector3(0, 0.6, 0))
	var cap := SphereMesh.new()
	cap.radius = 0.16
	cap.height = 0.2
	_add(cap, red, Vector3(0, 0.98, 0))
	var black := _mat(Color(0.08, 0.08, 0.08))
	var valve := BoxMesh.new()
	valve.size = Vector3(0.08, 0.14, 0.08)
	_add(valve, black, Vector3(0, 1.1, 0))
	var handle := BoxMesh.new()
	handle.size = Vector3(0.3, 0.04, 0.07)
	_add(handle, black, Vector3(0.08, 1.18, 0)).rotation.z = 0.25
	var hose := CylinderMesh.new()
	hose.top_radius = 0.025
	hose.bottom_radius = 0.025
	hose.height = 0.55
	_add(hose, black, Vector3(0.2, 0.85, 0)).rotation.z = 0.35
	var band := CylinderMesh.new()
	band.top_radius = 0.172
	band.bottom_radius = 0.172
	band.height = 0.12
	_add(band, _mat(Color(0.9, 0.95, 1.0), Color(0.6, 0.85, 1.0), 2.0), Vector3(0, 0.62, 0))
	_light(Color(0.6, 0.85, 1.0), 1.4, 4.0, 0.8)
	_beam(Color(0.55, 0.85, 1.0), 16.0)


func _build_ward() -> void:
	var gold := _mat(Color(1.0, 0.85, 0.45), Color(1.0, 0.8, 0.4), 3.0)
	gold.metallic = 0.8
	gold.roughness = 0.25
	var ring := TorusMesh.new()
	ring.inner_radius = 0.2
	ring.outer_radius = 0.27
	var r := _add(ring, gold, Vector3(0, 1.0, 0))
	r.rotation.x = PI / 2.0
	var core := SphereMesh.new()
	core.radius = 0.12
	core.height = 0.24
	_add(core, _mat(Color(1.0, 1.0, 0.9), Color(1.0, 0.95, 0.75), 7.0), Vector3(0, 1.0, 0))
	var ray := CylinderMesh.new()
	ray.top_radius = 0.0
	ray.bottom_radius = 0.05
	ray.height = 0.22
	ray.radial_segments = 4
	ray.rings = 1
	for i in 10:
		var a := TAU * i / 10.0
		var mi := _add(ray, gold, Vector3(cos(a) * 0.37, 1.0 + sin(a) * 0.37, 0))
		mi.rotation.z = a - PI / 2.0
	_light(Color(1.0, 0.95, 0.75), 1.6, 4.0, 1.0)
	_beam(Color(1.0, 0.95, 0.7), 16.0)
