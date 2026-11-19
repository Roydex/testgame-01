extends Node
## Registers the prototype input map at startup so bindings live in one
## readable place (instead of serialized InputEvents in project.godot).

const KEY_BINDINGS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump_ascend": [KEY_SPACE],
	&"descend": [KEY_C, KEY_CTRL],
	&"dash": [KEY_SHIFT],
	&"lock_toggle": [KEY_Q],
	&"camera_zoom": [KEY_Z],
	&"target_next": [KEY_E],
	&"target_prev": [KEY_R],
	&"ui_release_mouse": [KEY_ESCAPE],
	&"debug_toggle_hud": [KEY_F1],
	&"debug_cycle_profile": [KEY_F2],
	&"debug_stagger": [KEY_F3],
	&"debug_action": [KEY_F4],
	&"debug_reset": [KEY_F5],
	&"debug_kill_target": [KEY_K],
	&"debug_toggle_shooters": [KEY_F6],
}

const MOUSE_BINDINGS := {
	&"lock_toggle": [MOUSE_BUTTON_MIDDLE],
	&"target_next": [MOUSE_BUTTON_WHEEL_DOWN],
	&"target_prev": [MOUSE_BUTTON_WHEEL_UP],
}


func _init() -> void:
	register()


static func register() -> void:
	for action: StringName in KEY_BINDINGS:
		_ensure_action(action)
		for key: int in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: StringName in MOUSE_BINDINGS:
		_ensure_action(action)
		for button: int in MOUSE_BINDINGS[action]:
			var mev := InputEventMouseButton.new()
			mev.button_index = button
			InputMap.action_add_event(action, mev)


static func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
