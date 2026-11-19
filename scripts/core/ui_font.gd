class_name UiFont
extends RefCounted
## One CJK-capable font for every UI / Label3D, built from fonts that ship
## with the OS (no font files in the project). On macOS the CJK families
## live in .ttc collections and Godot uses the collection's first face
## (PingFang.ttc starts with PingFang HK, which lacks Simplified glyphs such
## as 远). We therefore load candidate files and keep the first whose used
## face really contains the probe characters (e.g. Hiragino Sans GB).

const NAMES := ["PingFang SC", "Hiragino Sans GB", "Heiti SC", "Microsoft YaHei", "Noto Sans CJK SC",
	"Source Han Sans SC", "WenQuanYi Micro Hei"]
const PROBE := [0x8FDC, 0x7A0B, 0x9635]  # 远 程 阵
static var _font: Font
static var _theme: Theme


static func get_font() -> Font:
	if _font == null:
		_font = _build()
	return _font


static func _build() -> Font:
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(NAMES + ["sans-serif"])
	for family in NAMES:
		var path := OS.get_system_font_path(family)
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) != OK:
			continue
		# the face Godot uses must really contain Simplified glyphs
		var ok := true
		for c: int in PROBE:
			ok = ok and ff.has_char(c)
		if ok:
			ff.fallbacks = [fallback]
			return ff
	return fallback


static func apply_to_root(tree: SceneTree) -> void:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = get_font()
	tree.root.theme = _theme
