class_name Habitat
extends Node3D
## VERDANT ARK 方舟苏生 habitat: a fixed circle where the seed core woke.
## Owner's turrets inside fire faster, reach farther and mend; the owner mends
## inside (damage-taken bonus via DeployKit.incoming_mult); hostile mechs on
## the rim are slowed (status refreshed each tick). Removed by the effect.

var owner_mech: MechMotor
var effect: ArkRevivalEffect
var _gone := false
var _t := 0.0
var _rim_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D


func setup(p_owner: MechMotor, p_effect: ArkRevivalEffect) -> void:
	owner_mech = p_owner
	effect = p_effect
	name = "Habitat"
	add_to_group(&"habitats")
	var r := effect.habitat_radius
	_disc_mat = _mat(Color(0.25, 0.9, 0.4, 0.14))
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.05
	disc.mesh = cm
	disc.material_override = _disc_mat
	disc.position = Vector3.UP * 0.06
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_rim_mat = _mat(Color(0.3, 1.0, 0.45, 0.5))
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - effect.edge_width
	tm.outer_radius = r
	tm.rings = 64
	rim.mesh = tm
	rim.material_override = _rim_mat
	rim.position = Vector3.UP * 0.1
	rim.scale = Vector3(1.0, 0.15, 1.0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	# mycelium spokes
	for i in 12:
		var sp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.06, r)
		sp.mesh = bm
		sp.material_override = _rim_mat
		var a := TAU * i / 12.0
		sp.position = Vector3(sin(a) * r * 0.5, 0.12, cos(a) * r * 0.5)
		sp.rotation.y = a
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)
	CombatEvents.area_telegraph.emit(owner_mech, global_position, r, 0.0, &"habitat")
	CombatEvents.entity_spawned.emit(self, &"habitat")


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(c, 1.0)
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func flat_dist(n: Node3D) -> float:
	return Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()


func contains(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and flat_dist(n) <= effect.habitat_radius


func _physics_process(delta: float) -> void:
	if _gone:
		return
	if owner_mech == null or not is_instance_valid(owner_mech) or not TeamRules.is_alive(owner_mech):
		remove()
		return
	if owner_mech.in_hitstop():
		return
	_t += delta
	_rim_mat.albedo_color.a = 0.4 + 0.2 * sin(_t * 3.0)
	var r := effect.habitat_radius
	for t in Deployables.owned_by(owner_mech, DeploySpec.Kind.TURRET):
		var tu := t as Turret
		if tu == null:
			continue
		var inside := contains(tu)
		tu.fire_rate_mult = effect.turret_rate_mult if inside else 1.0
		tu.range_bonus = effect.turret_range_bonus if inside else 0.0
		if inside:
			tu.health.heal(effect.turret_regen_per_sec * delta)
	var oc := DamageSystem.get_combat(owner_mech)
	if oc and contains(owner_mech):
		oc.health.heal(oc.health.max_hp * effect.owner_regen_frac * delta)
	if effect.edge_status:
		for e in TeamRules.get_valid_targets(owner_mech, &"mechs"):
			var d := flat_dist(e)
			if d <= r and d >= r - effect.edge_width:
				var ec := DamageSystem.get_combat(e)
				if ec:
					ec.status.apply(effect.edge_status, owner_mech)


func remove() -> void:
	if _gone:
		return
	_gone = true
	if owner_mech and is_instance_valid(owner_mech):
		for t in Deployables.owned_by(owner_mech, DeploySpec.Kind.TURRET):
			var tu := t as Turret
			if tu:
				tu.fire_rate_mult = 1.0
				tu.range_bonus = 0.0
	CombatEvents.entity_removed.emit(self, &"habitat", false)
	queue_free()
