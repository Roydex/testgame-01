class_name AreaBlast
extends RefCounted
## Radial EXPLOSION. Every damageable hurtbox in the radius with a clear
## line of sight from the centre is resolved through DamageSystem once
## (cover blocks it). Guardable (the blast centre decides the frontal arc),
## never parryable.


static func explode(owner: Node3D, def: AttackDefinition, center: Vector3, radius: float,
		dmg_mult: float = 1.0, skip: Array = []) -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		return out
	var world := owner.get_world_3d()
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = CombatTypes.HURTBOX_LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var seen := {}
	for r in world.direct_space_state.intersect_shape(q, 16):
		var hb := r.collider as Hurtbox
		if hb == null or hb.mech == null or seen.has(hb.mech.get_instance_id()) or hb.mech in skip:
			continue
		seen[hb.mech.get_instance_id()] = true
		if not TeamRules.can_damage(owner, hb.mech):
			continue  # allies, own missiles, the dead
		var aim: Vector3 = hb.mech.call(&"get_lock_point") if hb.mech.has_method(&"get_lock_point") else hb.mech.global_position
		if not CombatTypes.has_line_of_sight(world, center, aim):
			continue  # behind cover
		var hit := HitInfo.new()
		hit.attacker = owner
		hit.victim = hb.mech
		hit.attack = def
		hit.source_position = center
		hit.hit_position = aim
		hit.direction = (aim - center).normalized()
		hit.damage_mult = dmg_mult
		DamageSystem.resolve(hit)
		out.append(hit)
	CombatEvents.area_telegraph.emit(owner, center, radius, 0.0, &"blast")
	return out
