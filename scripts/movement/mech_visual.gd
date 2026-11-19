class_name MechVisual
extends Node3D
## Placeholder procedural mech body + procedural ACTION layer (grey-box art,
## to be replaced in phase 7). Purely a READER of motor / combat state:
## it poses a simple rig (hips, legs, torso, arms, lance, mirror shield) from
## the current attack phase and progress, hit reactions and movement. It owns
## no gameplay state and can never block control.
##
## Rig:  _body (lean / recoil)
##        ├─ legs (pivots at the hips)
##        └─ _torso (twist / pitch / crouch)
##             ├─ head, visor, backpack, thrusters, crown, wings
##             ├─ _arm_r (shoulder pivot) → _lance_pivot → lance (+ tip)
##             └─ _arm_l (shoulder pivot) → shield plate

var motor: MechMotor
var combat: CombatStateMachine
var style: StringName = &"generic"

var _body: Node3D
var _torso: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _lance_pivot: Node3D
var _lance: MeshInstance3D
var _lance_tip: Node3D
var _lance_base: Node3D
var _shield: MeshInstance3D
var _thrusters: Array[MeshInstance3D] = []
var _thruster_mat: StandardMaterial3D
var _armor_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _lance_mat: StandardMaterial3D
var _shield_mat: StandardMaterial3D
var _materials: Array[StandardMaterial3D] = []
var _crown: Array[MeshInstance3D] = []
var _crown_missing: MeshInstance3D
var _wings: Array[MeshInstance3D] = []
var _trail: WeaponTrail

var _prev_h := Vector3.ZERO
var _lean := Vector2.ZERO
var _fade := 1.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _telegraph := 0.0
var _ult_phase := "LOCKED"
var _dead := false
var _walk_phase := 0.0
## Hit recoil spring (pitch, roll) and its velocity.
var _recoil := Vector2.ZERO
var _recoil_v := Vector2.ZERO
var _parry_flash := 0.0
## Smoothed pose (applied each frame).
var _pose := {}
var _recoil_fire := 0.0


func setup(p_motor: MechMotor, color: Color, p_style: StringName = &"generic") -> void:
	motor = p_motor
	style = p_style
	combat = motor.get_node_or_null(^"CombatStateMachine") as CombatStateMachine
	_armor_mat = _mat(color, 0.55, 0.3)
	var dark := _mat(Color(0.15, 0.15, 0.17), 0.7, 0.2)
	_thruster_mat = _emissive(Color(0.4, 0.8, 1.0), 0.0)
	_glow_mat = _emissive(Color(1.0, 0.93, 0.72), 1.5)
	_lance_mat = _emissive(Color(0.85, 0.95, 1.0), 1.2)
	_shield_mat = _mat(color.lightened(0.25), 0.25, 0.8)
	_shield_mat.emission_enabled = true
	_shield_mat.emission = Color(0.7, 0.9, 1.0)
	_shield_mat.emission_energy_multiplier = 0.0

	_body = _pivot(self, Vector3.ZERO)
	_leg_l = _pivot(_body, Vector3(-0.5, 1.8, 0))
	_box(_leg_l, Vector3(0.7, 1.8, 0.8), Vector3(0, -0.9, 0), dark)
	_leg_r = _pivot(_body, Vector3(0.5, 1.8, 0))
	_box(_leg_r, Vector3(0.7, 1.8, 0.8), Vector3(0, -0.9, 0), dark)
	_torso = _pivot(_body, Vector3(0, 1.8, 0))
	_box(_torso, Vector3(1.9, 1.4, 1.2), Vector3(0, 0.7, 0), _armor_mat)
	_box(_torso, Vector3(0.7, 0.55, 0.75), Vector3(0, 1.7, -0.1), _armor_mat)
	_box(_torso, Vector3(0.5, 0.18, 0.1), Vector3(0, 1.75, -0.5), _thruster_mat)
	_box(_torso, Vector3(1.4, 1.0, 0.5), Vector3(0, 0.9, 0.8), dark)
	for x in [-0.45, 0.45]:
		_thrusters.append(_box(_torso, Vector3(0.35, 0.8, 0.35), Vector3(x, 0.2, 1.05), _thruster_mat))
	_arm_r = _pivot(_torso, Vector3(1.25, 1.2, 0))
	_box(_arm_r, Vector3(0.55, 1.4, 0.55), Vector3(0, -0.6, 0), _armor_mat)
	_arm_l = _pivot(_torso, Vector3(-1.25, 1.2, 0))
	_box(_arm_l, Vector3(0.55, 1.4, 0.55), Vector3(0, -0.6, 0), _armor_mat)
	_lance_pivot = _pivot(_arm_r, Vector3(0, -1.25, 0))
	if style == &"seraph":
		# light lance: shaft continues the line of the hand (local -Y)
		_lance = _box(_lance_pivot, Vector3(0.13, 3.8, 0.13), Vector3(0, -1.5, 0), _lance_mat)
		_box(_lance_pivot, Vector3(0.32, 0.9, 0.08), Vector3(0, -3.6, 0), _glow_mat)
		_lance_tip = _pivot(_lance_pivot, Vector3(0, -4.0, 0))
		_lance_base = _pivot(_lance_pivot, Vector3(0, -1.0, 0))
		# refracting mirror shield on the left forearm
		_shield = _box(_arm_l, Vector3(0.14, 1.7, 1.3), Vector3(-0.3, -0.9, -0.1), _shield_mat)
		_build_seraph()
	else:
		# generic / ranged frame: forearm cannon
		_lance = _box(_lance_pivot, Vector3(0.35, 1.8, 0.35), Vector3(0, -0.6, 0), dark)
		_lance_tip = _pivot(_lance_pivot, Vector3(0, -1.5, 0))
		_lance_base = _pivot(_lance_pivot, Vector3(0, 0, 0))
	_trail = WeaponTrail.new()
	_trail.name = "WeaponTrail"
	add_child(_trail)
	if combat:
		CombatEvents.telegraph.connect(_on_telegraph)
		CombatEvents.hit_resolved.connect(_on_hit)
		CombatEvents.ultimate_phase.connect(_on_ult_phase)
		CombatEvents.mech_died.connect(_on_died)
		CombatEvents.parried.connect(_on_parried)
		CombatEvents.attack_active.connect(_on_attack_active)


