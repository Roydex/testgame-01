class_name PauseMenu
extends CanvasLayer
## Pause menu (Esc / P). Pauses the whole SceneTree: every gameplay node uses
## the default INHERIT process mode, so motors, combat, projectiles, FX tweens
## and timers freeze. This layer runs with PROCESS_MODE_ALWAYS.

signal resumed
signal restart_requested
signal practice_toggle_requested

const CONTROLS_TEXT := """移动  WASD        视角  鼠标        跳跃 / 按住上升  Space
下降  C / Ctrl      冲刺  Shift       锁定  Q / 鼠标中键      切换目标  E / R / 滚轮
攻击  左键          格挡  右键按住     招架  F
突进斩 X            大招  V            镜头距离  Z
暂停  Esc / P       回满  F5           重开  F7           练习 / 实战  F12
陪练机阵营  F8      陪练机模式  F9 / F11      HP 降到 29%  F10      调试面板  F1"""

var _root: Control
var _title: Label
var _mode_label: Label
var _controls: Label
var _practice_button: Button
var _was_captured := false
## Returns the current mode text ("练习模式" / "实战模式"), set by the scene.
var mode_text_provider: Callable


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	sb.border_color = Color(1.0, 0.93, 0.72, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override(&"separation", 12)
	vb.custom_minimum_size = Vector2(380, 0)
	panel.add_child(vb)
	_title = _label(vb, "暂停", 40)
	_mode_label = _label(vb, "", 16)
	_button(vb, "继续游戏", resume)
	_button(vb, "重新开始", func(): _close(); restart_requested.emit())
	_practice_button = _button(vb, "切换 练习 / 实战", func(): practice_toggle_requested.emit(); _refresh())
	_button(vb, "操作说明", func(): _controls.visible = not _controls.visible)
	_button(vb, "退出游戏", func(): get_tree().quit())
	_controls = _label(vb, CONTROLS_TEXT, 14)
	_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_controls.visible = false
	_root.visible = false


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", UiFont.get_font())
	l.add_theme_font_size_override(&"font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override(&"font", UiFont.get_font())
	b.add_theme_font_size_override(&"font_size", 20)
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if is_open():
			resume()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open():
		return
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_controls.visible = false
	_refresh()
	_root.visible = true
	(_root.find_children("*", "Button", true, false)[0] as Button).grab_focus()


func resume() -> void:
	if not is_open():
		return
	_close()
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()


func _close() -> void:
	_root.visible = false
	get_tree().paused = false


func _refresh() -> void:
	_mode_label.text = mode_text_provider.call() if mode_text_provider.is_valid() else ""
