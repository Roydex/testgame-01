class_name Projectile
extends Node3D
## Combat projectile. Swept as a sphere of `projectile_radius` each tick
## against world geometry and hurtboxes (no tunnelling, cover blocks it).
## Damage goes through DamageSystem; allies are passed through
## (TeamRules.can_damage). A parry reflects it: ownership moves to the
## parrier, so the same permission rules apply afterwards (FFA: may hit a
## third party on the way; allies are never hit).
##
## Optional behaviour from AttackDefinition.projectile_spec: distance
## falloff, limited homing after an arming distance, a hurtbox so it can be
## shot down (missiles), and an impact splash (EXPLOSION).

var owner_mech: Node3D
## Who fired it originally — reflected shots fly back toward them.
var original_shooter: Node3D
var attack: AttackDefinition
var spec: ProjectileSpec
var velocity: Vector3
var damage_mult: float = 1.0
var homing_deg: float = 0.0
var homing_target: Node3D
## Missiles home in 3D; reflected shots only steer horizontally.
var homing_3d: bool = true
var reflected: bool = false
var travelled: float = 0.0
## Fully charged railgun shot.
var guard_break: bool = false
## Team of the current owner (shoot-down permission for missiles).
var team_id: int = -1
var health: Health
var _mesh_mat: StandardMaterial3D
var _excluded: Array[RID] = []
var _hurtbox: Hurtbox
var _shape: SphereShape3D
var _done := false


func launch(p_owner: Node3D, def: AttackDefinition, vel: Vector3, dmg_mult: float = 1.0) -> void:
	owner_mech = p_owner
	original_shooter = p_owner
	attack = def
	spec = def.projectile_spec
	velocity = vel
	damage_mult = dmg_mult
	team_id = TeamRules.get_team(p_owner)
	add_to_group(&"projectiles")
	_shape = SphereShape3D.new()
	_shape.radius = maxf(def.projectile_radius, 0.05)
	if spec and spec.shootable_hp > 0.0:
		health = Health.new()
		add_child(health)
		health.setup(spec.shootable_hp)
		health.died.connect(_on_shot_down)
		_hurtbox = Hurtbox.new()
		add_child(_hurtbox)
		_hurtbox.setup(self, maxf(def.projectile_radius * 1.6, 0.5), 1.2, 0.0)
	_rebuild_exclusions()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = def.projectile_radius
	sm.height = def.projectile_radius * 2.0
	mi.mesh = sm
	var col := spec.color if spec else Color(1.0, 0.45, 0.15)
	_mesh_mat = StandardMaterial3D.new()
	_mesh_mat.albedo_color = col
	_mesh_mat.emission_enabled = true
	_mesh_mat.emission = col
	_mesh_mat.emission_energy_multiplier = 4.0
	mi.material_override = _mesh_mat
	add_child(mi)


func is_alive() -> bool:
	return not _done and is_inside_tree()


func get_lock_point() -> Vector3:
	return global_position


func _rebuild_exclusions() -> void:
	_excluded.clear()
	var hb := owner_mech.get_node_or_null(^"Hurtbox") as Area3D if owner_mech and is_instance_valid(owner_mech) else null
	if hb:
		_excluded.append(hb.get_rid())
	if owner_mech is CollisionObject3D and is_instance_valid(owner_mech):
		_excluded.append((owner_mech as CollisionObject3D).get_rid())
	if _hurtbox:
		_excluded.append(_hurtbox.get_rid())


## Mirror-shield refraction: reverse toward the original shooter, transfer
## ownership, scale damage / speed, optional limited horizontal homing.
func reflect(new_owner: Node3D, dmg_mult: float, speed_mult: float, homing: float) -> void:
	var target := original_shooter
	owner_mech = new_owner
	team_id = TeamRules.get_team(new_owner)
	reflected = true
	damage_mult *= dmg_mult
	homing_deg = homing
	homing_3d = false
	homing_target = target if homing > 0.0 else null
	var speed := velocity.length() * speed_mult
	var dir := -velocity.normalized()
	if target and is_instance_valid(target):
		dir = ((target.global_position + Vector3.UP * 2.2) - global_position).normalized()
	velocity = dir * speed
	travelled = 0.0
	_rebuild_exclusions()
	if _mesh_mat:
		_mesh_mat.albedo_color = Color(0.8, 0.95, 1.0)
		_mesh_mat.emission = Color(0.7, 0.9, 1.0)


## Mirror-shield GUARD refraction (PALE SERAPH 流光镜盾, round 6): the
## blocked shot is spent, and a weaker copy owned by `new_owner` flies from
## `at` back toward the original shooter (no homing).
static func spawn_refraction(src: Projectile, new_owner: Node3D, dmg_mult: float, at: Vector3) -> Projectile:
	if src == null or new_owner == null or not is_instance_valid(new_owner) or not new_owner.is_inside_tree():
		return null
	var shooter := src.original_shooter
	var speed := maxf(src.velocity.length(), 20.0)
	var dir := -src.velocity.normalized()
	if shooter and is_instance_valid(shooter) and shooter is Node3D:
		var aim: Vector3 = shooter.call(&"get_lock_point") if shooter.has_method(&"get_lock_point") \
			else (shooter as Node3D).global_position + Vector3.UP * 2.2
		if (aim - at).length() > 0.5:
			dir = (aim - at).normalized()
	var p := Projectile.new()
	new_owner.get_parent().add_child(p)
	p.global_position = at
	p.launch(new_owner, src.attack, dir * speed, src.damage_mult * dmg_mult)
	p.original_shooter = shooter
	p.reflected = true
	if p._mesh_mat:
		p._mesh_mat.albedo_color = Color(0.8, 0.95, 1.0)
		p._mesh_mat.emission = Color(0.7, 0.9, 1.0)
	return p


