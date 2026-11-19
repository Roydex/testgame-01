extends Node
## Loads every GDScript in scripts/ and tests/ inside the full project
## context (autoloads available) and exits 0 if all compile, 2 otherwise.

func _ready() -> void:
	var bad := 0
	var files := _collect("res://scripts") + _collect("res://tests")
	for f in files:
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate():
			print("PARSE ERROR in ", f)
			bad += 1
	print("checked %d scripts, %d with errors" % [files.size(), bad])
	get_tree().quit(2 if bad > 0 else 0)


func _collect(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_collect(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
