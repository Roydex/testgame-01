class_name OrbitalStrike
extends Node3D
## AZURE ORACLE 轨道激光. Called on the lock target (or a point ahead of
## the caster when nothing is locked). The ground circle first FOLLOWS the
## target (speed-limited, orange) for the follow time, then LOCKS (red) for
## `lock_time`, then a vertical BEAM hits every damageable inside whose line
## to the sky is clear. Leaving the locked circle dodges it; roofs block it.
## BEAM: guardable, not parryable. Mark stacks shrink the circle and lengthen
## the follow phase (the locked dodge window never changes). A player can
## mark the point by hand (AIM state, see _call_marked). Playtest round 2
## made it a heavy strike: more damage, guard break, a burning circle after.

const FOLLOW_COLOR := Color(1.0, 0.6, 0.1, 0.35)
const LOCK_COLOR := Color(1.0, 0.12, 0.08, 0.35)

var owner_mech: Node3D
var attack: AttackDefinition
var spec: OrbitalSpec
var radius: float = 5.0
## Followed target (null: fixed point from the start).
var target: Node3D
var follow_duration := 0.0
## Hand-marked empty ground: the circle keeps the full warning (orange
## then red) but never moves.
var fixed_point := false
var telegraph := 0.0
var _t := 0.0
var _fired := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _beam: MeshInstance3D


static func ground_point(world: World3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 60.0, CombatTypes.WORLD_LAYER)
	var r := world.direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() else p


## Spawns the strike for `combat`'s current attack definition `def`.
static func call_strike(combat: CombatStateMachine, def: AttackDefinition) -> OrbitalStrike:
	var spec := def.orbital_spec if def.orbital_spec else OrbitalSpec.new()
	var m := combat.motor
	var marks := 0
	var at := m.global_position + m.get_forward() * spec.unlocked_distance
	var followed: Node3D = null
	if combat.placement_set:
		return _call_marked(combat, def, spec)
	var t := combat.ranged_target()
	if t == null and Experiments.free_aim and combat.free_aim_active \
			and m.global_position.distance_to(combat.free_aim_point) <= spec.max_call_range:
		at = combat.free_aim_point  # crosshair ground point, no follow
	if t and is_instance_valid(t) and TeamRules.is_alive(t) and m.global_position.distance_to(t.global_position) <= spec.max_call_range:
		at = t.global_position
		followed = t
		var tc := DamageSystem.get_combat(t)
		if tc:
			marks = tc.status.stacks(&"mark")
	var s := OrbitalStrike.new()
	m.get_parent().add_child(s)
	s.global_position = ground_point(m.get_world_3d(), at)
	s.target = followed
	s.follow_duration = (spec.follow_time + spec.follow_per_mark * marks) if s.target else 0.0
	s.setup(m, def, spec, clampf(spec.radius + spec.radius_per_mark * marks, spec.min_radius, maxf(spec.radius, spec.min_radius)))
	return s


## Playtest round 3: the player marked the point by hand (AIM state). A
## hostile mech inside the marked circle is followed exactly like a locked
## target; empty ground stays fixed with the same total warning.
static func _call_marked(combat: CombatStateMachine, def: AttackDefinition, spec: OrbitalSpec) -> OrbitalStrike:
	var m := combat.motor
	var at := clamp_to_range(m.global_position, combat.placement_point, spec.max_call_range)
	combat.placement_set = false
	var followed: Node3D = null
	var best := spec.radius
	for t in TeamRules.get_valid_targets(m, &"mechs"):
		var d := Vector2(t.global_position.x - at.x, t.global_position.z - at.z).length()
		if d <= best:
			best = d
			followed = t
	var marks := 0
	var tc := DamageSystem.get_combat(followed)
	if tc:
		marks = tc.status.stacks(&"mark")
	var s := OrbitalStrike.new()
	m.get_parent().add_child(s)
	s.global_position = ground_point(m.get_world_3d(), (followed.global_position if followed else at) + Vector3.UP * 2.0)
	s.target = followed
	s.fixed_point = followed == null
	s.follow_duration = spec.follow_time + spec.follow_per_mark * marks
	s.setup(m, def, spec, clampf(spec.radius + spec.radius_per_mark * marks, spec.min_radius, maxf(spec.radius, spec.min_radius)))
	return s


