class_name Health
extends Node
## Hit points of one combatant. Damage only arrives through DamageSystem.

signal damaged(amount: float, hp: float, max_hp: float)
signal died

var max_hp: float = 300.0
var hp: float = 300.0
var dead: bool = false


func setup(p_max: float) -> void:
	max_hp = p_max
	hp = p_max
	dead = false


func ratio() -> float:
	return hp / maxf(max_hp, 0.001)


func take(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	damaged.emit(amount, hp, max_hp)
	if hp <= 0.0:
		dead = true
		died.emit()
