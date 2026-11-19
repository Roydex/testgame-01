class_name Projectile
extends Node3D
## Combat projectile. Swept with a ray each tick against world geometry and
## hurtboxes (no tunnelling). Damage goes through DamageSystem; allies are
## passed through (TeamRules.can_damage). A parry reflects it: ownership
## moves to the parrier, so the same permission rules apply afterwards
## (FFA: may hit a third party on the way; allies are never hit).

var owner_mech: Node3D
## Who fired it originally — reflected shots fly back toward them.
var original_shooter: Node3D
var attack: AttackDefinition
var velocity: Vector3
var damage_mult: float = 1.0
var homing_deg: float = 0.0
var homing_target: Node3D
var reflected: bool = false
var travelled: float = 0.0
var _mesh_mat: StandardMaterial3D
var _excluded: Array[RID] = []


func launch(p_owner: Node3D, def: AttackDefinition, vel: Vector3, dmg_mult: float = 1.0) -> void:
	owner_mech = p_owner
	original_shooter = p_owner
	attack = def
	velocity = vel
	damage_mult = dmg_mult
	add_to_group(&"projectiles")
	_rebuild_exclusions()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = def.projectile_radius
	sm.height = def.projectile_radius * 2.0
	mi.mesh = sm
	_mesh_mat = StandardMaterial3D.new()
	_mesh_mat.albedo_color = Color(1.0, 0.45, 0.15)
	_mesh_mat.emission_enabled = true
	_mesh_mat.emission = Color(1.0, 0.4, 0.1)
	_mesh_mat.emission_energy_multiplier = 4.0
	mi.material_override = _mesh_mat
	add_child(mi)


func _rebuild_exclusions() -> void:
	_excluded.clear()
	var hb := owner_mech.get_node_or_null(^"Hurtbox") as Area3D if owner_mech else null
	if hb:
		_excluded.append(hb.get_rid())
	if owner_mech is CollisionObject3D:
		_excluded.append((owner_mech as CollisionObject3D).get_rid())


## Mirror-shield refraction: reverse toward the original shooter, transfer
## ownership, scale damage / speed, optional limited horizontal homing.
func reflect(new_owner: Node3D, dmg_mult: float, speed_mult: float, homing: float) -> void:
	var target := original_shooter
	owner_mech = new_owner
	reflected = true
	damage_mult *= dmg_mult
	homing_deg = homing
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


func _physics_process(delta: float) -> void:
	if homing_target and is_instance_valid(homing_target) and homing_deg > 0.0:
		var to := (homing_target.global_position + Vector3.UP * 2.2) - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var vflat := Vector3(velocity.x, 0.0, velocity.z)
		if flat.length() > 0.5 and vflat.length() > 0.1:
			var ang := vflat.signed_angle_to(flat, Vector3.UP)
			var mx := deg_to_rad(homing_deg) * delta
			velocity = velocity.rotated(Vector3.UP, clampf(ang, -mx, mx))
	var from := global_position
	var to_pos := from + velocity * delta
	var space := get_world_3d().direct_space_state
	for attempt in 4:
		var q := PhysicsRayQueryParameters3D.create(from, to_pos, 1 | CombatTypes.HURTBOX_LAYER)
		q.collide_with_areas = true
		q.exclude = _excluded
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var hb := hit.collider as Hurtbox
		if hb == null:
			if hit.collider is MechMotor:
				_excluded.append((hit.collider as CollisionObject3D).get_rid())  # body: hurtbox decides
				continue
			queue_free()  # world geometry
			return
		if not TeamRules.can_damage(owner_mech, hb.mech):
			_excluded.append(hb.get_rid())  # ally / dead: pass through
			continue
		var info := HitInfo.new()
		info.attacker = owner_mech
		info.victim = hb.mech
		info.attack = attack
		info.projectile = self
		info.source_position = global_position
		info.hit_position = hit.position
		info.direction = velocity.normalized()
		info.damage_mult = damage_mult
		if DamageSystem.resolve(info) == CombatTypes.HitResult.REFLECTED:
			return  # direction already reversed by reflect()
		queue_free()
		return
	global_position = to_pos
	travelled += velocity.length() * delta
	if travelled > attack.projectile_range:
		queue_free()
