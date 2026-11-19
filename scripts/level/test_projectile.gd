class_name TestProjectile
extends Node3D
## Grey-box TEST FIXTURE for M04 (air evasion). Not a weapon system: no
## damage, it only records whether a mech was hit or the shot was dodged.
## Straight line, constant speed, swept with a ray each tick (no tunnelling).

static var hits: int = 0
static var dodges: int = 0
static var last_result: String = ""
static var debug_print: bool = false

var velocity: Vector3
var max_range: float = 160.0
var shooter: Node
var radius: float = 0.4
var _travelled := 0.0


static func reset_stats() -> void:
	hits = 0
	dodges = 0
	last_result = ""


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	add_child(mi)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col := hit.collider as Node
		if col is MechMotor and TeamRules.is_hostile(shooter, col):
			hits += 1
			last_result = "HIT %s" % col.name
			col.set_meta(&"test_hits", int(col.get_meta(&"test_hits", 0)) + 1)
		else:
			dodges += 1
			last_result = "dodged (hit %s)" % (col.name if col else "?")
		if debug_print:
			print("[proj] %s at %s" % [last_result, (hit.position as Vector3).snapped(Vector3.ONE * 0.1)])
		queue_free()
		return
	global_position = to
	_travelled += velocity.length() * delta
	if _travelled > max_range:
		dodges += 1
		last_result = "dodged (out of range)"
		queue_free()
