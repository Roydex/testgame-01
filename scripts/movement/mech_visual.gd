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


var style: StringName = &"generic"
var _crown: Array[MeshInstance3D] = []
var _crown_missing: MeshInstance3D
var _wings: Array[MeshInstance3D] = []
var _glow_mat: StandardMaterial3D
var _flash := 0.0
var _flash_color := Color.WHITE
var _telegraph := 0.0
var _ult_phase := "LOCKED"
var _dead := false


func setup(p_motor: MechMotor, color: Color, p_style: StringName = &"generic") -> void:
	motor = p_motor
	style = p_style
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
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(1.0, 0.95, 0.8)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.92, 0.7)
	_glow_mat.emission_energy_multiplier = 1.5
	if style == &"seraph":
		_build_seraph()
	if motor and motor.has_node(^"CombatStateMachine"):
		CombatEvents.telegraph.connect(_on_telegraph)
		CombatEvents.hit_resolved.connect(_on_hit)
		CombatEvents.ultimate_phase.connect(_on_ult_phase)
		CombatEvents.mech_died.connect(_on_died)


## PALE SERAPH placeholder story read: an INCOMPLETE crown (3 of 4 arcs)
## above the head and folded light-wing plates. The ultimate completes the
## crown and unfolds the wings.
func _build_seraph() -> void:
	for i in 4:
		var a := TAU * i / 4.0
		var seg := _box(_body, Vector3(0.5, 0.12, 0.12), Vector3(cos(a) * 0.5, 4.05, sin(a) * 0.5), _glow_mat)
		seg.rotation.y = -a + PI * 0.5
		if i == 3:
			_crown_missing = seg
			seg.visible = false
		else:
			_crown.append(seg)
	for side in [-1.0, 1.0]:
		var w := _box(_body, Vector3(0.12, 1.6, 0.9), Vector3(side * 0.85, 3.0, 0.9), _glow_mat)
		w.rotation.z = side * 0.25
		_wings.append(w)


func _on_telegraph(attacker: Node3D, _attack: AttackDefinition, duration: float) -> void:
	if attacker == motor:
		_telegraph = maxf(duration, 0.2)


func _on_hit(hit: HitInfo) -> void:
	if hit.victim == motor:
		match hit.result:
			CombatTypes.HitResult.HIT:
				flash(Color(1.0, 0.3, 0.2), 0.12)
			CombatTypes.HitResult.GUARDED:
				flash(Color(0.5, 0.7, 1.0), 0.08)
			CombatTypes.HitResult.GUARD_BREAK:
				flash(Color(1.0, 0.6, 0.1), 0.2)
			CombatTypes.HitResult.PARRIED, CombatTypes.HitResult.DEFLECTED, CombatTypes.HitResult.REFLECTED:
				flash(Color(1.0, 1.0, 1.0), 0.15)


func _on_ult_phase(mech: Node3D, phase: String) -> void:
	if mech != motor:
		return
	_ult_phase = phase
	if _crown_missing:
		_crown_missing.visible = phase == "WINDUP" or phase == "JUDGMENT"
	for w in _wings:
		var open := phase == "JUDGMENT" or phase == "WINDUP"
		w.scale = Vector3(1, 1.8, 2.2) if open else Vector3.ONE
	_glow_mat.emission_energy_multiplier = 6.0 if phase == "JUDGMENT" else (0.3 if phase == "OVERLOAD" else 1.5)
	_glow_mat.emission = Color(1.0, 0.95, 0.75) if phase != "OVERLOAD" else Color(0.9, 0.3, 0.2)


func _on_died(mech: Node3D) -> void:
	if mech == motor:
		_dead = true
		_armor_mat.albedo_color = _armor_mat.albedo_color.darkened(0.6)
		_body.rotation = Vector3(0.0, 0.0, 1.2)


func flash(c: Color, t: float) -> void:
	_flash = t
	_flash_color = c


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
	_flash = maxf(_flash - delta, 0.0)
	_telegraph = maxf(_telegraph - delta, 0.0)
	_armor_mat.emission_enabled = _flash > 0.0 or _telegraph > 0.0
	if _flash > 0.0:
		_armor_mat.emission = _flash_color
		_armor_mat.emission_energy_multiplier = 2.5
	elif _telegraph > 0.0:
		# attack telegraph: pulsing warm glow
		_armor_mat.emission = Color(1.0, 0.25, 0.1)
		_armor_mat.emission_energy_multiplier = 1.2 + sin(Time.get_ticks_msec() * 0.03) * 0.8
	if _dead or motor.in_hitstop():
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
