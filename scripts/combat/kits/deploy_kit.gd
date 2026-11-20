class_name DeployKit
extends MechKit
## VERDANT ARK 部署. At most `max_turrets` turrets at a time (each expires
## on its own timer, and can be destroyed); the deploy skills have their
## own cooldowns (AttackDefinition.cooldown). Near its own turrets the ark
## is tougher (fortress).


var wall: ShieldWall
var wall_cooldown_left := 0.0
## 方舟苏生: the active habitat (null when none) and the dormancy cost.
var habitat: Habitat
var dormant := false


func cfg() -> DeployConfig:
	return config as DeployConfig


func wall_up() -> bool:
	return wall != null and is_instance_valid(wall) and wall.is_alive()


func on_guard_started() -> void:
	if not cfg().wall_enabled or wall_up() or wall_cooldown_left > 0.0 or dormant:
		return
	var fwd := motor.get_forward()
	var rt := combat.ranged_target() if combat.ranged_target() else combat.aim_target
	if rt and is_instance_valid(rt):
		var to := rt.global_position - motor.global_position
		to.y = 0.0
		if to.length() > 0.5:
			fwd = to.normalized()
	var at := OrbitalStrike.ground_point(motor.get_world_3d(), motor.global_position + fwd * cfg().wall_distance + Vector3.UP * 2.0)
	wall = ShieldWall.new()
	motor.get_parent().add_child(wall)
	wall.global_position = at
	wall.look_at(at + fwd, Vector3.UP)
	wall.setup(motor, cfg().wall_size, cfg().wall_hp, cfg().wall_lifetime)
	wall.gone.connect(func(_destroyed: bool) -> void: wall_cooldown_left = cfg().wall_cooldown)
	CombatEvents.kit_event.emit(motor, &"wall_up")


func _physics_process(delta: float) -> void:
	if wall_cooldown_left > 0.0 and not wall_up():
		wall_cooldown_left = maxf(wall_cooldown_left - delta, 0.0)


func setup(p_combat: CombatStateMachine, p_config: KitConfig) -> void:
	super.setup(p_combat, p_config if p_config else DeployConfig.new())


func turrets() -> Array[Node3D]:
	return Deployables.owned_by(motor, DeploySpec.Kind.TURRET)


func can_start(def: AttackDefinition) -> bool:
	if dormant and def.get_delivery() == CombatTypes.Delivery.DEPLOY:
		return false  # 方舟苏生 cost: no deploying while dormant
	if def.get_delivery() == CombatTypes.Delivery.DEPLOY and def.deploy_spec and def.deploy_spec.kind == DeploySpec.Kind.TURRET:
		return turrets().size() < cfg().max_turrets
	return true


func in_fortress() -> bool:
	for t in turrets():
		if t.global_position.distance_to(motor.global_position) <= cfg().fortress_radius:
			return true
	return false


func incoming_mult(_hit: HitInfo) -> float:
	var m := cfg().fortress_damage_taken if in_fortress() else 1.0
	if habitat and is_instance_valid(habitat) and habitat.contains(motor):
		m *= habitat.effect.owner_damage_taken
	return m


## 方舟苏生: turrets refilled next to the ark, deploy / zone / wall ready.
func revive() -> void:
	var p := combat.profile
	if p.skill:
		combat.clear_cooldown(p.skill.id)
	if p.skill_hold:
		combat.clear_cooldown(p.skill_hold.id)
	wall_cooldown_left = 0.0
	var spec: DeploySpec = p.skill.deploy_spec if p.skill and p.skill.deploy_spec else null
	if spec == null:
		return
	var side := 1.0
	while turrets().size() < cfg().max_turrets:
		var at := motor.global_position + motor.global_basis.x * (4.0 * side) + Vector3.UP * 2.0
		Deployables.spawn_turret(combat, spec, OrbitalStrike.ground_point(motor.get_world_3d(), at))
		side = -side
	CombatEvents.kit_event.emit(motor, &"ark_revive")


func reset() -> void:
	dormant = false
	habitat = null
	if wall_up():
		wall.remove(false)
	wall = null
	wall_cooldown_left = 0.0
	for t in turrets():
		t.call(&"_remove", false)
	for z in Deployables.owned_by(motor, DeploySpec.Kind.ZONE):
		z.queue_free()


func hud_text() -> String:
	var parts: PackedStringArray = []
	for t in turrets():
		parts.append("%.0fs" % float(t.call(&"time_left")))
	var line := "炮台 %d / %d%s" % [parts.size(), cfg().max_turrets, ("  [" + ", ".join(parts) + "]") if not parts.is_empty() else ""]
	var p := combat.profile
	if p.skill and p.skill.cooldown > 0.0 and combat.get_cooldown(p.skill.id) > 0.0:
		line += "  部署冷却 %.1fs" % combat.get_cooldown(p.skill.id)
	if p.skill_hold and combat.get_cooldown(p.skill_hold.id) > 0.0:
		line += "  束缚区冷却 %.1fs" % combat.get_cooldown(p.skill_hold.id)
	if in_fortress():
		line += "  堡垒（受伤 ×%.2f）" % cfg().fortress_damage_taken
	if wall_up():
		line += "  盾墙 %.0f HP %.0fs" % [wall.health.hp, wall.time_left()]
	elif wall_cooldown_left > 0.0:
		line += "  盾墙冷却 %.1fs" % wall_cooldown_left
	elif cfg().wall_enabled:
		line += "  盾墙就绪（右键）"
	return line
