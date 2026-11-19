class_name Turret
extends Node3D
## VERDANT ARK 自律炮台. A destructible deployable with its own HP and
## hurtbox. It grows for `arm_time`, then fires at the nearest hostile mech
## in range with a clear line of sight (TeamRules decides hostility). Its
## aim turns at a limited rate, so fast air dashers can outrun it. Expires
## after `lifetime`. Never hard-codes teams or modes.

var owner_mech: Node3D
var team_id: int = -1
var kind: int = DeploySpec.Kind.TURRET
var spec: DeploySpec
var health: Health
var hurtbox: Hurtbox
var age := 0.0
var target: Node3D
var _cool := 0.0
var _retarget := 0.0
var _aim := Vector3.FORWARD
var _head: Node3D
var _gone := false
var _mat: StandardMaterial3D


func setup(p_owner: Node3D, p_spec: DeploySpec) -> void:
	owner_mech = p_owner
	team_id = TeamRules.get_team(p_owner)
	spec = p_spec
	name = "Turret"
	add_to_group(&"deployables")
	add_to_group(&"lock_targets")
	health = Health.new()
	add_child(health)
	health.setup(spec.hp)
	health.died.connect(func(): _remove(true))
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(self, 0.9, 2.4)
	var body := StaticBody3D.new()
	body.collision_layer = 4  # "targets": mechs bump into it, shots use the hurtbox
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 2.0
	cs.shape = cyl
	cs.position = Vector3.UP
	body.add_child(cs)
	add_child(body)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.25, 0.5, 0.28)
	_mat.emission_enabled = true
	_mat.emission = Color(0.4, 1.0, 0.5)
	_mat.emission_energy_multiplier = 0.3
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.55
	bm.bottom_radius = 0.9
	bm.height = 1.6
	base.mesh = bm
	base.material_override = _mat
	base.position = Vector3.UP * 0.8
	add_child(base)
	_head = Node3D.new()
	_head.position = Vector3.UP * 1.9
	add_child(_head)
	var hm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	hm.mesh = sm
	hm.material_override = _mat
	_head.add_child(hm)
	var barrel := MeshInstance3D.new()
	var brm := BoxMesh.new()
	brm.size = Vector3(0.22, 0.22, 1.1)
	barrel.mesh = brm
	barrel.material_override = _mat
	barrel.position = Vector3(0, 0, -0.7)
	_head.add_child(barrel)
	if p_owner:
		_aim = (p_owner as Node3D).global_basis * Vector3.FORWARD
	scale = Vector3.ONE * 0.2
	CombatEvents.area_telegraph.emit(owner_mech, global_position, spec.fire_range, spec.arm_time, &"turret")
	CombatEvents.entity_spawned.emit(self, &"turret")


func is_alive() -> bool:
	return not _gone and health != null and not health.dead and is_inside_tree()


func is_armed() -> bool:
	return age >= spec.arm_time


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * 1.8


func time_left() -> float:
	return maxf(spec.lifetime - age, 0.0)


func _physics_process(delta: float) -> void:
	if _gone:
		return
	age += delta
	scale = Vector3.ONE * lerpf(0.2, 1.0, clampf(age / maxf(spec.arm_time, 0.01), 0.0, 1.0))
	if age >= spec.lifetime:
		_remove(false)
		return
	if owner_mech == null or not is_instance_valid(owner_mech):
		_remove(false)
		return
	if not is_armed():
		return
	_mat.emission_energy_multiplier = 0.6 + 0.8 * clampf(1.0 - time_left() / 4.0, 0.0, 1.0) * (0.5 + 0.5 * sin(age * 12.0))
	_retarget -= delta
	if _retarget <= 0.0 or not _valid(target):
		_retarget = 0.2
		target = _pick()
	if target == null:
		return
	var muzzle := _head.global_position
	var aim_pt: Vector3 = target.call(&"get_lock_point")
	var want := (aim_pt - muzzle).normalized()
	var ang := _aim.angle_to(want)
	var mx := deg_to_rad(spec.turn_rate_deg) * delta
	if ang > 0.0001:
		var axis := _aim.cross(want)
		_aim = _aim.rotated(axis.normalized(), minf(ang, mx)).normalized() if axis.length() > 0.0001 else want
	_head.global_basis = Basis.looking_at(_aim, Vector3.UP if absf(_aim.y) < 0.99 else Vector3.RIGHT)
	_cool -= delta
	if _cool <= 0.0 and _aim.angle_to(want) < deg_to_rad(6.0) and spec.shot:
		_cool = spec.fire_interval
		var p := Projectile.new()
		get_parent().add_child(p)
		p.global_position = muzzle + _aim * 1.2
		p.launch(self, spec.shot, _aim * spec.shot.projectile_speed)


func _valid(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or not TeamRules.can_damage(self, t):
		return false
	var p: Vector3 = t.call(&"get_lock_point")
	return _head.global_position.distance_to(p) <= spec.fire_range \
		and CombatTypes.has_line_of_sight(get_world_3d(), _head.global_position, p)


func _pick() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for t in TeamRules.get_valid_targets(self, &"mechs"):
		if not _valid(t):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < bd:
			bd = d
			best = t
	return best


func _remove(destroyed: bool) -> void:
	if _gone:
		return
	_gone = true
	hurtbox.set_enabled(false)
	CombatEvents.entity_removed.emit(self, &"turret", destroyed)
	queue_free()
