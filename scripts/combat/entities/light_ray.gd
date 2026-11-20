class_name LightRay
extends Node3D
## Short-lived visual of an instant light ray (PALE SERAPH mirror
## reflection). Pure presentation: damage is resolved by the caller.

static func flash(parent: Node, a: Vector3, b: Vector3, color: Color, width: float = 0.14, life: float = 0.25) -> LightRay:
	var r := LightRay.new()
	parent.add_child(r)
	r._build(a, b, color, width, life)
	return r


func _build(a: Vector3, b: Vector3, color: Color, width: float, life: float) -> void:
	name = "LightRay"
	var length := a.distance_to(b)
	if length < 0.05:
		queue_free()
		return
	var dir := (b - a) / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI * 0.5), (a + b) * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = width
	cm.bottom_radius = width
	cm.height = length
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(queue_free)
