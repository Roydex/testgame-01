class_name JudgmentAura
extends Node3D
## Presentation only (playtest round 2: "变身存在感太低"). While its mech
## is in JUDGMENT: a pulsing golden shell, the suppression field drawn on
## the ground at its real radius, and fading golden afterimages when moving.
## Reads UltimateSystem state; never affects combat.

const GOLD := Color(1.0, 0.85, 0.35)

var motor: MechMotor
var combat: CombatStateMachine
var _on := false
var _t := 0.0
var _ghost_cd := 0.0
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D


func setup(p_motor: MechMotor, p_combat: CombatStateMachine) -> void:
	motor = p_motor
	combat = p_combat
	name = "JudgmentAura"
	_shell_mat = _gold(0.1)
	_shell_mat.emission_energy_multiplier = 1.0
	_shell = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 6.0
	_shell.mesh = sm
	_shell.material_override = _shell_mat
	_shell.position = Vector3.UP * 2.6
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)
	var r := combat.ultimate.definition.field_radius if combat.ultimate else 12.0
	_ring = MeshInstance3D.new()
	_ring.top_level = true
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.25
	tm.outer_radius = r
	tm.rings = 64
	_ring.mesh = tm
	_ring_mat = _gold(0.6)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.04
	disc.mesh = cm
	_disc_mat = _gold(0.06)
	disc.material_override = _disc_mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(disc)
	_set_on(false)
	CombatEvents.ultimate_phase.connect(_on_phase)


func _gold(a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(GOLD, a)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = GOLD
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _on_phase(mech: Node3D, phase: String) -> void:
	if mech == motor:
		_set_on(phase == "JUDGMENT")


func _set_on(on: bool) -> void:
	_on = on
	_shell.visible = on
	_ring.visible = on


func _process(delta: float) -> void:
	if not _on or motor == null:
		return
	_t += delta
	_shell_mat.albedo_color.a = 0.08 + 0.05 * sin(_t * 7.0)
	_shell.scale = Vector3.ONE * (1.0 + 0.05 * sin(_t * 7.0))
	_ring.global_position = OrbitalStrike.ground_point(motor.get_world_3d(), motor.global_position + Vector3.UP * 1.0) + Vector3.UP * 0.1
	_ring_mat.albedo_color.a = 0.45 + 0.25 * sin(_t * 4.0)
	_ghost_cd -= delta
	if _ghost_cd <= 0.0 and motor.get_horizontal_velocity().length() > 6.0:
		_ghost_cd = 0.06
		_ghost()


## Afterimage: a golden silhouette left behind, fading out.
func _ghost() -> void:
	var g := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.95
	cap.height = 4.6
	g.mesh = cap
	var m := _gold(0.2)
	m.emission_energy_multiplier = 1.2
	g.material_override = m
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.top_level = true
	add_child(g)
	g.global_transform = Transform3D(motor.global_basis, motor.global_position + Vector3.UP * 2.3)
	var tw := g.create_tween().set_parallel(true)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_property(g, "scale", Vector3(1.15, 1.0, 1.15), 0.35)
	tw.chain().tween_callback(g.queue_free)
