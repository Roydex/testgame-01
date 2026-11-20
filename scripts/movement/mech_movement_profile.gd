class_name MechMovementProfile
extends Resource
## Data-only movement tuning for one mech. All values are PROTOTYPE values
## pending playtest (待测试) — see docs/MOVEMENT_PARAMETERS.md.

@export var display_name: String = "Prototype"

@export_group("Ground")
## Top horizontal speed on the ground (m/s).
@export var ground_max_speed: float = 14.0
## Acceleration along the input direction (m/s²).
@export var ground_accel: float = 50.0
## Deceleration when there is no input (m/s²).
@export var ground_decel: float = 60.0
## How fast sideways velocity is removed when changing direction (m/s²). Higher = tighter turns.
@export var ground_turn_grip: float = 55.0
## Body yaw rotation speed (deg/s).
@export var turn_speed_deg: float = 720.0
## Deceleration applied while above max speed (after a dash) (m/s²).
@export var overspeed_decel: float = 30.0

@export_group("Ground Dash")
@export var ground_dash_speed: float = 30.0
@export var ground_dash_duration: float = 0.32
@export var ground_dash_cost: float = 16.0
@export var dash_cooldown: float = 0.18

@export_group("Jump / Takeoff")
## Initial upward velocity of a jump (m/s).
@export var jump_velocity: float = 9.0
## Time after leaving the ground before thrust can engage (s).
@export var takeoff_time: float = 0.14
## Maximum height above the takeoff point reachable by thrust (m).
@export var max_ascent_height: float = 10.0

@export_group("Air Control")
@export var air_max_speed: float = 13.0
@export var air_accel: float = 24.0
@export var air_decel: float = 10.0
## Sideways velocity removal in the air. Low = drifty / high inertia.
@export var air_turn_grip: float = 18.0
## Air control multiplier when EN is exhausted (limited steering while falling).
@export_range(0.0, 1.0) var exhausted_air_control: float = 0.35

@export_group("Air Dash")
@export var air_dash_speed: float = 32.0
@export var air_dash_duration: float = 0.3
@export var air_dash_cost: float = 28.0
## How much the dash direction can be steered during the dash (deg/s).
@export var air_dash_steer_deg: float = 90.0

@export_group("Vertical Thrust")
@export var ascend_speed: float = 9.0
@export var ascend_accel: float = 30.0
## How fast vertical velocity is braked to zero when hovering (m/s²).
@export var hover_brake: float = 25.0

@export_group("Hover lock / fast descent (2026-11-20)")
## Releasing ascend makes the mech FALL; a double tap of ascend (within
## this window) toggles the hover lock, which holds altitude instead.
@export var hover_double_tap_window: float = 0.3
## Tap descend: committed fast descent until touchdown (no EN, cannot be
## cancelled by ascend). Move input tilts it (lateral speed).
@export var fast_descent_speed: float = 28.0
@export var fast_descent_accel: float = 120.0
@export var fast_descent_lateral_speed: float = 14.0
## Dive dash (descend during an air dash, or dash during a fast descent):
## dash-speed horizontal travel with this sink rate, until touchdown.
@export var dive_descent_speed: float = 22.0

@export_group("Energy (EN)")
@export var max_en: float = 100.0
## Halved 2026-11-20 (user): 20 → 10, ascend 28 → 22.
@export var hover_cost_per_sec: float = 10.0
## Hovering with no move input and little horizontal speed costs this × less.
@export var idle_hover_mult: float = 0.5
@export var idle_hover_speed: float = 3.0
@export var ascend_cost_per_sec: float = 22.0
@export var ground_regen_per_sec: float = 32.0
@export var regen_delay: float = 0.5
## Ground regen multiplier while standing still (grounded, no move input,
## horizontal speed below `idle_regen_speed`). Playtest feedback 2026-11-19.
@export var idle_regen_mult: float = 2.0
@export var idle_regen_speed: float = 1.5
## EN regen while airborne and NOT thrusting (falling; not hovering,
## ascending, dashing or fast-descending), after `regen_delay`. User decision
## 2026-11-20 (AGENT.md §10.2 amended). After EN runs dry the thrusters stay
## locked until touchdown, so regen in the air never re-launches a mech.
@export var air_regen_per_sec: float = 6.0

@export_group("Gravity / Landing")
@export var gravity: float = 24.0
@export var max_fall_speed: float = 40.0
@export var landing_recovery: float = 0.08
## Impact speed (m/s) above which a landing is "hard".
@export var hard_landing_speed: float = 20.0
@export var hard_landing_recovery: float = 0.3
## Horizontal speed multiplier while recovering from a landing.
@export_range(0.0, 1.0) var landing_speed_mult: float = 0.45


func get_max_air_time_estimate() -> float:
	## Upper bound used by tests: hover the full EN bar, then free-fall from the
	## ascent ceiling.
	## Cheapest hover (idle) on a full bar, plus everything that could be
	## regenerated while falling the full height back, plus that fall.
	var cheapest := maxf(hover_cost_per_sec * idle_hover_mult, 0.01)
	var fall_time := sqrt(2.0 * (max_ascent_height + jump_velocity * jump_velocity / (2.0 * gravity)) / gravity)
	var hover_time := (max_en + air_regen_per_sec * fall_time) / cheapest
	return hover_time + fall_time + takeoff_time + 2.0
