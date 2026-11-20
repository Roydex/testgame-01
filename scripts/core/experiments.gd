class_name Experiments
extends RefCounted
## Switchable gameplay experiments from playtest round 2 (阶段 3a 第 2 轮).
## They are rules, not "practice" branches: every brain / mech obeys them
## the same way. All default OFF so the grey-box scene, the headless tests
## and the balance simulation keep the accepted behaviour; the skill lab
## turns them on at start and toggles them with F2 / F3 / F4 so the old and
## new feel can be compared. PROTOTYPE values (待测试).

## 速度即伤害: melee hits scale with closing speed, attacks started at dash
## speed keep their momentum, a landed hit can be dash-cancelled and chained.
static var momentum := false
## 近战俯瞰镜头 (id kept as duel_cam): close lock-on rises to a high, wide
## shot that barely turns; parries / ripostes / finishers / judgment get a
## short side cut with slow motion (at most one per 1.5 s).
static var duel_cam := false
## 自由瞄准: ranged weapons fire at the crosshair (with aim assist); the lock
## only frames the camera and steers melee lunges.
static var free_aim := false

const NAMES := {
	&"momentum": "速度即伤害",
	&"duel_cam": "近战俯瞰镜头",
	&"free_aim": "自由瞄准",
}

# --- 速度即伤害
## Closing speed (m/s) at which the bonus starts, and per m/s above it.
const MOMENTUM_SPEED_START := 8.0
const MOMENTUM_PER_MPS := 0.025
const MOMENTUM_MAX_BONUS := 0.6
## Each dash-cancelled hit chained within the window adds this (capped).
const CHAIN_WINDOW := 0.9
const CHAIN_STEP := 0.1
const CHAIN_MAX := 5
## An attack started above this fraction of the ground dash speed keeps
## its momentum: its lunge is at least this share of the current speed.
const DASH_ATTACK_SPEED_FRAC := 0.8
const DASH_ATTACK_CARRY := 0.9

# --- 自由瞄准
## Aim assist: a hostile within this angle of the crosshair ray is snapped to.
const AIM_ASSIST_DEG := 3.5
const AIM_MAX_DISTANCE := 250.0


static func set_all(on: bool) -> void:
	momentum = on
	duel_cam = on
	free_aim = on


static func is_on(id: StringName) -> bool:
	match id:
		&"momentum": return momentum
		&"duel_cam": return duel_cam
		&"free_aim": return free_aim
	return false


static func toggle(id: StringName) -> bool:
	match id:
		&"momentum":
			momentum = not momentum
			return momentum
		&"duel_cam":
			duel_cam = not duel_cam
			return duel_cam
		&"free_aim":
			free_aim = not free_aim
			return free_aim
	return false


## Damage / knockback multiplier for a melee hit at `closing_speed` m/s.
static func momentum_mult(closing_speed: float) -> float:
	if not momentum:
		return 1.0
	return 1.0 + clampf((closing_speed - MOMENTUM_SPEED_START) * MOMENTUM_PER_MPS, 0.0, MOMENTUM_MAX_BONUS)
