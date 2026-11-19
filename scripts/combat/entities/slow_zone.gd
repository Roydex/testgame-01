class_name SlowZone
extends Node3D
## VERDANT ARK 区域束缚装置. A ground area: hostile mechs inside (up to
## `HEIGHT` above it) get the restraint status — slower movement, pricier
## dashes. Never a root. Leaving it (or rising above it) ends the effect
## within the status duration. Hostility comes from TeamRules.

const HEIGHT := 6.0

var owner_mech: Node3D
var team_id: int = -1
var kind: int = DeploySpec.Kind.ZONE
var spec: DeploySpec
var age := 0.0
var _gone := false
var _mat: StandardMaterial3D


func setup(p_owner: Node3D, p_spec: DeploySpec) -> void:
	owner_mech = p_owner
	team_id = TeamRules.get_team(p_owner)
	spec = p_spec
	name = "SlowZone"
	add_to_group(&"deployables")
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.3, 0.95, 0.45, 0.28)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color(0.25, 0.9, 0.4)
	_mat.emission_energy_multiplier = 1.0
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = spec.radius
	cm.bottom_radius = spec.radius
	cm.height = 0.06
	disk.mesh = cm
	disk.material_override = _mat
	disk.position = Vector3.UP * 0.05
	add_child(disk)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = spec.radius - 0.15
	tm.outer_radius = spec.radius + 0.15
	rim.mesh = tm
	rim.material_override = _mat
	rim.position = Vector3.UP * 0.1
	add_child(rim)
	CombatEvents.area_telegraph.emit(owner_mech, global_position, spec.radius, spec.lifetime, &"zone")
	CombatEvents.entity_spawned.emit(self, &"zone")


func is_alive() -> bool:
	return not _gone and is_inside_tree()


func contains(p: Vector3) -> bool:
	var d := p - global_position
	return Vector2(d.x, d.z).length() <= spec.radius and d.y >= -1.0 and d.y <= HEIGHT


func _physics_process(delta: float) -> void:
	if _gone:
		return
	age += delta
	if age >= spec.lifetime or owner_mech == null or not is_instance_valid(owner_mech):
		_gone = true
		CombatEvents.entity_removed.emit(self, &"zone", false)
		queue_free()
		return
	_mat.albedo_color.a = 0.2 + 0.1 * sin(age * 4.0)
	if spec.zone_status == null:
		return
	for t in TeamRules.get_valid_targets(self, &"mechs"):
		if not contains(t.global_position):
			continue
		var tc := DamageSystem.get_combat(t)
		if tc:
			tc.status.apply(spec.zone_status, self)
