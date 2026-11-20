class_name SweepBeam
extends Node3D
## AZURE ORACLE 轨道扫射 (round 6, user direction "扫射型激光"). After a
## short landing warning (fixed red circle) an orbital beam stands on the
## ground and slides toward the caster's aim point at a capped speed: the
## hand-steered placement point for a player, the lock target for scripts.
## Every tick it hits each damageable under it and under the open sky (BEAM:
## guardable, not parryable, an ultimate attack); mark stacks add damage.
## It leaves short burning ground behind. The effect stops it and calls the
## collapse strike where it stands.

var owner_mech: MechMotor
var combat: CombatStateMachine
var effect: SweepEffect
var _t := 0.0
var _next_tick := 0.0
var _next_burn := 0.0
var _gone := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
## Tick hits so far (tests / tuning).
var tick_hits := 0


func setup(c: CombatStateMachine, eff: SweepEffect, start: Vector3) -> void:
	combat = c
	owner_mech = c.motor
	effect = eff
	name = "SweepBeam"
	add_to_group(&"orbital_strikes")
	global_position = OrbitalStrike.ground_point(owner_mech.get_world_3d(), start + Vector3.UP * 2.0)
	_ring_mat = _mat(OrbitalStrike.LOCK_COLOR, 1.5)
	_ring = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = eff.radius
	cm.bottom_radius = eff.radius
	cm.height = 0.08
	_ring.mesh = cm
	_ring.material_override = _ring_mat
	_ring.position = Vector3.UP * 0.06
	add_child(_ring)
	_next_tick = eff.arm_time
	_next_burn = eff.arm_time + eff.burn_every
	CombatEvents.area_telegraph.emit(owner_mech, global_position, eff.radius, eff.arm_time, &"orbital")
	CombatEvents.entity_spawned.emit(self, &"sweep_beam")


func _mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(c, 1.0)
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func is_armed() -> bool:
	return _t >= effect.arm_time


## Where the beam wants to go: the hand-steered point, else the lock target.
func aim_point() -> Vector3:
	if combat.placement_set:
		return combat.placement_point
	var t := combat.ranged_target()
	if t and is_instance_valid(t):
		return t.global_position
	return global_position


func _physics_process(delta: float) -> void:
	if _gone:
		return
	if owner_mech == null or not is_instance_valid(owner_mech) or not TeamRules.is_alive(owner_mech):
		remove()
		return
	_t += delta
	if not is_armed():
		_ring_mat.albedo_color.a = 0.3 + 0.35 * (0.5 + 0.5 * sin(_t * 30.0))
		return  # the landing warning stays where it was called
	if _beam == null:
		_build_beam()
	_steer(delta)
	_beam_mat.albedo_color.a = 0.45 + 0.15 * sin(_t * 20.0)
	while _t >= _next_tick:
		_next_tick += effect.tick_interval
		_tick()
	if effect.burn_attack and _t >= _next_burn:
		_next_burn += effect.burn_every
		var b := BurnZone.new()
		get_parent().add_child(b)
		b.global_position = global_position
		b.setup(owner_mech, effect.burn_attack, effect.radius, effect.burn_duration, effect.burn_interval)


func _steer(delta: float) -> void:
	var want := OrbitalStrike.clamp_to_range(owner_mech.global_position, aim_point(), effect.max_range)
	var p := global_position
	var flat := Vector2(want.x - p.x, want.z - p.z)
	var step := effect.speed * delta
	if flat.length() > step:
		flat = flat.normalized() * step
	var g := OrbitalStrike.ground_point(get_world_3d(), Vector3(p.x + flat.x, maxf(p.y, want.y) + 2.0, p.z + flat.y))
	global_position = g


func _build_beam() -> void:
	_ring_mat.albedo_color = Color(1.0, 0.45, 0.2, 0.4)
	_ring_mat.emission = Color(1.0, 0.45, 0.2)
	_beam_mat = _mat(Color(1.0, 0.6, 0.35, 0.5), 6.0)
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = effect.radius * 0.7
	cm.bottom_radius = effect.radius
	cm.height = effect.sky_height
	_beam.mesh = cm
	_beam.material_override = _beam_mat
	_beam.position = Vector3.UP * effect.sky_height * 0.5
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	CombatEvents.kit_event.emit(owner_mech, &"sweep_beam_down")


## One damage tick: every damageable inside the beam and under the open sky.
func _tick() -> void:
	if effect.tick_attack == null:
		return
	var world := get_world_3d()
	var shape := CylinderShape3D.new()
	shape.radius = effect.radius
	shape.height = effect.sky_height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * effect.sky_height * 0.5)
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
		var sky := Vector3(p.x, global_position.y + effect.sky_height, p.z)
		if not CombatTypes.has_line_of_sight(world, p, sky):
			continue  # under a roof
		var hit := HitInfo.new()
		hit.attacker = owner_mech
		hit.victim = hb.mech
		hit.attack = effect.tick_attack
		hit.source_entity = self
		hit.source_position = p + Vector3.UP * 8.0
		hit.hit_position = p
		hit.direction = Vector3.DOWN
		var vc := DamageSystem.get_combat(hb.mech)
		if vc:
			hit.damage_mult = 1.0 + effect.mark_bonus * vc.status.stacks(&"mark")
		DamageSystem.resolve(hit)
		tick_hits += 1


func remove() -> void:
	if _gone:
		return
	_gone = true
	CombatEvents.entity_removed.emit(self, &"sweep_beam", false)
	queue_free()
