extends Node

const INDEX: String = "res://.godot/gdlib/mounts.json"

func _init() -> void:
	if not FileAccess.file_exists(INDEX):
		return
	var archives: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not archives is Array:
		push_error("GDLibrary could not read the package index.")
		return
	for archive: String in archives:
		if not ProjectSettings.load_resource_pack(archive, false):
			push_error("GDLibrary could not mount " + archive)
