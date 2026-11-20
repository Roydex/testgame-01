class_name PlacementReticle
extends Node3D
## Presentation only: the "ghost" of a hand-marked ground strike (AZURE
## orbital) shown to the aiming player. Cyan while over empty ground, red
## when a hostile mech is inside (the strike will follow it).

var _ring: MeshInstance3D
var _disc: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D
var _radius := -1.0
var _t := 0.0


func _ready() -> void:
	top_level = true
	name = "PlacementReticle"
	_ring_mat = _mat(0.85)
	_disc_mat = _mat(0.18)
	_ring = MeshInstance3D.new()
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_disc = MeshInstance3D.new()
	_disc.material_override = _disc_mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	# vertical beam marker so the point reads from far away
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.06
	bm.bottom_radius = 0.18
	bm.height = 14.0
	beam.mesh = bm
	beam.position = Vector3.UP * 7.0
	beam.material_override = _ring_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	visible = false


func _mat(a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.9, 1.0, a)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.4, 0.9, 1.0)
	m.emission_energy_multiplier = 2.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = 2
	return m


func show_at(p: Vector3, radius: float, on_target: bool) -> void:
	visible = true
	global_position = p + Vector3.UP * 0.08
	if not is_equal_approx(radius, _radius):
		_radius = radius
		var tm := TorusMesh.new()
		tm.inner_radius = radius - 0.22
		tm.outer_radius = radius
		tm.rings = 48
		_ring.mesh = tm
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.04
		_disc.mesh = cm
	var c := Color(1.0, 0.25, 0.2) if on_target else Color(0.4, 0.9, 1.0)
	for m in [_ring_mat, _disc_mat]:
		m.emission = c
		m.albedo_color = Color(c, m.albedo_color.a)


func _process(delta: float) -> void:
	if visible:
		_t += delta
		_disc_mat.albedo_color.a = 0.14 + 0.08 * sin(_t * 8.0)