## PALE SERAPH story read: an INCOMPLETE crown (3 of 4 arcs) above the head
## and folded light-wing plates. The ultimate completes the crown and unfolds
## the wings.
func _build_seraph() -> void:
	for i in 4:
		var a := TAU * i / 4.0
		var seg := _box(_torso, Vector3(0.5, 0.12, 0.12), Vector3(cos(a) * 0.5, 2.25, sin(a) * 0.5), _glow_mat)
		seg.rotation.y = -a + PI * 0.5
		if i == 3:
			_crown_missing = seg
			seg.visible = false
		else:
			_crown.append(seg)
	for side in [-1.0, 1.0]:
		var w := _box(_torso, Vector3(0.12, 1.6, 0.9), Vector3(side * 0.85, 1.2, 0.9), _glow_mat)
		w.rotation.z = side * 0.25
		_wings.append(w)


# ------------------------------------------------------------------ events

func _on_telegraph(attacker: Node3D, _attack: AttackDefinition, duration: float) -> void:
	if attacker == motor:
		_telegraph = maxf(duration, 0.2)


func _on_attack_active(attacker: Node3D, attack: AttackDefinition) -> void:
	if attacker == motor and attack.attack_type == CombatTypes.AttackType.MELEE and _lance_tip:
		_trail.start(attack.recovery * 0.4 + attack.active + 0.05)
	elif attacker == motor and attack.attack_type == CombatTypes.AttackType.PROJECTILE:
		_recoil_fire = 1.0


func _on_hit(hit: HitInfo) -> void:
	if hit.victim != motor:
		return
	var away := motor.global_basis.inverse() * hit.direction
	var strength := clampf(hit.attack.knockback / 10.0, 0.2, 1.4)
	match hit.result:
		CombatTypes.HitResult.HIT:
			flash(Color(1.0, 0.35, 0.2), 0.14)
			_kick(away, strength)
		CombatTypes.HitResult.GUARDED:
			flash(Color(0.5, 0.75, 1.0), 0.08)
			_kick(away, strength * 0.35)
		CombatTypes.HitResult.GUARD_BREAK:
			flash(Color(1.0, 0.6, 0.1), 0.22)
			_kick(away, strength * 1.3)
		CombatTypes.HitResult.PARRIED, CombatTypes.HitResult.DEFLECTED, CombatTypes.HitResult.REFLECTED:
			flash(Color(1.0, 1.0, 1.0), 0.15)


func _on_parried(defender: Node3D, _attacker: Node3D, _proj: bool) -> void:
	if defender == motor:
		_parry_flash = 0.35


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


## Recoil spring kick: `dir_local` is the hit direction in mech space.
func _kick(dir_local: Vector3, strength: float) -> void:
	# +rotation.x leans the top backwards (+Z), +rotation.z leans it left (-X):
	# lean away from the blow
	var d := Vector2(dir_local.z, -dir_local.x)
	if d.length() < 0.1:
		d = Vector2(1.0, 0.0)
	_recoil_v += d.normalized() * 9.0 * strength


func flash(c: Color, t: float) -> void:
	_flash = t
	_flash_color = c


func get_lance_tip() -> Vector3:
	return _lance_tip.global_position if _lance_tip else global_position


# ------------------------------------------------------------------ helpers

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


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


