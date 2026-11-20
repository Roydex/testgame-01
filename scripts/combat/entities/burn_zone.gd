class_name BurnZone
extends Node3D
## Ground fire left by the AZURE ORACLE heavy orbital strike. Every
## `interval` s each damageable hurtbox inside the circle (and under the open
## sky, like the strike itself) takes one EXPLOSION hit through
## DamageSystem: guardable, no stagger. Leaving the circle stops it.

var owner_mech: Node3D
var attack: AttackDefinition
var radius := 4.0
var duration := 3.0
var interval := 0.5
var _t := 0.0
var _next := 0.0
var _mat: StandardMaterial3D
var _flames: Array[MeshInstance3D] = []


func setup(p_owner: Node3D, def: AttackDefinition, p_radius: float, p_duration: float, p_interval: float) -> void:
	owner_mech = p_owner
	attack = def
	radius = p_radius
	duration = p_duration
	interval = maxf(p_interval, 0.1)
	_next = interval
	name = "BurnZone"
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.35, 0.05, 0.55)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.4, 0.1)
	_mat.emission_energy_multiplier = 3.0
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.1
	disc.mesh = cm
	disc.material_override = _mat
	disc.position = Vector3.UP * 0.08
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.3
	tm.outer_radius = radius
	tm.rings = 48
	edge.mesh = tm
	var em := _mat.duplicate() as StandardMaterial3D
	em.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	em.emission_energy_multiplier = 6.0
	edge.material_override = em
	edge.position = Vector3.UP * 0.15
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge)
	# flickering flame tongues around the rim
	for i in 10:
		var f := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 1.2, 0.25)
		f.mesh = bm
		f.material_override = em
		var a := TAU * i / 10.0
		f.position = Vector3(cos(a) * radius * 0.85, 0.6, sin(a) * radius * 0.85)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		_flames.append(f)
	CombatEvents.entity_spawned.emit(self, &"burn")


func _physics_process(delta: float) -> void:
	_t += delta
	_mat.albedo_color.a = 0.45 + 0.15 * sin(_t * 14.0)
	for i in _flames.size():
		_flames[i].scale.y = 0.6 + 0.5 * absf(sin(_t * 9.0 + i * 1.7))
	if owner_mech == null or not is_instance_valid(owner_mech) or _t >= duration:
		CombatEvents.entity_removed.emit(self, &"burn", false)
		queue_free()
		return
	if _t >= _next:
		_next += interval
		_tick()


func _tick() -> void:
	var world := get_world_3d()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 6.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * 3.0)
	q.collision_mask = CombatTypes.HURTBOX_LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var seen := {}
	for r in world.direct_space_state.intersect_shape(q, 16):
		var hb := r.collider as Hurtbox
		if hb == null or hb.mech == null or seen.has(hb.mech.get_instance_id()):
			continue
		seen[hb.mech.get_instance_id()] = true
		if not TeamRules.can_damage(owner_mech, hb.mech):
			continue
		var p: Vector3 = hb.mech.call(&"get_lock_point") if hb.mech.has_method(&"get_lock_point") else hb.mech.global_position
		if not CombatTypes.has_line_of_sight(world, p, Vector3(p.x, global_position.y + 45.0, p.z)):
			continue  # under a roof: same shelter rule as the strike
		var hit := HitInfo.new()
		hit.attacker = owner_mech
		hit.victim = hb.mech
		hit.attack = attack
		hit.source_entity = self
		hit.source_position = global_position + Vector3.UP * 0.5
		hit.hit_position = p
		hit.direction = (p - global_position).normalized()
		DamageSystem.resolve(hit)