## 终末坐标: a strike called straight onto `target` (it follows, then locks).
static func call_on(combat: CombatStateMachine, def: AttackDefinition, target: Node3D) -> OrbitalStrike:
	var spec := def.orbital_spec if def.orbital_spec else OrbitalSpec.new()
	var m := combat.motor
	var s := OrbitalStrike.new()
	m.get_parent().add_child(s)
	s.global_position = ground_point(m.get_world_3d(), target.global_position + Vector3.UP * 2.0)
	s.target = target
	s.follow_duration = spec.follow_time
	s.setup(m, def, spec, spec.radius)
	return s


## A strike on a fixed ground point (no follow phase): the full lock warning
## of the spec, then the beam (AZURE 轨道扫射 collapse).
static func call_at(owner: Node3D, def: AttackDefinition, point: Vector3) -> OrbitalStrike:
	var spec := def.orbital_spec if def.orbital_spec else OrbitalSpec.new()
	var s := OrbitalStrike.new()
	owner.get_parent().add_child(s)
	s.global_position = ground_point(owner.get_world_3d(), point + Vector3.UP * 2.0)
	s.fixed_point = true
	s.follow_duration = 0.0
	s.setup(owner, def, spec, spec.radius)
	return s


## Horizontal clamp of a marked point to the call range around `from`.
static func clamp_to_range(from: Vector3, p: Vector3, max_range: float) -> Vector3:
	var d := Vector2(p.x - from.x, p.z - from.z)
	if d.length() <= max_range:
		return p
	d = d.normalized() * max_range
	return Vector3(from.x + d.x, p.y, from.z + d.y)


func is_locked() -> bool:
	return _t >= follow_duration


func setup(p_owner: Node3D, def: AttackDefinition, p_spec: OrbitalSpec, p_radius: float) -> void:
	owner_mech = p_owner
	attack = def
	spec = p_spec
	radius = p_radius
	name = "OrbitalStrike"
	telegraph = follow_duration + spec.lock_time
	add_to_group(&"orbital_strikes")
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = FOLLOW_COLOR if follow_duration > 0.0 else LOCK_COLOR
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(_ring_mat.albedo_color, 1.0)
	_ring_mat.emission_energy_multiplier = 1.5
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.08
	_ring.mesh = cm
	_ring.material_override = _ring_mat
	_ring.position = Vector3.UP * 0.06
	add_child(_ring)
	CombatEvents.area_telegraph.emit(owner_mech, global_position, radius, telegraph, &"orbital")
	CombatEvents.entity_spawned.emit(self, &"orbital")


func _physics_process(delta: float) -> void:
	if owner_mech == null or not is_instance_valid(owner_mech):
		CombatEvents.entity_removed.emit(self, &"orbital", false)
		queue_free()  # the caller was removed (mech swapped out / freed): the strike fizzles
		return
	var was_locked := is_locked()
	_t += delta
	if not _fired:
		if not is_locked():
			_follow(delta)
		elif not was_locked:
			_ring_mat.albedo_color = Color(LOCK_COLOR, _ring_mat.albedo_color.a)
			_ring_mat.emission = Color(LOCK_COLOR, 1.0)
			_ring.scale = Vector3(0.96, 1.0, 0.96)  # tightens as it locks
			CombatEvents.kit_event.emit(owner_mech, &"orbital_locked")
		# the circle pulses faster as the strike approaches
		var k := clampf(_t / maxf(telegraph, 0.01), 0.0, 1.0)
		_ring_mat.albedo_color.a = 0.25 + 0.4 * k * (0.5 + 0.5 * sin(_t * (8.0 + 20.0 * k)))
		if _t >= telegraph:
			_strike()
	elif _t >= telegraph + spec.beam_duration:
		CombatEvents.entity_removed.emit(self, &"orbital", false)
		queue_free()


