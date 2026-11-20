class_name Health
extends Node
## Hit points of one combatant. Damage only arrives through DamageSystem.

signal damaged(amount: float, hp: float, max_hp: float)
signal died

var max_hp: float = 300.0
var hp: float = 300.0
var dead: bool = false
## Practice mode: HP never drops below this (0 = can die).
var min_hp: float = 0.0
## Practice mode: regenerate to full after `regen_delay` s without damage.
var regen_rate: float = 0.0
var regen_delay: float = 4.0
var _since_damage: float = 0.0


func setup(p_max: float) -> void:
	max_hp = p_max
	hp = p_max
	dead = false


func ratio() -> float:
	return hp / maxf(max_hp, 0.001)


func take(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	hp = maxf(hp - amount, min_hp)
	_since_damage = 0.0
	damaged.emit(amount, hp, max_hp)
	if hp <= 0.0:
		dead = true
		died.emit()


## Healing (ultimate regeneration). Never revives.
func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)


func restore() -> void:
	hp = max_hp
	dead = false


func _physics_process(delta: float) -> void:
	_since_damage += delta
	if regen_rate > 0.0 and not dead and hp < max_hp and _since_damage >= regen_delay:
		hp = minf(hp + regen_rate * delta, max_hp)
