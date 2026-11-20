extends "res://scripts/level/graybox_test_scene.gd"
## 技能测试场景 (phase 3a). The grey-box arena plus a cover wall and a roofed
## shelter next to the spawn, so every rule can be tried by hand: cover vs
## shots / grapple / turret fire / blasts, roofs vs the orbital strike.
##   1–4  play 01 白祷 / 02 赤狱 / 03 苍藓 / 04 苍穹 (swap in place)
##   G    cycle the sparring partner's mech
##   7 / 8 / 9  toggle the round-2 experiments (速度即伤害 / 动态对决镜头 /
##              自由瞄准), 0 all on / off. They start ON in the lab.
## Everything else (practice mode, F-keys, pause menu) works as in the
## grey-box scene. Command-line: `-- --skill-demo` runs the scripted showcase.

const LAB_POINTS := {
	"wall": Vector3(-12, 2.0, 16),
	"shelter": Vector3(14, 0.0, 16),
}

static var player_id: StringName = &"hellfang"
static var partner_id: StringName = &"seraph"


func _ready() -> void:
	Experiments.set_all(true)
	GrayboxBuilder.build(self)
	_build_lab_cover()
	_spawn_player(1)
	_spawn_dummies()
	set_practice(true)
	_swap_partner(partner_id)
	if "--skill-demo" in OS.get_cmdline_user_args():
		var sd := preload("res://scripts/debug/skill_demo.gd").new()
		sd.name = "SkillDemo"
		add_child(sd)
		sd.run(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	combat_hud.callout("技能测试场景：%s" % MechFactory.MECHS[player_id].name, Color(1, 0.9, 0.6), 2.0)


func _exit_tree() -> void:
	Experiments.set_all(false)  # never leak into other scenes / tests
	Engine.time_scale = 1.0


func _create_player_motor(_index: int) -> MechMotor:
	return MechFactory.create_by_id(player_id, 0, true)


func _build_lab_cover() -> void:
	var c := Color(0.62, 0.5, 0.45)
	GrayboxBuilder._box(self, "LabWall", Vector3(10, 4, 1), LAB_POINTS.wall, c)
	var s: Vector3 = LAB_POINTS.shelter
	for x in [-3.6, 3.6]:
		for z in [-3.6, 3.6]:
			GrayboxBuilder._box(self, "LabShelterPillar", Vector3(0.8, 5, 0.8), s + Vector3(x, 2.5, z), c)
	GrayboxBuilder._box(self, "LabShelterRoof", Vector3(8.8, 0.4, 8.8), s + Vector3(0, 5.2, 0), c)
	_sign("掩体墙：挡住射击、钩爪、炮台火力和爆炸", LAB_POINTS.wall + Vector3(0, 3.2, 0))
	_sign("有顶掩体：轨道激光打不进来", s + Vector3(0, 6.4, 0))


func _sign(text: String, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UiFont.get_font()
	l.font_size = 48
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 8
	l.position = at
	add_child(l)


## Replace the player's mech in place (keeps position, camera and HUDs).
func swap_player(id: StringName) -> void:
	player_id = id
	var at := motor.global_position
	motor.name = "Player_old"  # free the name for the new mech
	motor.queue_free()
	attach_player(MechFactory.create_by_id(id, 0, true), at + Vector3.UP * 0.3)
	set_practice(practice_mode)
	combat_hud.callout(MechFactory.MECHS[id].name, Color(1, 0.9, 0.6), 1.5)
	combat_hud.set_mode_banner(_banner())


## Replace the melee sparring partner with another mech's kit.
func _swap_partner(id: StringName) -> void:
	partner_id = id
	if dummies.is_empty():
		return
	var old := dummies[0]
	var at := old.global_position
	var mode := (old.get_node(^"SparringBrain") as SparringBrain).mode
	old.name = "Sparring_old"
	old.queue_free()
	var d := MechFactory.create_by_id(id, 1, true, Color(0.85, 0.75, 0.6) if id == &"seraph" else Color(0, 0, 0, 0))
	d.name = "Sparring_" + String(id).capitalize()
	d.position = at + Vector3.UP * 0.3
	d.add_to_group(&"lock_targets")
	add_child(d)
	var b := SparringBrain.new()
	b.name = "SparringBrain"
	b.mode = mode
	d.add_child(b)
	b.setup(d)
	dummies[0] = d
	set_practice(practice_mode)


## Skill lab (playtest round 3): F9 switches the always-shooting ranged
## partner together with the melee one, so "静止" really means quiet.
func _sync_ranged_partner() -> void:
	if dummies.size() < 2:
		return
	var mb := dummies[0].get_node(^"SparringBrain") as SparringBrain
	var rb := dummies[1].get_node(^"SparringBrain") as SparringBrain
	var map := {
		SparringBrain.Mode.TRAINING: SparringBrain.Mode.TRAINING_RANGED,
		SparringBrain.Mode.MELEE: SparringBrain.Mode.RANGED,
		SparringBrain.Mode.PASSIVE: SparringBrain.Mode.PASSIVE,
		SparringBrain.Mode.GUARD: SparringBrain.Mode.GUARD,
		SparringBrain.Mode.PARRY_TRAINER: SparringBrain.Mode.PARRY_TRAINER,
	}
	rb.mode = map.get(mb.mode, SparringBrain.Mode.PASSIVE)
	combat_hud.set_mode_banner(_banner())
	combat_hud.callout("陪练机：近战 %s · 远程 %s" % [mb.get_mode_name(), rb.get_mode_name()])


func _banner() -> String:
	var ex: PackedStringArray = []
	for id: StringName in [&"momentum", &"duel_cam", &"free_aim"]:
		ex.append("%s%s" % [Experiments.NAMES[id], "开" if Experiments.is_on(id) else "关"])
	return "%s   陪练：%s   [1–4 切换机体  G 切换陪练机体]\n实验：%s   [7 / 8 / 9 切换  0 全开/全关]" % [
		super(), MechFactory.MECHS[partner_id].name, "  ".join(ex)]


func _unhandled_input(event: InputEvent) -> void:
	for i in 4:
		if event.is_action_pressed(StringName("lab_mech_%d" % (i + 1))):
			swap_player(MechFactory.MECH_IDS[i])
			return
	for pair in [[&"lab_exp_momentum", &"momentum"], [&"lab_exp_duel_cam", &"duel_cam"], [&"lab_exp_free_aim", &"free_aim"]]:
		if event.is_action_pressed(pair[0]):
			var on := Experiments.toggle(pair[1])
			combat_hud.callout("%s：%s" % [Experiments.NAMES[pair[1]], "开" if on else "关"], Color(0.7, 0.95, 1.0), 1.2)
			combat_hud.set_mode_banner(_banner())
			return
	if event.is_action_pressed(&"lab_exp_all"):
		var all_on := Experiments.momentum and Experiments.duel_cam and Experiments.free_aim
		Experiments.set_all(not all_on)
		combat_hud.callout("全部实验：%s" % ("关" if all_on else "开"), Color(0.7, 0.95, 1.0), 1.2)
		combat_hud.set_mode_banner(_banner())
		return
	if event.is_action_pressed(&"debug_dummy_mode"):
		super(event)  # cycles the melee partner
		_sync_ranged_partner()
		return
	if event.is_action_pressed(&"lab_partner_next"):
		var ids := MechFactory.MECH_IDS
		_swap_partner(ids[(ids.find(partner_id) + 1) % ids.size()])
		combat_hud.callout("陪练机：%s" % MechFactory.MECHS[partner_id].name)
		return
	super(event)
