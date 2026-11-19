class_name Hurtbox
extends Area3D
## Receives hits for its mech. Detection queries (melee hitbox sweeps and
## projectile rays) look for this area on CombatTypes.HURTBOX_LAYER.

var mech: MechMotor


func setup(p_mech: MechMotor, radius: float, height: float) -> void:
	mech = p_mech
	name = "Hurtbox"
	collision_layer = CombatTypes.HURTBOX_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	cs.shape = cap
	cs.position = Vector3.UP * height * 0.5
	add_child(cs)


func set_enabled(on: bool) -> void:
	set_deferred(&"monitorable", on)
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred(&"disabled", not on)
