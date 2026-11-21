@tool
class_name GDLibraryAssets
extends RefCounted

const INDEX: String = "res://.godot/gdlib/asset_roots.json"
static var initialized: bool = false
static var embedded_packages: Dictionary = {}

static func path(package_id: String, relative_path: String) -> String:
	if not package_id.is_valid_ascii_identifier() or relative_path.is_empty() or not relative_path.is_relative_path() or relative_path.contains(":") or relative_path.contains("\\"):
		return ""
	for segment: String in relative_path.split("/"):
		if not segment.is_valid_filename() or segment.begins_with("."):
			return ""
	if not initialized:
		read_index()
	if embedded_packages.has(package_id):
		return "res://gdlib_assets/" + package_id + "/" + relative_path
	return "res://" + relative_path

static func read_index() -> void:
	initialized = true
	embedded_packages.clear()
	if FileAccess.file_exists(INDEX):
		var packages: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if packages is Array:
			for id: String in packages:
				embedded_packages[id] = true