# ------------------------------------------------------------------ poses
# Pose keys (radians / metres): ty torso yaw, tp torso pitch, cr crouch,
# rx/ry/rz right arm, rp lance pitch, rz_off right shoulder z offset,
# le lance extension (scale), lx/ly/lz left arm, sh shield glow.

const IDLE := {"ty": 0.0, "tp": 0.0, "cr": 0.0, "rx": 0.45, "ry": 0.0, "rz": 0.15, "rp": 1.05, "ro": 0.0, "le": 1.0,
	"lx": 0.35, "ly": 0.0, "lz": -0.15, "sh": 0.0}


func _p(over: Dictionary) -> Dictionary:
	var d := IDLE.duplicate()
	for k in over:
		d[k] = over[k]
	return d


func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var d := {}
	for k in a:
		d[k] = lerpf(a[k], b[k], t)
	return d


static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)


static func _ease_in(t: float) -> float:
	return pow(clampf(t, 0.0, 1.0), 2.0)


## Key poses per attack style: [windup end, active end].
func _attack_keys(id: StringName) -> Array:
	match id:
		&"seraph_l1", &"seraph_judgment_counter":  # thrust
			return [_p({"ty": 0.4, "rx": 0.85, "rp": 0.75, "ro": 0.55, "lx": 0.6}),
				_p({"ty": -0.3, "tp": 0.15, "rx": 1.55, "rp": 0.0, "ro": -0.6, "le": 1.45})]
		&"seraph_l2":  # horizontal sweep right → left
			return [_p({"ty": 0.75, "rx": 1.45, "ry": 1.15, "rp": 0.2, "rz": 0.4}),
				_p({"ty": -0.7, "rx": 1.45, "ry": -1.25, "rp": 0.2, "rz": -0.2, "le": 1.25})]
		&"seraph_l3":  # heavy charged thrust
			return [_p({"ty": 0.55, "tp": -0.25, "cr": 0.35, "rx": 0.55, "rp": 0.9, "ro": 0.85, "lx": 0.9}),
				_p({"ty": -0.4, "tp": 0.35, "cr": 0.15, "rx": 1.6, "rp": 0.0, "ro": -0.9, "le": 1.8})]
		&"seraph_dash_slash":  # low guard → rising slash
			return [_p({"tp": 0.35, "cr": 0.45, "rx": -0.35, "rp": 1.3, "ro": 0.4, "lx": 0.9}),
				_p({"tp": -0.15, "cr": 0.0, "rx": 2.6, "rp": 0.3, "ro": -0.3, "le": 1.35})]
		&"seraph_final_spear":  # raised overhead charge → full lunge
			return [_p({"tp": -0.2, "cr": 0.25, "rx": 2.2, "rp": -0.45, "ro": 0.5, "le": 1.6, "lx": 1.2, "lz": -0.6}),
				_p({"tp": 0.45, "cr": 0.1, "rx": 1.57, "rp": 0.0, "ro": -1.0, "le": 2.3, "lx": -0.4})]
		_:  # projectile / generic: aim forward
			return [_p({"rx": 1.5, "rp": 0.0, "ty": -0.1}), _p({"rx": 1.62, "rp": 0.0})]


func _target_pose() -> Dictionary:
	if combat == null:
		return IDLE
	match combat.state:
		CombatStateMachine.CombatState.ATTACK:
			var a := combat.attack
			if a == null:
				return IDLE
			var keys := _attack_keys(a.id)
			var t := combat.attack_time
			var act := maxf(a.active, a.lunge_duration)
			if t < a.windup:
				var w := _ease_out(t / maxf(a.windup, 0.01))
				var pose := _mix(IDLE, keys[0], w)
				if a.telegraphed:  # charge tremble during telegraphed windups
					pose.ro += sin(Time.get_ticks_msec() * 0.06) * 0.04
				return pose
			if t < a.windup + act:
				# snap into the strike in the first 40 % of the active window
				var s := _ease_out((t - a.windup) / maxf(act * 0.4, 0.01))
				return _mix(keys[0], keys[1], s)
			return _mix(keys[1], IDLE, _ease_in((t - a.windup - act) / maxf(a.recovery, 0.01)))
		CombatStateMachine.CombatState.GUARD:
			return _p({"cr": 0.2, "tp": 0.1, "lx": 1.45, "ly": 0.55, "lz": 0.0, "rx": 0.25, "sh": 0.6})
		CombatStateMachine.CombatState.PARRY:
			if combat.is_parrying():
				return _p({"ty": -0.25, "lx": 1.65, "ly": 0.4, "lz": 0.0, "sh": 2.5})
			return _p({"cr": 0.1, "lx": 0.1, "lz": -0.45, "rx": 0.2, "sh": 0.0})  # whiff: shield dropped
		CombatStateMachine.CombatState.STAGGER:
			return _p({"tp": -0.35, "cr": 0.2, "rx": 0.1, "rp": 0.6, "lx": 0.1, "lz": -0.5})
		CombatStateMachine.CombatState.OFFBALANCE:
			return _p({"tp": -0.6, "cr": 0.1, "rx": -0.6, "rp": 0.3, "lx": -0.6, "lz": -0.7, "ty": 0.3})
		CombatStateMachine.CombatState.ULT_WINDUP:
			return _p({"tp": -0.3, "cr": 0.2, "rx": 2.6, "rp": -0.6, "lx": 2.6, "lz": -0.5, "sh": 1.5})
	return IDLE


