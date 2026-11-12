extends Node3D
## A Sunflare drop. A beam and a countdown ring mark where it will land (also shown on
## the map), then a burning star crashes down, blasting anyone standing too close, and
## leaves a Sunflare pickup: +2 flares and some light for whoever grabs it first.

const Cfg = preload("res://scripts/cfg.gd")

var main
var warn: float = Cfg.DROP_WARN
var t := 0.0
var place := ""
var beam_mat: StandardMaterial3D
var ring_mat: StandardMaterial3D
var ring: MeshInstance3D
var label: Label3D
var meteor: Node3D
var _whistled := false


func remaining() -> float:
	return maxf(0.0, warn - t)


func _ready() -> void:
	beam_mat = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.albedo_color = Color(1.0, 0.45, 0.12, 0.2)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.45
	cm.height = 90.0
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.mesh = cm
	beam.material_override = beam_mat
	beam.position.y = 45.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	var tm := TorusMesh.new()
	tm.inner_radius = Cfg.DROP_BLAST - 0.15
	tm.outer_radius = Cfg.DROP_BLAST
	tm.rings = 48
	tm.ring_segments = 4
	ring = MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = ring_mat
	ring.position.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 44
	label.outline_size = 14
	label.modulate = Color(1.0, 0.75, 0.35)
	label.no_depth_test = true
	label.position.y = 2.6
	add_child(label)
	main.sfx.play("drop_warn", global_position + Vector3(0, 3, 0), 4.0)


func _process(delta: float) -> void:
	t += delta
	var r := remaining()
	label.text = "SUNFLARE\n%d" % int(ceil(r))
	var pulse := 0.5 + 0.5 * sin(t * (6.0 + (warn - r) * 2.0))
	ring_mat.albedo_color.a = 0.45 + 0.45 * pulse
	ring.rotation.y += delta * 2.0
	ring.scale = Vector3.ONE * (1.0 + 0.06 * pulse)
	beam_mat.albedo_color.a = 0.12 + 0.18 * pulse
	if r <= 1.0 and meteor == null:
		_launch_meteor(r)
	if r <= 0.0:
		main.on_drop_landed(self)
		queue_free()


func _launch_meteor(dur: float) -> void:
	meteor = Node3D.new()
	add_child(meteor)
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.9, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	m.emission_energy_multiplier = 10.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = m
	meteor.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 6.0
	l.omni_range = 16.0
	meteor.add_child(l)
	var trail := GPUParticles3D.new()
	trail.amount = 60
	trail.lifetime = 0.6
	trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.spread = 180.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 2.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(2.0, 1.2, 0.5, 1.0), Color(1.0, 0.3, 0.1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	trail.process_material = pm
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.25
	pmesh.height = 0.5
	pmesh.radial_segments = 6
	pmesh.rings = 3
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.vertex_color_use_as_albedo = true
	pmesh.material = pmat
	trail.draw_pass_1 = pmesh
	meteor.add_child(trail)
	meteor.position = Vector3(12.0, 75.0, -8.0)
	create_tween().tween_property(meteor, "position", Vector3(0, 0.5, 0), maxf(0.2, dur)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
