class_name CombatFeedback
extends Node3D
## Presentation only. Listens to CombatEvents and plays sparks, placeholder
## sounds and (capped) camera shake. Removing this node changes nothing in
## combat outcomes.

## Global multipliers so feel can be tuned without touching attack data.
@export var shake_scale: float = 1.0
@export var max_shake: float = 0.6
@export var audio_volume_db: float = -6.0
@export var spark_scale: float = 1.0

var rig: CameraRig
## Only hits involving this mech shake the camera.
var focus_mech: Node3D
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer3D.new()
		p.volume_db = audio_volume_db
		p.max_distance = 120.0
		p.unit_size = 12.0
		add_child(p)
		_players.append(p)
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.attack_started.connect(_on_attack)
	CombatEvents.telegraph.connect(_on_telegraph)
	CombatEvents.ultimate_phase.connect(_on_ult)
	CombatEvents.mech_died.connect(_on_died)


func _exit_tree() -> void:
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


func _on_hit(hit: HitInfo) -> void:
	var pos := hit.hit_position
	match hit.result:
		CombatTypes.HitResult.HIT:
			var heavy := hit.attack.damage >= 15.0
			play(&"heavy_hit" if heavy else &"hit", pos, randf_range(0.95, 1.05))
			_spark(pos, Color(1.0, 0.55, 0.2), 0.9 if heavy else 0.6)
			if _involved(hit):
				_shake(hit.attack.shake)
		CombatTypes.HitResult.GUARDED:
			play(&"guard", pos)
			_spark(pos, Color(0.5, 0.75, 1.0), 0.5)
			if _involved(hit):
				_shake(hit.attack.shake * 0.4)
		CombatTypes.HitResult.GUARD_BREAK:
			play(&"guard_break", pos)
			_spark(pos, Color(1.0, 0.7, 0.2), 1.1)
			if _involved(hit):
				_shake(hit.attack.shake * 1.2)
		CombatTypes.HitResult.PARRIED, CombatTypes.HitResult.DEFLECTED:
			play(&"parry", pos)
			_spark(pos, Color(1.0, 1.0, 1.0), 1.2)
			if _involved(hit):
				_shake(0.2)
		CombatTypes.HitResult.REFLECTED:
			play(&"reflect", pos)
			_spark(pos, Color(0.8, 0.95, 1.0), 0.8)


func _on_attack(attacker: Node3D, attack: AttackDefinition) -> void:
	if attack and attack.attack_type == CombatTypes.AttackType.MELEE:
		play(&"swing", attacker.global_position + Vector3.UP * 2.5, randf_range(0.9, 1.1))


func _on_telegraph(attacker: Node3D, _attack: AttackDefinition, _d: float) -> void:
	play(&"telegraph", attacker.global_position + Vector3.UP * 3.0)


func _on_ult(mech: Node3D, phase: String) -> void:
	if phase == "JUDGMENT" or phase == "WINDUP":
		play(&"ult", mech.global_position + Vector3.UP * 3.0, 1.0 if phase == "JUDGMENT" else 0.8)
		_spark(mech.global_position + Vector3.UP * 4.0, Color(1.0, 0.95, 0.7), 2.0)


func _on_died(mech: Node3D) -> void:
	play(&"death", mech.global_position + Vector3.UP * 2.0)
	_spark(mech.global_position + Vector3.UP * 2.0, Color(1.0, 0.4, 0.1), 2.5)


func _shake(amount: float) -> void:
	if rig:
		rig.add_shake(minf(amount * shake_scale, max_shake))


func _spark(pos: Vector3, color: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2 * spark_scale
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * spark_scale, 0.18)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tw.chain().tween_callback(mi.queue_free)
