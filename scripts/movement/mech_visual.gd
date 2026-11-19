class_name MechVisual
extends Node3D
## Placeholder procedural mech body (prototype grey-box art, to be replaced).
## Purely a reader of motor state: leans with acceleration, lights thrusters.
## It owns no gameplay state and cannot block control.

var motor: MechMotor
var _body: Node3D
var _thrusters: Array[MeshInstance3D] = []
var _thruster_mat: StandardMaterial3D
var _armor_mat: StandardMaterial3D
var _prev_h := Vector3.ZERO
var _lean := Vector2.ZERO
var _materials: Array[StandardMaterial3D] = []
var _fade := 1.0


func setup(p_motor: MechMotor, color: Color) -> void:
	motor = p_motor
	_armor_mat = StandardMaterial3D.new()
	_armor_mat.albedo_color = color
	_armor_mat.roughness = 0.55
	_armor_mat.metallic = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.17)
	_thruster_mat = StandardMaterial3D.new()
	_thruster_mat.albedo_color = Color(0.4, 0.8, 1.0)
	_thruster_mat.emission_enabled = true
	_thruster_mat.emission = Color(0.3, 0.7, 1.0)
	_thruster_mat.emission_energy_multiplier = 0.0
	_body = Node3D.new()
	add_child(_body)
	_box(_body, Vector3(0.7, 1.8, 0.8), Vector3(-0.55, 0.9, 0), dark)       # legs
	_box(_body, Vector3(0.7, 1.8, 0.8), Vector3(0.55, 0.9, 0), dark)
	_box(_body, Vector3(1.9, 1.4, 1.2), Vector3(0, 2.5, 0), _armor_mat)      # torso
	_box(_body, Vector3(0.7, 0.55, 0.75), Vector3(0, 3.5, -0.1), _armor_mat) # head
	_box(_body, Vector3(0.5, 0.18, 0.1), Vector3(0, 3.55, -0.5), _thruster_mat) # visor
	_box(_body, Vector3(0.6, 1.5, 0.6), Vector3(-1.3, 2.4, 0), _armor_mat)   # arms
	_box(_body, Vector3(0.6, 1.5, 0.6), Vector3(1.3, 2.4, 0), _armor_mat)
	_box(_body, Vector3(1.4, 1.0, 0.5), Vector3(0, 2.7, 0.8), dark)          # backpack
	for x in [-0.45, 0.45]:
		_thrusters.append(_box(_body, Vector3(0.35, 0.8, 0.35), Vector3(x, 2.0, 1.05), _thruster_mat))


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	if mat is StandardMaterial3D and not _materials.has(mat):
		_materials.append(mat)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Called by CameraRig: 1 = opaque, 0 = invisible. Used when the camera is
## pushed very close to the mech (backed against a wall).
func set_camera_fade(alpha: float) -> void:
	alpha = clampf(alpha, 0.0, 1.0)
	if is_equal_approx(alpha, _fade):
		return
	_fade = alpha
	visible = alpha > 0.05
	for m in _materials:
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if alpha >= 0.99 else BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha


func _process(delta: float) -> void:
	if motor == null:
		return
	var h := motor.get_horizontal_velocity()
	var accel := (h - _prev_h) / maxf(delta, 0.001)
	_prev_h = h
	var local_acc := motor.global_basis.inverse() * accel
	var target_lean := Vector2(clampf(local_acc.z * 0.004, -0.25, 0.25), clampf(-local_acc.x * 0.004, -0.25, 0.25))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-8.0 * delta))
	_body.rotation = Vector3(_lean.x, 0.0, _lean.y)
	var thrust := 0.0
	match motor.state:
		MechMotor.MotionState.AIRBORNE:
			thrust = 3.0 if motor.hover_engaged else 0.5
		MechMotor.MotionState.HOVER:
			thrust = 1.5
		MechMotor.MotionState.AIR_DASH, MechMotor.MotionState.GROUND_DASH:
			thrust = 5.0
		MechMotor.MotionState.TAKEOFF:
			thrust = 2.0
	_thruster_mat.emission_energy_multiplier = lerpf(_thruster_mat.emission_energy_multiplier, thrust, 1.0 - exp(-12.0 * delta))
