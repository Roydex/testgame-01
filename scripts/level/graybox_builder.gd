class_name GrayboxBuilder
extends RefCounted
## Builds the movement grey-box test arena (prototype only, NOT one of the
## three final maps). Geometry is code-built so tests and the playable scene
## use the exact same layout. Coordinates in metres; ground top at y = 0.

const GRID_SHADER := preload("res://shaders/graybox_grid.gdshader")
const CEILING_Y := 40.0
const HALF_EXTENT := 100.0

## Named reference points used by tests and the debug HUD.
const POINTS := {
	"spawn": Vector3(0, 0.2, 30),
	"steps_base": Vector3(-25, 0.2, 0),
	"tower_mid_top": Vector3(54, 8.2, -30),
	"tower_a_top": Vector3(40, 16.2, -30),
	"tower_b_top": Vector3(40, 16.2, -70),
	"bridge_mid": Vector3(40, 16.2, -50),
	"slab_under": Vector3(-40, 0.2, -50),
	"slab_top": Vector3(-40, 8.6, -50),
	"corridor_in": Vector3(-40, 0.2, 52),
	"wall_front": Vector3(0, 0.2, -30),
}


static func build(root: Node3D, with_targets: bool = true) -> Dictionary:
	var info := {}
	var world := Node3D.new()
	world.name = "Graybox"
	root.add_child(world)

	var bounds := MapBounds.new()
	bounds.name = "MapBounds"
	bounds.ceiling_y = CEILING_Y
	bounds.kill_y = -30.0
	bounds.half_extent = Vector2(HALF_EXTENT - 1.0, HALF_EXTENT - 1.0)
	world.add_child(bounds)
	info.bounds = bounds

	var c_floor := Color(0.5, 0.52, 0.55)
	var c_step := Color(0.62, 0.58, 0.5)
	var c_tower := Color(0.45, 0.5, 0.6)
	var c_wall := Color(0.6, 0.45, 0.42)
	var c_slab := Color(0.48, 0.58, 0.5)

	# --- flat ground
	_box(world, "Ground", Vector3(HALF_EXTENT * 2, 1, HALF_EXTENT * 2), Vector3(0, -0.5, 0), c_floor)

	# --- steps of increasing height (1 / 2 / 4 / 7 / 10 m) + walkable ramp
	var heights := [1.0, 2.0, 4.0, 7.0, 10.0]
	for i in heights.size():
		var h: float = heights[i]
		_box(world, "Step_%dm" % int(h), Vector3(8, h, 8), Vector3(-30 - i * 8, h * 0.5, 0), c_step)
	_ramp(world, "Ramp_4m", Vector3(8, 0.5, 14), Vector3(-30, 2.0, 14), deg_to_rad(-16.0), c_step)
	_box(world, "RampTop", Vector3(8, 4, 6), Vector3(-30, 2, 23.5), c_step)

	# --- towers + bridge (mid tower is the stepping stone: 0 -> 8 -> 16 m)
	_box(world, "TowerMid_8m", Vector3(8, 8, 8), Vector3(54, 4, -30), c_tower)
	_box(world, "TowerA_16m", Vector3(12, 16, 12), Vector3(40, 8, -30), c_tower)
	_box(world, "TowerB_16m", Vector3(12, 16, 12), Vector3(40, 8, -70), c_tower)
	_box(world, "Bridge", Vector3(4, 0.6, 28), Vector3(40, 15.7, -50), c_step)

	# --- walls: thick (1 m) and thin (0.3 m), 12 m tall
	_box(world, "WallThick", Vector3(40, 12, 1), Vector3(0, 6, -40), c_wall)
	_box(world, "WallThin", Vector3(40, 12, 0.3), Vector3(0, 6, -55), c_wall)

	# --- two-storey slab structure: 0.4 m slab at 8 m, 0.3 m slab at 16 m
	for x in [-49.0, -31.0]:
		for z in [-59.0, -41.0]:
			_box(world, "Pillar", Vector3(1.5, 16, 1.5), Vector3(x, 8, z), c_slab)
	_box(world, "SlabLow", Vector3(20, 0.4, 20), Vector3(-40, 8.2, -50), c_slab)
	_box(world, "SlabHigh", Vector3(20, 0.3, 20), Vector3(-40, 16.15, -50), c_slab)

	# --- narrow covered corridor: 3.2 m wide, 6 m tall, 16 m long
	_box(world, "CorridorL", Vector3(1, 6, 16), Vector3(-42.1, 3, 52), c_wall)
	_box(world, "CorridorR", Vector3(1, 6, 16), Vector3(-37.9, 3, 52), c_wall)
	_box(world, "CorridorRoof", Vector3(5.2, 0.5, 16), Vector3(-40, 6.25, 52), c_wall)

	# --- boundary walls up past the flight ceiling + ceiling marker
	var e := HALF_EXTENT
	var bh := CEILING_Y + 10.0
	_box(world, "BoundN", Vector3(e * 2, bh, 1), Vector3(0, bh * 0.5, -e), c_wall, false)
	_box(world, "BoundS", Vector3(e * 2, bh, 1), Vector3(0, bh * 0.5, e), c_wall, false)
	_box(world, "BoundW", Vector3(1, bh, e * 2), Vector3(-e, bh * 0.5, 0), c_wall, false)
	_box(world, "BoundE", Vector3(1, bh, e * 2), Vector3(e, bh * 0.5, 0), c_wall, false)
	var ceil_mesh := MeshInstance3D.new()
	ceil_mesh.name = "CeilingMarker"
	var pm := PlaneMesh.new()
	pm.size = Vector2(e * 2, e * 2)
	pm.flip_faces = true
	ceil_mesh.mesh = pm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1.0, 0.3, 0.2, 0.08)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ceil_mesh.material_override = cm
	ceil_mesh.position = Vector3(0, CEILING_Y, 0)
	world.add_child(ceil_mesh)

	# --- environment
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 250.0
	world.add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)

	info.targets = []
	if with_targets:
		info.targets = _targets(world)
	return info


