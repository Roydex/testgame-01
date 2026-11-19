class_name MechFactory
extends RefCounted
## Builds a mech entity from data. Player and AI share exactly this setup;
## only the brain differs.

const PROFILES := [
	"res://resources/profiles/prototype_base.tres",
	"res://resources/profiles/pale_seraph.tres",
	"res://resources/profiles/hellfang.tres",
	"res://resources/profiles/verdant_ark.tres",
	"res://resources/profiles/azure_oracle.tres",
]
const COLORS := [
	Color(0.6, 0.62, 0.66), Color(0.9, 0.92, 0.95), Color(0.55, 0.1, 0.1),
	Color(0.2, 0.42, 0.25), Color(0.2, 0.4, 0.75),
]


static func load_profile(index: int) -> MechMovementProfile:
	return load(PROFILES[index % PROFILES.size()]) as MechMovementProfile


const COMBAT_SERAPH := "res://resources/combat/pale_seraph_combat.tres"
const COMBAT_SPARRING_RANGED := "res://resources/combat/sparring_ranged_combat.tres"
const COMBAT_HELLFANG := "res://resources/combat/hellfang_combat.tres"
const COMBAT_VERDANT := "res://resources/combat/verdant_combat.tres"
const COMBAT_AZURE := "res://resources/combat/azure_combat.tres"

## The four playable mechs: movement profile index, combat profile, colour,
## visual style. Player and AI are built from the same entry.
const MECH_IDS: Array[StringName] = [&"seraph", &"hellfang", &"verdant", &"azure"]
const MECHS := {
	&"seraph": {"name": "01 白祷·零式", "move": 1, "combat": COMBAT_SERAPH, "color": Color(0.9, 0.92, 0.95), "style": &"seraph"},
	&"hellfang": {"name": "02 赤狱·断牙", "move": 2, "combat": COMBAT_HELLFANG, "color": Color(0.55, 0.1, 0.1), "style": &"hellfang"},
	&"verdant": {"name": "03 苍藓·方舟", "move": 3, "combat": COMBAT_VERDANT, "color": Color(0.2, 0.42, 0.25), "style": &"verdant"},
	&"azure": {"name": "04 苍穹·星标", "move": 4, "combat": COMBAT_AZURE, "color": Color(0.2, 0.4, 0.75), "style": &"azure"},
}


static func create_by_id(id: StringName, team_id: int = 0, with_visual: bool = true, color_override := Color(0, 0, 0, 0)) -> MechMotor:
	var e: Dictionary = MECHS[id]
	var col: Color = e.color if color_override.a <= 0.0 else color_override
	var m := create_mech(load_profile(e.move), team_id, col, with_visual, load(e.combat) as CombatProfile, e.style)
	m.set_meta(&"mech_id", id)
	return m


static func create_mech(profile: MechMovementProfile, team_id: int = 0, color: Color = Color(0.7, 0.7, 0.7), with_visual: bool = true,
		combat_profile: CombatProfile = null, visual_style: StringName = &"generic") -> MechMotor:
	var m := MechMotor.new()
	m.name = "Mech"
	m.profile = profile
	m.team_id = team_id
	m.collision_layer = 2
	m.collision_mask = 1 | 2 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.9
	cap.height = MechMotor.BODY_HEIGHT
	cs.shape = cap
	cs.position = Vector3.UP * MechMotor.BODY_HEIGHT * 0.5
	m.add_child(cs)
	var combat := CombatStateMachine.new()
	combat.name = "CombatStateMachine"
	m.add_child(combat)
	combat.setup(combat_profile, m)
	if with_visual:
		var vis := MechVisual.new()
		vis.name = "Visual"
		m.add_child(vis)
		vis.setup(m, color, visual_style)
	return m
