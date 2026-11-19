class_name TestTarget
extends AnimatableBody3D
## Lock-on test dummy. Can hover, bob vertically or circle. Periodically shows
## an "attack telegraph" glow so camera readability (M06) can be judged.
## Not an AI: it follows a fixed motion pattern.

enum Pattern { STATIC, VERTICAL_SINE, CIRCLE, PATROL_LINE }

@export var pattern: Pattern = Pattern.STATIC
@export var team_id: int = 1
@export var amplitude: float = 10.0
@export var period: float = 6.0
@export var radius: float = 1.6
@export var telegraph_interval: float = 4.0
@export var telegraph_time: float = 0.8
@export var respawn_time: float = 5.0
@export var label_text: String = "Target"
@export_group("Test shooter (M04 fixture)")
## Fires a TestProjectile at the nearest hostile mech when each telegraph ends.
@export var shooter: bool = false
@export var shooting_enabled: bool = false
@export var projectile_speed: float = 55.0
@export var fire_range: float = 90.0
## Aim at the predicted position (linear lead) instead of the current one.
@export var lead_target: bool = false

var shots_fired: int = 0

var origin: Vector3
var time: float = 0.0
var alive: bool = true
var telegraphing: bool = false
var _mat: StandardMaterial3D
var _label: Label3D
var _col: CollisionShape3D
var _mesh: MeshInstance3D
var _dead_timer := 0.0


func _ready() -> void:
	add_to_group(&"lock_targets")
	collision_layer = 4
	collision_mask = 0
	sync_to_physics = true
	origin = global_position
	_col = CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	_col.shape = s
	add_child(_col)
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	_mesh.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.85, 0.25, 0.2)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.15, 0.05)
	_mat.emission_energy_multiplier = 0.2
	_mesh.material_override = _mat
	add_child(_mesh)
	_label = Label3D.new()
	_label.font = UiFont.get_font()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3.UP * (radius + 1.0)
	_label.pixel_size = 0.02
	_label.no_depth_test = true
	_label.text = label_text
	add_child(_label)


func is_alive() -> bool:
	return alive


func get_lock_point() -> Vector3:
	return global_position


func _fire() -> void:
	var best: MechMotor = null
	var best_d := fire_range
	for n in get_tree().get_nodes_in_group(&"mechs"):
		var m := n as MechMotor
		if m and TeamRules.is_hostile(self, m):
			var d := global_position.distance_to(m.global_position)
			if d < best_d:
				best_d = d
				best = m
	if best == null:
		return
	var chest := best.global_position + Vector3.UP * 2.0
	var aim := chest
	if lead_target:
		# iterate the intercept: flight time depends on the lead point itself
		for i in 4:
			aim = chest + best.velocity * (global_position.distance_to(aim) / projectile_speed)
	var p := TestProjectile.new()
	p.shooter = self
	p.velocity = (aim - global_position).normalized() * projectile_speed
	get_parent().add_child(p)
	p.global_position = global_position + p.velocity.normalized() * (radius + 0.3)
	shots_fired += 1


func kill() -> void:
	if not alive:
		return
	alive = false
	_dead_timer = respawn_time
	visible = false
	_col.set_deferred(&"disabled", true)


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_timer -= delta
		if _dead_timer <= 0.0 and respawn_time > 0.0:
			alive = true
			visible = true
			_col.set_deferred(&"disabled", false)
		return
	time += delta
	var w := TAU / maxf(period, 0.1)
	match pattern:
		Pattern.VERTICAL_SINE:
			global_position = origin + Vector3.UP * sin(time * w) * amplitude
		Pattern.CIRCLE:
			global_position = origin + Vector3(cos(time * w), 0.0, sin(time * w)) * amplitude
		Pattern.PATROL_LINE:
			global_position = origin + Vector3(sin(time * w) * amplitude, 0.0, 0.0)
	var phase := fmod(time, telegraph_interval)
	var was := telegraphing
	telegraphing = phase > telegraph_interval - telegraph_time
	if was and not telegraphing and shooter and shooting_enabled:
		_fire()
	_mat.emission_energy_multiplier = 4.0 if telegraphing else 0.2
	_label.text = "%s  h=%.1fm%s" % [label_text, global_position.y, "  !!" if telegraphing else ""]
