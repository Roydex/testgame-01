extends Node
## Global combat event bus (autoload "CombatEvents"). Detection and damage
## resolution emit; feedback, HUD, logs and tests listen. Keeps hit logic
## and presentation decoupled.

signal hit_resolved(hit: HitInfo)
signal telegraph(attacker: Node3D, attack: AttackDefinition, duration: float)
signal attack_started(attacker: Node3D, attack: AttackDefinition)
## The attack's active (damaging) phase begins: swing sound, weapon trail.
signal attack_active(attacker: Node3D, attack: AttackDefinition)
signal parried(defender: Node3D, attacker: Node3D, was_projectile: bool)
signal mech_died(mech: Node3D)
signal ultimate_phase(mech: Node3D, phase: String)

## Rolling damage log for the debug overlay.
var log_lines: PackedStringArray = []


func _ready() -> void:
	hit_resolved.connect(_on_hit)


func _on_hit(hit: HitInfo) -> void:
	var line := "%s → %s  %s  %s %.1f" % [
		hit.attacker.name if hit.attacker else "?", hit.victim.name if hit.victim else "?",
		hit.attack.display_name if hit.attack else "?", CombatTypes.RESULT_NAMES[hit.result], hit.final_damage]
	log_lines.insert(0, line)
	if log_lines.size() > 8:
		log_lines.resize(8)
