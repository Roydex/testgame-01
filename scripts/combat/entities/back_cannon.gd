class_name BackCannon
extends Node3D
## VERDANT ARK 移动方舟 back cannon (round 6): a gun pod grown out of the
## shell while the ark is awake. Rides on the mech (no HP of its own, no
## collision), turns at a limited rate onto the nearest hostile mech in
## range with a clear line of sight, and fires the ark's spore shells (owned
## by the ark: TeamRules decides hostility). Removed by the effect.

var owner_mech: MechMotor
var shot: AttackDefinition
var fire_range := 32.0
var interval := 0.6
var turn_deg := 180.0
var target: Node3D
var shots_fired := 0
var _aim := Vector3.FORWARD
var _cool := 0.0
var _retarget := 0.0
var _head: Node3D


func setup(p_owner: MechMotor, p_shot: AttackDefinition, p_range: float, p_interval: float, p_turn: float, offset: Vector3) -> void:
	owner_mech = p_owner
	shot = p_shot
	fire_range = p_range
	interval = p_interval
	turn_deg = p_turn
	name = "BackCannon"
	position = offset
	_aim = p_owner.global_basis * Vector3.FORWARD
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.55, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 1.0, 0.45)
	mat.emission_energy_multiplier = 1.2
	var pod := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	pod.mesh = sm
	pod.material_override = mat
	add_child(pod)
	_head = Node3D.new()
	add_child(_head)
	var barrel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 1.2)
	barrel.mesh = bm
	barrel.material_override = mat
	barrel.position = Vector3(0, 0, -0.7)
	_head.add_child(barrel)
	_cool = interval * 0.5


func _valid(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or not TeamRules.can_damage(owner_mech, t):
		return false
	var p: Vector3 = t.call(&"get_lock_point") if t.has_method(&"get_lock_point") else t.global_position + Vector3.UP * 2.0
	return global_position.distance_to(p) <= fire_range and CombatTypes.has_line_of_sight(get_world_3d(), global_position, p)


func _pick() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for t in TeamRules.get_valid_targets(owner_mech, &"mechs"):
		if not _valid(t):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < bd:
			bd = d
			best = t
	return best


func _physics_process(delta: float) -> void:
	if owner_mech == null or not is_instance_valid(owner_mech) or not TeamRules.is_alive(owner_mech):
		queue_free()
		return
	if owner_mech.in_hitstop():
		return
	_retarget -= delta
	if _retarget <= 0.0 or not _valid(target):
		_retarget = 0.2
		target = _pick()
	_cool -= delta
	if target == null:
		return
	var aim_pt: Vector3 = target.call(&"get_lock_point") if target.has_method(&"get_lock_point") else target.global_position + Vector3.UP * 2.0
	var want := (aim_pt - global_position).normalized()
	var ang := _aim.angle_to(want)
	var mx := deg_to_rad(turn_deg) * delta
	if ang > 0.0001:
		var axis := _aim.cross(want)
		_aim = _aim.rotated(axis.normalized(), minf(ang, mx)).normalized() if axis.length() > 0.0001 else want
	_head.global_basis = Basis.looking_at(_aim, Vector3.UP if absf(_aim.y) < 0.99 else Vector3.RIGHT)
	if _cool <= 0.0 and _aim.angle_to(want) < deg_to_rad(8.0) and shot:
		_cool = interval
		var p := Projectile.new()
		owner_mech.get_parent().add_child(p)
		p.global_position = global_position + _aim * 1.3
		p.launch(owner_mech, shot, _aim * shot.projectile_speed)
		shots_fired += 1
