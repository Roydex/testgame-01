class_name WeaponTrail
extends MeshInstance3D
## Ribbon between the lance base and tip over the last few frames of a
## swing. Purely visual; driven by MechVisual.

const MAX_SAMPLES := 14
const SAMPLE_LIFE := 0.16

## Ribbon colour and sample life (the shield trail changes them per parry).
var color := Color(0.75, 0.9, 1.0)
var life := SAMPLE_LIFE
var max_samples := MAX_SAMPLES
## Alpha at the base edge (the tip edge is 0.85).
var base_alpha := 0.15

var _samples: Array = []  # [tip, base, age]
var _emit_left := 0.0
var _mesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Opaque-ish ribbon (alpha blend instead of additive): reads on bright
## ground too. Used by the shield-edge trail.
func use_mix_blend() -> void:
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX


func sample_count() -> int:
	return _samples.size()


## Emit samples for `duration` seconds.
func start(duration: float) -> void:
	_emit_left = duration


func update_trail(delta: float, tip: Vector3, base: Vector3) -> void:
	for s in _samples:
		s[2] += delta
	while not _samples.is_empty() and _samples[0][2] > life:
		_samples.pop_front()
	if _emit_left > 0.0:
		_emit_left -= delta
		_samples.append([tip, base, 0.0])
		if _samples.size() > max_samples:
			_samples.pop_front()
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var a := clampf(1.0 - s[2] / life, 0.0, 1.0)
		_mesh.surface_set_color(Color(color, a * 0.85))
		_mesh.surface_add_vertex(s[0])
		_mesh.surface_set_color(Color(color, a * base_alpha))
		_mesh.surface_add_vertex(s[1])
	_mesh.surface_end()