func _apply_pose(p: Dictionary) -> void:
	_torso.rotation = Vector3(p.tp, p.ty, 0.0)
	_torso.position = Vector3(0, 1.8 - p.cr, 0)
	_arm_r.rotation = Vector3(p.rx, p.ry, p.rz)
	_arm_r.position = Vector3(1.25, 1.2, p.ro)
	_arm_l.rotation = Vector3(p.lx, p.ly, p.lz)
	_lance_pivot.rotation = Vector3(p.rp, 0.0, 0.0)
	_lance_pivot.scale = Vector3(1.0, p.le, 1.0)
	_shield_mat.emission_energy_multiplier = p.sh + _parry_flash * 10.0


func _process(delta: float) -> void:
	if motor == null:
		return
	_flash = maxf(_flash - delta, 0.0)
	_telegraph = maxf(_telegraph - delta, 0.0)
	_parry_flash = maxf(_parry_flash - delta, 0.0)
	_armor_mat.emission_enabled = _flash > 0.0 or _telegraph > 0.0
	if _flash > 0.0:
		_armor_mat.emission = _flash_color
		_armor_mat.emission_energy_multiplier = 2.5
	elif _telegraph > 0.0:
		# attack telegraph: pulsing warm glow
		_armor_mat.emission = Color(1.0, 0.25, 0.1)
		_armor_mat.emission_energy_multiplier = 1.2 + sin(Time.get_ticks_msec() * 0.03) * 0.8
	_lance_mat.emission_energy_multiplier = 1.2 + (4.0 if combat and combat.state == CombatStateMachine.CombatState.ATTACK else 0.0) \
		+ (3.0 if _telegraph > 0.0 else 0.0)
	_trail.update_trail(delta, _lance_tip.global_position if _lance_tip else Vector3.ZERO,
		_lance_base.global_position if _lance_base else Vector3.ZERO)
	if _dead:
		return
	if motor.in_hitstop():
		return  # freeze the pose during hitstop: it sells the impact

	# --- pose: attack-driven poses are crisp, others ease quickly
	var want := _target_pose()
	var attacking := combat != null and combat.state == CombatStateMachine.CombatState.ATTACK
	if _pose.is_empty():
		_pose = want.duplicate()
	var k := 1.0 if attacking else 1.0 - exp(-14.0 * delta)
	_pose = _mix(_pose, want, k)
	if _recoil_fire > 0.0:
		_recoil_fire = maxf(_recoil_fire - delta * 5.0, 0.0)
		_pose.rx += _recoil_fire * 0.5
	_apply_pose(_pose)

	# --- lean from acceleration + hit recoil spring
	var h := motor.get_horizontal_velocity()
	var accel := (h - _prev_h) / maxf(delta, 0.001)
	_prev_h = h
	var local_acc := motor.global_basis.inverse() * accel
	var target_lean := Vector2(clampf(local_acc.z * 0.004, -0.25, 0.25), clampf(-local_acc.x * 0.004, -0.25, 0.25))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-8.0 * delta))
	_recoil_v += (-_recoil * 140.0 - _recoil_v * 14.0) * delta
	_recoil += _recoil_v * delta
	_recoil = _recoil.clamp(Vector2(-0.7, -0.5), Vector2(0.7, 0.5))
	_body.rotation = Vector3(_lean.x + _recoil.x, 0.0, _lean.y + _recoil.y)

	# --- legs: walk cycle on the ground, tucked in the air
	var spd := h.length()
	if motor.is_grounded_state():
		_walk_phase += delta * (2.0 + spd * 0.55)
		var amp := clampf(spd / 12.0, 0.0, 1.0) * 0.55
		_leg_l.rotation.x = sin(_walk_phase) * amp
		_leg_r.rotation.x = -sin(_walk_phase) * amp
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.45, 1.0 - exp(-8.0 * delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.15, 1.0 - exp(-8.0 * delta))

	# --- thrusters
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
	if attacking and combat.attack and combat.attack.lunge_speed > 20.0:
		thrust = 6.0
	_thruster_mat.emission_energy_multiplier = lerpf(_thruster_mat.emission_energy_multiplier, thrust, 1.0 - exp(-12.0 * delta))