static func _targets(world: Node3D) -> Array:
	var out := []
	var t1 := _target(world, "T1 low-hover", Vector3(0, 6, -15), TestTarget.Pattern.STATIC, 0, 1)
	t1.shooter = true
	out.append(t1)
	out.append(_target(world, "T2 high", Vector3(20, 26, -10), TestTarget.Pattern.STATIC, 0, 1))
	var t3 := _target(world, "T3 bobbing", Vector3(-15, 18, -20), TestTarget.Pattern.VERTICAL_SINE, 12, 7)
	t3.shooter = true
	out.append(t3)
	out.append(_target(world, "T4 orbit", Vector3(0, 14, 0), TestTarget.Pattern.CIRCLE, 35, 24))
	out.append(_target(world, "T5 ground", Vector3(-10, 1.6, 12), TestTarget.Pattern.STATIC, 0, 1))
	out.append(_target(world, "T6 tower", Vector3(40, 18, -70), TestTarget.Pattern.STATIC, 0, 1))
	return out


static func _target(world: Node3D, label: String, pos: Vector3, pattern: int, amp: float, period: float) -> TestTarget:
	var t := TestTarget.new()
	t.name = label.replace(" ", "_")
	t.label_text = label
	t.pattern = pattern
	t.amplitude = amp
	t.period = period
	t.position = pos
	world.add_child(t)
	return t


static func _box(parent: Node3D, n: String, size: Vector3, pos: Vector3, color: Color, visible_mesh: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	if visible_mesh:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var mat := ShaderMaterial.new()
		mat.shader = GRID_SHADER
		mat.set_shader_parameter(&"base_color", color)
		mat.set_shader_parameter(&"line_color", color.darkened(0.45))
		mi.material_override = mat
		body.add_child(mi)
	parent.add_child(body)
	return body


static func _ramp(parent: Node3D, n: String, size: Vector3, pos: Vector3, pitch: float, color: Color) -> void:
	var b := _box(parent, n, size, pos, color)
	b.rotation.x = pitch
