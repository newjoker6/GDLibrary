@tool
extends EditorImportPlugin

const Package = preload("package.gd")

func _get_importer_name() -> String:
	return "gdlibrary.package"

func _get_visible_name() -> String:
	return "GDScript Library"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gdlib"])

func _get_save_extension() -> String:
	return "res"

func _get_resource_type() -> String:
	return "Resource"

func _get_preset_count() -> int:
	return 0

func _get_import_options(_path: String, _preset: int) -> Array[Dictionary]:
	return []

func _import(source_file: String, save_path: String, _options: Dictionary, _variants: Array[String], _gen_files: Array[String]) -> Error:
	var info: Dictionary = Package.read_package(source_file)
	var output: String = save_path + ".res"
	if info.is_empty():
		if FileAccess.file_exists(output):
			DirAccess.remove_absolute(output)
		push_error("GDLibrary could not read or verify " + source_file)
		return ERR_FILE_CORRUPT
	for member: Dictionary in info.members:
		member.erase("body")
	info["embedded_paths"] = PackedStringArray(info.get("embedded", {}).keys())
	info.erase("embedded")
	info.erase("api")
	var marker: Resource = Resource.new()
	marker.set_meta("gdlib", info)
	return ResourceSaver.save(marker, output)