func _armed() -> bool:
	return spec == null or travelled >= spec.arming_distance


func _steer(delta: float) -> void:
	if homing_target == null or not is_instance_valid(homing_target) or homing_deg <= 0.0 or not _armed():
		return
	if not TeamRules.is_alive(homing_target):
		homing_target = null
		return
	var aim: Vector3 = homing_target.call(&"get_lock_point") if homing_target.has_method(&"get_lock_point") \
		else homing_target.global_position + Vector3.UP * 2.2
	var to := aim - global_position
	var mx := deg_to_rad(homing_deg) * delta
	if homing_3d:
		if to.length() < 0.3:
			return
		var ang := velocity.angle_to(to)
		if ang < 0.0001:
			return
		var axis := velocity.cross(to)
		if axis.length() < 0.0001:
			return
		velocity = velocity.rotated(axis.normalized(), minf(ang, mx))
	else:
		var flat := Vector3(to.x, 0.0, to.z)
		var vflat := Vector3(velocity.x, 0.0, velocity.z)
		if flat.length() > 0.5 and vflat.length() > 0.1:
			var a := vflat.signed_angle_to(flat, Vector3.UP)
			velocity = velocity.rotated(Vector3.UP, clampf(a, -mx, mx))


func _physics_process(delta: float) -> void:
	if _done:
		return
	if owner_mech == null or not is_instance_valid(owner_mech):
		_remove(false)  # its shooter is gone (expired turret): the shot fizzles
		return
	_steer(delta)
	var from := global_position
	var motion := velocity * delta
	var space := get_world_3d().direct_space_state
	for attempt in 4:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _shape
		q.transform = Transform3D(Basis(), from)
		q.motion = motion
		q.collision_mask = CombatTypes.WORLD_LAYER | CombatTypes.HURTBOX_LAYER
		q.collide_with_areas = true
		q.exclude = _excluded
		var frac := space.cast_motion(q)
		if frac.is_empty() or frac[1] >= 1.0:
			break
		# contact point: what did we touch?
		var at := from + motion * frac[1]
		q.transform = Transform3D(Basis(), at)
		q.motion = Vector3.ZERO
		var touching := space.intersect_shape(q, 6)
		var hb: Hurtbox = null
		var world := false
		for t in touching:
			var c: Object = t.collider
			if c is Hurtbox:
				if hb == null:
					hb = c as Hurtbox
			elif c is CollisionObject3D and ((c as CollisionObject3D).collision_layer & CombatTypes.WORLD_LAYER) != 0:
				world = true
		if hb == null:
			if world or touching.is_empty():
				_impact(at, null)
				return
			for t in touching:
				_excluded.append((t.collider as CollisionObject3D).get_rid())
			continue
		if hb.mech == null or not TeamRules.can_damage(owner_mech, hb.mech):
			_excluded.append(hb.get_rid())  # ally / dead / own: pass through
			continue
		var info := HitInfo.new()
		info.attacker = owner_mech
		info.victim = hb.mech
		info.attack = attack
		info.projectile = self
		info.source_position = at
		info.hit_position = at
		info.direction = velocity.normalized()
		info.damage_mult = damage_mult * _falloff_mult()
		info.force_guard_break = guard_break
		var res := DamageSystem.resolve(info)
		if res == CombatTypes.HitResult.REFLECTED:
			global_position = at
			return  # direction already reversed by reflect()
		if res == CombatTypes.HitResult.EVADED:
			_excluded.append(hb.get_rid())  # i-frames: it flies on past
			continue
		_impact(at, hb.mech)
		return
	global_position = from + motion
	travelled += motion.length()
	if travelled > _max_range():
		_remove(false)


func _max_range() -> float:
	var r := attack.projectile_range
	if spec and spec.steep_range_mult < 1.0 and not reflected:
		var pitch := rad_to_deg(asin(clampf(velocity.normalized().y, -1.0, 1.0)))
		if pitch > 30.0:
			r *= spec.steep_range_mult
	return r


func _falloff_mult() -> float:
	if spec == null or spec.falloff_end <= spec.falloff_start or reflected:
		return 1.0
	var t := clampf(inverse_lerp(spec.falloff_start, spec.falloff_end, travelled), 0.0, 1.0)
	return lerpf(1.0, spec.falloff_min_mult, t)


func _impact(at: Vector3, direct_victim: Node3D) -> void:
	if spec and spec.splash_radius > 0.0 and spec.splash_attack and _armed():
		AreaBlast.explode(owner_mech, spec.splash_attack, at - velocity.normalized() * 0.3, spec.splash_radius,
			damage_mult, [direct_victim] if direct_victim else [])
	_remove(false)


func _on_shot_down() -> void:
	_remove(true)


func _remove(destroyed: bool) -> void:
	if _done:
		return
	_done = true
	if destroyed:
		CombatEvents.entity_removed.emit(self, &"missile", true)
	queue_free()
