class_name Hurtbox
extends Area3D
## Receives hits for its owner (a mech, a turret, a missile). Detection
## queries (melee hitbox sweeps, projectile sweeps, blasts) look for this
## area on CombatTypes.HURTBOX_LAYER. `mech` is the owning damageable.

var mech: Node3D


## Capsule standing on the owner's origin; `center_y` overrides its centre height.
func setup(p_owner: Node3D, radius: float, height: float, center_y: float = -1.0) -> void:
	mech = p_owner
	name = "Hurtbox"
	collision_layer = CombatTypes.HURTBOX_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0)
	cs.shape = cap
	cs.position = Vector3.UP * (height * 0.5 if center_y < 0.0 else center_y)
	add_child(cs)


func set_enabled(on: bool) -> void:
	set_deferred(&"monitorable", on)
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred(&"disabled", not on)
