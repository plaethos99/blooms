extends Node3D
## Ember Bloom (heal), Light Shard (small heal, dropped by hollows) or a tool.

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
		_:
			_build_tool()
	vis.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(vis, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	age += delta
	vis.position.y = 0.12 * sin(age * 2.2)
	vis.rotation.y += delta * 0.8
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
