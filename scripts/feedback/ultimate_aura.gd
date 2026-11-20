class_name UltimateAura
extends Node3D
## Presentation only for the phase-3b ultimates (PALE SERAPH has
## JudgmentAura). HELLFANG 熔炉逆燃: flame pillars during the windup, a
## pulsing heat-wave ring at its real radius while active. AZURE ORACLE
## 终末坐标: a beacon beam into the sky and a golden coordinate grid above
## while active. VERDANT ARK draws its habitat itself (Habitat).

var motor: MechMotor
var combat: CombatStateMachine
var _phase := ""
var _t := 0.0
var _windup_fx: Node3D
var _active_fx: Node3D
var _mats: Array[StandardMaterial3D] = []


func setup(p_motor: MechMotor, p_combat: CombatStateMachine) -> void:
	motor = p_motor
	combat = p_combat
	name = "UltimateAura"
	CombatEvents.ultimate_phase.connect(_on_phase)


func _mat(c: Color, a: float, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, a)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.append(m)
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _on_phase(mech: Node3D, phase: String) -> void:
	if mech != motor:
		return
	_phase = phase
	_clear()
	var eff := combat.ultimate.definition.effect
	if phase == "WINDUP" and eff is BackdraftEffect:
		_windup_fx = Node3D.new()
		add_child(_windup_fx)
		var flame := _mat(Color(1.0, 0.45, 0.1), 0.7, 5.0)
		for x in [-0.55, 0.55]:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.15
			cm.bottom_radius = 0.5
			cm.height = 9.0
			_mesh(_windup_fx, cm, flame, Vector3(x, 8.0, 0.95))
	elif phase == "JUDGMENT" and eff is BackdraftEffect:
		_active_fx = Node3D.new()
		_active_fx.top_level = true
		add_child(_active_fx)
		var r: float = (eff as BackdraftEffect).aura_radius
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.3
		tm.outer_radius = r
		tm.rings = 48
		_mesh(_active_fx, tm, _mat(Color(1.0, 0.35, 0.1), 0.8, 5.0), Vector3.UP * 0.15)
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.05
		_mesh(_active_fx, cm, _mat(Color(1.0, 0.3, 0.05), 0.12), Vector3.UP * 0.08)
		for i in 8:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 2.0, 0.3)
			var a := TAU * i / 8.0
			_mesh(_active_fx, bm, _mat(Color(1.0, 0.5, 0.1), 0.6, 4.0), Vector3(cos(a) * r * 0.9, 1.0, sin(a) * r * 0.9))
	elif phase == "JUDGMENT" and eff is CoordinateEffect:
		_active_fx = Node3D.new()
		_active_fx.top_level = true
		add_child(_active_fx)
		var gold := _mat(Color(1.0, 0.85, 0.35), 0.55, 4.0)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.2
		cm.height = 14.0
		# thin, faint, starting above the head: never blocks the view behind the oracle
		_mesh(_active_fx, cm, _mat(Color(1.0, 0.85, 0.35), 0.3, 3.0), Vector3.UP * 13.0)
		var n := 9
		var span := 48.0
		for i in n:
			var off := -span * 0.5 + span * i / float(n - 1)
			var bx := BoxMesh.new()
			bx.size = Vector3(span, 0.12, 0.12)
			_mesh(_active_fx, bx, gold, Vector3(0.0, 20.0, off))
			var bz := BoxMesh.new()
			bz.size = Vector3(0.12, 0.12, span)
			_mesh(_active_fx, bz, gold, Vector3(off, 20.0, 0.0))


func _clear() -> void:
	for n in [_windup_fx, _active_fx]:
		if n and is_instance_valid(n):
			n.queue_free()
	_windup_fx = null
	_active_fx = null


func _process(delta: float) -> void:
	_t += delta
	if _active_fx and is_instance_valid(_active_fx):
		var g := OrbitalStrike.ground_point(motor.get_world_3d(), motor.global_position + Vector3.UP * 1.0)
		_active_fx.global_position = Vector3(motor.global_position.x, g.y, motor.global_position.z)
		_active_fx.rotation.y += delta * 0.3
	for m in _mats:
		m.emission_energy_multiplier = 3.5 + 1.5 * sin(_t * 8.0)
