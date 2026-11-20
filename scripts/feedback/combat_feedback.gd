class_name CombatFeedback
extends Node3D
## Presentation only. Listens to CombatEvents and plays sparks, placeholder
## sounds and (capped) camera shake. Removing this node changes nothing in
## combat outcomes.

## Global multipliers so feel can be tuned without touching attack data.
@export var shake_scale: float = 1.0
@export var max_shake: float = 0.6
@export var audio_volume_db: float = 0.0
@export var damage_numbers: bool = true
## FOV punch (deg) on hits involving the focus mech.
@export var fov_punch: float = 3.0
@export var spark_scale: float = 1.0

var rig: CameraRig
## Only hits involving this mech shake the camera.
var focus_mech: Node3D
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0
## 动态对决镜头: real-time end of the current slow motion (ms, 0 = none).
var _slowmo_until := 0
## Attacks that count as a cinematic finisher when they land.
const CINE_ATTACKS: Array[StringName] = [&"seraph_riposte", &"seraph_judgment_counter", &"seraph_final_spear",
	&"hf_finisher", &"hf_furnace_burst", &"hf_ram"]
const SLOWMO_SCALE := 0.3
const SLOWMO_MS := 220
## Real-time gap between two cinematic cuts (brawls must not cut constantly).
const CINE_COOLDOWN_MS := 1500
const CINE_CUT_S := 0.5
var _last_cine_ms := -100000
## Cuts taken so far (tests / tuning).
var cinematic_count := 0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer3D.new()
		p.volume_db = audio_volume_db
		p.max_distance = 120.0
		p.unit_size = 12.0
		add_child(p)
		_players.append(p)
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.attack_active.connect(_on_attack)
	CombatEvents.telegraph.connect(_on_telegraph)
	CombatEvents.ultimate_phase.connect(_on_ult)
	CombatEvents.mech_died.connect(_on_died)
	CombatEvents.area_telegraph.connect(_on_area)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	for p in _players:
		p.stop()
		p.stream = null
	ProceduralAudio.clear_cache()


func play(id: StringName, pos: Vector3, pitch: float = 1.0) -> void:
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = ProceduralAudio.get_stream(id)
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


func _involved(hit: HitInfo) -> bool:
	return focus_mech != null and (hit.victim == focus_mech or hit.attacker == focus_mech)


func _process(_delta: float) -> void:
	if _slowmo_until > 0 and Time.get_ticks_msec() >= _slowmo_until:
		_slowmo_until = 0
		Engine.time_scale = 1.0


## Cinematic moment (duel-cam experiment only): brief slow motion + close-up.
func _cinematic() -> void:
	if not Experiments.duel_cam:
		return
	var now := Time.get_ticks_msec()
	if now - _last_cine_ms < CINE_COOLDOWN_MS:
		return
	_last_cine_ms = now
	cinematic_count += 1
	Engine.time_scale = SLOWMO_SCALE
	_slowmo_until = now + SLOWMO_MS
	if rig:
		rig.cinematic(CINE_CUT_S)


