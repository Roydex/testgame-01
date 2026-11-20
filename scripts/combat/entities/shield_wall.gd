class_name ShieldWall
extends Node3D
## VERDANT ARK 盾墙 (playtest round 2): a destructible energy wall raised by
## the guard button. Hostile shots and melee swings hit its box hurtbox and
## are absorbed (DamageSystem plain entity hit); allied shots pass through
## (TeamRules.can_damage), so teammates can fight from behind it. Mechs bump
## into it. Blasts, beams and grabs still use world line of sight and are
## not blocked (prototype limitation, see KNOWN_ISSUES). Never hard-codes
## teams or modes.

signal gone(destroyed: bool)

var owner_mech: Node3D
var team_id: int = -1
var health: Health
var lifetime := 8.0
var age := 0.0
var _gone := false
var _mat: StandardMaterial3D
var _flash := 0.0


func setup(p_owner: Node3D, size: Vector3, hp: float, p_lifetime: float) -> void:
	owner_mech = p_owner
	team_id = TeamRules.get_team(p_owner)
	lifetime = p_lifetime
	name = "ShieldWall"
	add_to_group(&"shield_walls")
	health = Health.new()
	add_child(health)
	health.setup(hp)
	health.died.connect(func() -> void: remove(true))
	# box hurtbox (shots / swings resolve against the wall)
	var hb := Hurtbox.new()
	hb.mech = self
	hb.name = "Hurtbox"
	hb.collision_layer = CombatTypes.HURTBOX_LAYER
	hb.collision_mask = 0
	hb.monitoring = false
	var hcs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = size + Vector3(0.0, 0.0, 0.4)
	hcs.shape = hbox
	hcs.position = Vector3.UP * size.y * 0.5
	hb.add_child(hcs)
	add_child(hb)
	# solid body: mechs bump into it (same "targets" layer as turrets)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3.UP * size.y * 0.5
	body.add_child(cs)
	add_child(body)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.35, 1.0, 0.55, 0.35)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color(0.4, 1.0, 0.6)
	_mat.emission_energy_multiplier = 1.5
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat
	mi.position = Vector3.UP * size.y * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.entity_spawned.emit(self, &"wall")


func is_alive() -> bool:
	return not _gone and is_inside_tree()


func time_left() -> float:
	return maxf(lifetime - age, 0.0)


func _on_hit(h: HitInfo) -> void:
	if h.victim == self:
		_flash = 0.15


func _physics_process(delta: float) -> void:
	if _gone:
		return
	age += delta
	_flash = maxf(_flash - delta, 0.0)
	var k := health.ratio() if health else 1.0
	_mat.albedo_color = Color(lerpf(1.0, 0.35, k), lerpf(0.5, 1.0, k), 0.55, 0.3 + (0.35 if _flash > 0.0 else 0.0))
	if owner_mech == null or not is_instance_valid(owner_mech) or not TeamRules.is_alive(owner_mech) or age >= lifetime:
		remove(false)


func remove(destroyed: bool) -> void:
	if _gone:
		return
	_gone = true
	if CombatEvents.hit_resolved.is_connected(_on_hit):
		CombatEvents.hit_resolved.disconnect(_on_hit)
	if destroyed and owner_mech and is_instance_valid(owner_mech):
		CombatEvents.kit_event.emit(owner_mech, &"wall_broken")
	CombatEvents.entity_removed.emit(self, &"wall", destroyed)
	gone.emit(destroyed)
	queue_free()
