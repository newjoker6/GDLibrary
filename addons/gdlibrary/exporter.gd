@tool
extends EditorExportPlugin

const Package = preload("package.gd")

var catalog: RefCounted

func _get_name() -> String:
	return "GDLibrary"

func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	var preset: EditorExportPreset = get_export_preset()
	if preset != null and preset.get_export_filter() in [EditorExportPreset.EXPORT_SELECTED_SCENES, EditorExportPreset.EXPORT_SELECTED_RESOURCES]:
		if not preload("preset_fixes.gd").covers(preset.get_include_filter()):
			get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_WARNING, "GDLibrary", "This preset may omit public classes. Open Project → Tools → GDLibrary Export Presets… and choose Fix Export Preset.")
	if catalog != null:
		for issue: String in catalog.get("issues"):
			get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "GDLibrary", issue)
	var asset_index: String = preload("assets.gd").INDEX
	if FileAccess.file_exists(asset_index):
		add_file(asset_index, FileAccess.get_file_as_bytes(asset_index), false)
	if not FileAccess.file_exists(Package.INDEX):
		return
	var emitted: Dictionary = {}
	for archive: String in JSON.parse_string(FileAccess.get_file_as_string(Package.INDEX)):
		if emitted.has(archive):
			continue
		var zip: ZIPReader = ZIPReader.new()
		if zip.open(archive) != OK:
			get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "GDLibrary", "Invalid cached library: " + archive)
			continue
		for entry: String in zip.get_files():
			if entry.ends_with(".gd"):
				add_file("res://" + entry, zip.read_file(entry), false)
		zip.close()
		emitted[archive] = true

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.ends_with(".gdlib.tres") or path.get_extension() == "gdlib" or (path.begins_with("res://addons/gdlibrary/") and path not in ["res://addons/gdlibrary/mounts.gd", "res://addons/gdlibrary/assets.gd"]):
		skip()
