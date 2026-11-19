class_name Deployables
extends RefCounted
## Placement and spawning of deployables (VERDANT ARK turret / restraint
## zone). Placement never goes through cover: the point is pulled back to
## the first wall between the owner and it, then projected to the ground.


static func owned_by(owner: Node, kind: DeploySpec.Kind) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in owner.get_tree().get_nodes_in_group(&"deployables"):
		var d := n as Node3D
		if d and d.get(&"owner_mech") == owner and int(d.get(&"kind")) == kind and d.call(&"is_alive"):
			out.append(d)
	return out


static func placement(combat: CombatStateMachine, spec: DeploySpec) -> Vector3:
	var m := combat.motor
	var eye := m.global_position + Vector3.UP * 2.0
	var at := m.global_position + m.get_forward() * spec.place_distance
	var t := combat.aim_target
	if spec.kind == DeploySpec.Kind.ZONE and t and is_instance_valid(t) and TeamRules.is_alive(t) \
			and m.global_position.distance_to(t.global_position) <= spec.max_place_range:
		at = t.global_position
	var target := at + Vector3.UP * 2.0
	var q := PhysicsRayQueryParameters3D.create(eye, target, CombatTypes.WORLD_LAYER)
	q.exclude = [m.get_rid()]
	var r := m.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		var back: Vector3 = (r.position as Vector3) - (target - eye).normalized() * 1.2
		at = Vector3(back.x, m.global_position.y, back.z)
	return OrbitalStrike.ground_point(m.get_world_3d(), at + Vector3.UP * 3.0)


static func deploy(combat: CombatStateMachine, def: AttackDefinition) -> Node3D:
	var spec := def.deploy_spec
	if spec == null:
		return null
	var at := placement(combat, spec)
	var e: Node3D
	if spec.kind == DeploySpec.Kind.TURRET:
		var t := Turret.new()
		combat.motor.get_parent().add_child(t)
		t.global_position = at
		t.setup(combat.motor, spec)
		e = t
	else:
		var z := SlowZone.new()
		combat.motor.get_parent().add_child(z)
		z.global_position = at
		z.setup(combat.motor, spec)
		e = z
	return e