func _on_hit(hit: HitInfo) -> void:
	var pos := hit.hit_position
	var me := _involved(hit)
	var dir := hit.direction
	if me and (hit.result == CombatTypes.HitResult.PARRIED or hit.result == CombatTypes.HitResult.GUARD_BREAK \
			or (hit.result == CombatTypes.HitResult.HIT and (hit.attack.id in CINE_ATTACKS or hit.momentum_mult >= 1.3))):
		_cinematic()
	if hit.momentum_mult > 1.1 and DamageSystem.is_landed(hit.result):
		_number(pos + Vector3.UP * 0.8, "高速 ×%.1f" % hit.momentum_mult, Color(0.5, 0.9, 1.0), 1.1)
	match hit.result:
		CombatTypes.HitResult.HIT:
			var heavy := hit.attack.damage >= 15.0
			play(&"heavy_hit" if heavy else &"hit", pos, randf_range(0.95, 1.05))
			_impact(pos, dir, Color(1.0, 0.55, 0.2), 1.3 if heavy else 0.9, 14 if heavy else 9)
			var counter := DamageSystem.get_combat(hit.victim) != null and DamageSystem.get_combat(hit.victim).offbalance_by == hit.attacker
			_number(pos, "%d" % roundi(hit.final_damage), Color(1.0, 0.85, 0.3) if counter else Color(1, 1, 1), 1.4 if counter or heavy else 1.0)
			if me:
				_shake(hit.attack.shake, heavy)
		CombatTypes.HitResult.GUARDED:
			play(&"guard", pos)
			_impact(pos, dir, Color(0.5, 0.75, 1.0), 0.6, 5)
			_number(pos, "%.1f" % hit.final_damage, Color(0.6, 0.8, 1.0), 0.8)
			if me:
				_shake(hit.attack.shake * 0.4, false)
		CombatTypes.HitResult.GUARD_BREAK:
			play(&"guard_break", pos)
			_impact(pos, dir, Color(1.0, 0.7, 0.2), 1.6, 16)
			_number(pos, "破防", Color(1.0, 0.6, 0.2), 1.5)
			if me:
				_shake(hit.attack.shake * 1.3, true)
		CombatTypes.HitResult.PARRIED, CombatTypes.HitResult.DEFLECTED:
			play(&"parry", pos)
			_impact(pos, -dir, Color(1.0, 1.0, 1.0), 1.7, 18)
			_number(pos, "招架", Color(0.85, 0.95, 1.0), 1.5)
			if me:
				_shake(0.35, true)
		CombatTypes.HitResult.REFLECTED:
			play(&"reflect", pos)
			_impact(pos, -dir, Color(0.8, 0.95, 1.0), 1.1, 10)
			_number(pos, "折射", Color(0.8, 0.95, 1.0), 1.2)


func _on_attack(attacker: Node3D, attack: AttackDefinition) -> void:
	if attack and attack.attack_type == CombatTypes.AttackType.MELEE:
		play(&"swing", attacker.global_position + Vector3.UP * 2.5, randf_range(0.9, 1.1))
	if attack and attack.hit_cone_deg > 0.0 and attacker is MechMotor:
		_flame_cone(attacker as MechMotor, attack)


## 熔炉喷焰: a fading cone of fire along the attacker's facing.
func _flame_cone(m: MechMotor, attack: AttackDefinition) -> void:
	var fwd := m.get_forward()
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var length := attack.hitbox_size.z
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = length * tan(deg_to_rad(attack.hit_cone_deg * 0.5))
	cm.height = length
	var cone := _fx_mesh(cm, Color(1.0, 0.45, 0.1, 0.55), m.global_position + Vector3.UP * 2.2 + fwd * (length * 0.5 + 0.4))
	cone.global_basis = Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	var mat := cone.material_override as StandardMaterial3D
	var tw := cone.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, attack.active + 0.15)
	tw.tween_callback(cone.queue_free)
	play(&"heavy_hit", m.global_position + Vector3.UP * 2.5, 0.6)


func _on_telegraph(attacker: Node3D, _attack: AttackDefinition, _d: float) -> void:
	play(&"telegraph", attacker.global_position + Vector3.UP * 3.0)


func _on_ult(mech: Node3D, phase: String) -> void:
	if phase == "JUDGMENT" and mech == focus_mech:
		_cinematic()
	if phase == "JUDGMENT" or phase == "WINDUP":
		play(&"ult", mech.global_position + Vector3.UP * 3.0, 1.0 if phase == "JUDGMENT" else 0.8)
		_spark(mech.global_position + Vector3.UP * 4.0, Color(1.0, 0.95, 0.7), 2.0)


func _on_died(mech: Node3D) -> void:
	play(&"death", mech.global_position + Vector3.UP * 2.0)
	_spark(mech.global_position + Vector3.UP * 2.0, Color(1.0, 0.4, 0.1), 2.5)