## Following phase: slide toward the target's ground point at follow_speed.
func _follow(delta: float) -> void:
	if fixed_point:
		return  # hand-marked ground: stays put through the orange phase
	if target == null or not is_instance_valid(target) or not TeamRules.is_alive(target):
		follow_duration = minf(follow_duration, _t)  # lock where it is
		telegraph = follow_duration + spec.lock_time
		return
	var want := ground_point(get_world_3d(), target.global_position)
	var p := global_position
	var flat := Vector2(want.x - p.x, want.z - p.z)
	var step := spec.follow_speed * delta
	if flat.length() > step:
		flat = flat.normalized() * step
	global_position = Vector3(p.x + flat.x, want.y, p.z + flat.y)


func _strike() -> void:
	_fired = true
	var world := get_world_3d()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = spec.sky_height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * spec.sky_height * 0.5)
	q.collision_mask = CombatTypes.HURTBOX_LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var seen := {}
	var struck: Array = []
	if owner_mech and is_instance_valid(owner_mech):
		for r in world.direct_space_state.intersect_shape(q, 16):
			var hb := r.collider as Hurtbox
			if hb == null or hb.mech == null or seen.has(hb.mech.get_instance_id()):
				continue
			seen[hb.mech.get_instance_id()] = true
			if not TeamRules.can_damage(owner_mech, hb.mech):
				continue
			var p: Vector3 = hb.mech.call(&"get_lock_point") if hb.mech.has_method(&"get_lock_point") else hb.mech.global_position
			var sky := Vector3(p.x, global_position.y + spec.sky_height, p.z)
			if not CombatTypes.has_line_of_sight(world, p, sky):
				continue  # under a roof
			var hit := HitInfo.new()
			hit.attacker = owner_mech
			hit.victim = hb.mech
			hit.attack = attack
			hit.source_entity = self
			hit.source_position = p + Vector3.UP * 8.0
			hit.hit_position = p
			hit.direction = Vector3.DOWN
			DamageSystem.resolve(hit)
			struck.append(hb.mech)
	_ring.visible = false
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.8
	cm.bottom_radius = radius
	cm.height = spec.sky_height
	_beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.55, 0.3, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.4, 0.2)
	bm.emission_energy_multiplier = 6.0
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.material_override = bm
	_beam.position = Vector3.UP * spec.sky_height * 0.5
	add_child(_beam)
	if owner_mech and is_instance_valid(owner_mech):
		CombatEvents.kit_event.emit(owner_mech, &"orbital_strike")
	if spec.shock_attack and spec.shock_radius > radius and owner_mech and is_instance_valid(owner_mech):
		_shockwave(struck)


## Outer shockwave: mechs near the circle that the beam did not hit are
## blasted outward. Same shelter rule as the beam (a roof over them blocks
## it) plus ground cover between the impact and them.
func _shockwave(skip: Array) -> void:
	var world := get_world_3d()
	var center := global_position + Vector3.UP * 1.0
	var shape := SphereShape3D.new()
	shape.radius = spec.shock_radius
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
		if not TeamRules.can_damage(owner_mech, hb.mech):
			continue
		var p: Vector3 = hb.mech.call(&"get_lock_point") if hb.mech.has_method(&"get_lock_point") else hb.mech.global_position
		var sky := Vector3(p.x, global_position.y + spec.sky_height, p.z)
		if not CombatTypes.has_line_of_sight(world, p, sky) or not CombatTypes.has_line_of_sight(world, center, p):
			continue
		var hit := HitInfo.new()
		hit.attacker = owner_mech
		hit.victim = hb.mech
		hit.attack = spec.shock_attack
		hit.source_entity = self
		hit.source_position = center
		hit.hit_position = p
		hit.direction = (p - center).normalized()
		DamageSystem.resolve(hit)
	CombatEvents.area_telegraph.emit(owner_mech, center, spec.shock_radius, 0.0, &"blast")
	if spec.burn_attack and spec.burn_duration > 0.0 and owner_mech and is_instance_valid(owner_mech):
		var b := BurnZone.new()
		get_parent().add_child(b)
		b.global_position = global_position
		b.setup(owner_mech, spec.burn_attack, radius, spec.burn_duration, spec.burn_interval)