## Instant area effects (blasts, the orbital shockwave, overheat steam):
## a flat ring that expands to the real radius and fades.
func _on_area(_owner: Node3D, pos: Vector3, radius: float, duration: float, kind: StringName) -> void:
	if duration > 0.0:
		return  # telegraphs draw themselves (orbital circle, zones)
	var col := Color(0.85, 0.9, 1.0) if kind == &"steam" else (Color(0.45, 1.0, 0.35) if kind == &"spore" else Color(1.0, 0.55, 0.2))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.9
	tor.outer_radius = 1.0
	tor.rings = 48
	var ring := _fx_mesh(tor, col, pos + Vector3.DOWN * 0.6)
	ring.scale = Vector3(radius * 0.15, 1.0, radius * 0.15)
	var m := ring.material_override as StandardMaterial3D
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.5, radius), 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)
	if kind == &"steam":
		play(&"guard", pos, 0.6)
	elif radius >= 6.0:
		play(&"heavy_hit", pos, 0.7)


func _shake(amount: float, punch: bool) -> void:
	if rig:
		rig.add_shake(minf(amount * shake_scale, max_shake))
		if punch:
			rig.add_fov_punch(fov_punch)


func _spark(pos: Vector3, color: Color, size: float) -> void:
	_impact(pos, Vector3.ZERO, color, size, 0)


## Flash + expanding ring + flying shards.
func _impact(pos: Vector3, dir: Vector3, color: Color, size: float, shards: int) -> void:
	var s := size * spark_scale
	var flash := _fx_mesh(SphereMesh.new(), color, pos)
	(flash.mesh as SphereMesh).radius = 0.5
	(flash.mesh as SphereMesh).height = 1.0
	flash.scale = Vector3.ONE * 0.3 * s
	var m1 := flash.material_override as StandardMaterial3D
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 1.6 * s, 0.12)
	tw.tween_property(m1, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(flash.queue_free)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.5
	var ring := _fx_mesh(tor, color, pos)
	if dir.length() > 0.1:
		ring.look_at_from_position(pos, pos + dir, Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT)
		ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	ring.scale = Vector3.ONE * 0.5 * s
	var m2 := ring.material_override as StandardMaterial3D
	var tw2 := ring.create_tween().set_parallel(true)
	tw2.tween_property(ring, "scale", Vector3.ONE * 3.2 * s, 0.22)
	tw2.tween_property(m2, "albedo_color:a", 0.0, 0.24)
	tw2.chain().tween_callback(ring.queue_free)
	for i in shards:
		var b := BoxMesh.new()
		b.size = Vector3(0.08, 0.08, 0.5) * s
		var sh := _fx_mesh(b, color, pos)
		var v := Vector3(randf_range(-1, 1), randf_range(-0.3, 1.0), randf_range(-1, 1)).normalized()
		if dir.length() > 0.1:
			v = (v + dir.normalized() * 1.2).normalized()
		sh.look_at_from_position(pos, pos + v, Vector3.UP if absf(v.y) < 0.95 else Vector3.RIGHT)
		var dist := randf_range(1.5, 3.5) * s
		var t3 := sh.create_tween().set_parallel(true)
		t3.tween_property(sh, "global_position", pos + v * dist + Vector3.DOWN * 0.4, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t3.tween_property(sh.material_override, "albedo_color:a", 0.0, 0.28)
		t3.chain().tween_callback(sh.queue_free)


func _fx_mesh(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	return mi


func _number(pos: Vector3, text: String, color: Color, size: float) -> void:
	if not damage_numbers:
		return
	var l := Label3D.new()
	l.font = UiFont.get_font()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011 * size
	l.font_size = 48
	l.outline_size = 10
	l.modulate = color
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.4, 0.4), 0.8, 0)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3.UP * 1.6, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)
