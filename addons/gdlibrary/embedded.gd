@tool
extends RefCounted

const ROOT: String = "res://gdlib_assets/"
const FORMATS: Array = ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "hdr", "exr", "wav", "ogg", "mp3", "ttf", "otf", "tscn", "tres", "res", "scn"]

static func supported(path: String) -> bool:
	if path.get_extension().to_lower() not in FORMATS or not path.begins_with("res://"):
		return false
	for segment: String in path.trim_prefix("res://").split("/"):
		if segment.begins_with(".") or not segment.is_valid_filename():
			return false
	return true

static func destination(id: String, path: String) -> String:
	return ROOT + id + "/" + path.trim_prefix("res://")

static func resolve_path(value: String, parent: String) -> String:
	if value.begins_with("uid://"):
		var uid: int = ResourceUID.text_to_id(value)
		return ResourceUID.get_id_path(uid) if ResourceUID.has_id(uid) else value
	return parent.get_base_dir().path_join(value).simplify_path() if value.is_relative_path() else value

static func collect(paths: PackedStringArray, targets: Dictionary, id: String, limit: int) -> Dictionary:
	var files: Dictionary = {}
	var imports: Dictionary = {}
	var total: int = 0
	for path: String in paths:
		if targets.has(path):
			continue
		if not supported(path):
			push_error("Cannot embed %s. Use external asset mode for this format." % path)
			return {"error": ERR_UNAVAILABLE}
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > limit - total:
			return {"error": ERR_PARAMETER_RANGE_ERROR}
		var bytes: PackedByteArray = file.get_buffer(file.get_length())
		if path.get_extension() in ["res", "scn"] and not ResourceLoader.get_dependencies(path).is_empty():
			push_error("Save %s as .tres or .tscn to relocate its dependencies." % path)
			return {"error": ERR_UNAVAILABLE}
		if path.get_extension() in ["tres", "tscn"]:
			var result: Dictionary = relocate(bytes.get_string_from_utf8(), path, paths, targets, id)
			if result.has("error"):
				return result
			bytes = String(result.text).to_utf8_buffer()
		if FileAccess.file_exists(path + ".import"):
			var config: ConfigFile = ConfigFile.new()
			if config.load(path + ".import") != OK:
				return {"error": ERR_INVALID_DATA}
			var importer: String = String(config.get_value("remap", "importer", ""))
			var extension: String = ""
			for key: String in config.get_section_keys("remap"):
				if key == "path" or key.begins_with("path."):
					extension = String(config.get_value("remap", key)).get_extension()
					break
			var params: Dictionary = {}
			if config.has_section("params"):
				for key: String in config.get_section_keys("params"):
					var value: Variant = config.get_value("params", key)
					if typeof(value) == TYPE_OBJECT or (value is String and value.begins_with("res://")):
						push_error("Use external asset mode for importer parameters referencing project resources: " + path)
						return {"error": ERR_UNAVAILABLE}
					params[key] = var_to_str(value)
			var settings: Dictionary = {"importer": importer, "type": config.get_value("remap", "type", ""), "extension": extension, "params": params}
			if not valid_settings(settings):
				return {"error": ERR_UNAVAILABLE}
			imports[path] = settings
		files[path] = bytes
		total += bytes.size()
		if total > limit:
			return {"error": ERR_PARAMETER_RANGE_ERROR}
	return {"files": files, "imports": imports}

static func relocate(source: String, parent: String, paths: PackedStringArray, targets: Dictionary, id: String) -> Dictionary:
	var lines: PackedStringArray = source.split("\n")
	var uid: RegEx = RegEx.create_from_string(' uid="[^"]+"')
	var attribute: RegEx = RegEx.create_from_string(' path="([^"]+)"')
	for i: int in lines.size():
		if lines[i].begins_with("[gd_scene ") or lines[i].begins_with("[gd_resource "):
			lines[i] = uid.sub(lines[i], "")
		elif lines[i].begins_with("[ext_resource "):
			var field: RegExMatch = attribute.search(lines[i])
			if field == null:
				return {"error": ERR_INVALID_DATA}
			var path: String = resolve_path(field.get_string(1), parent)
			if not paths.has(path) and not targets.has(path):
				return {"error": ERR_FILE_MISSING_DEPENDENCIES}
			var replacement: String = targets.get(path, destination(id, path))
			lines[i] = uid.sub(lines[i].left(field.get_start(1)) + replacement + lines[i].substr(field.get_end(1)), "")
	return {"text": "\n".join(lines)}

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary or not value.get("importer") in ["texture", "wav", "mp3", "oggvorbisstr", "font_data_dynamic"]:
		return false
	if not value.get("type") is String or not value.get("extension") is String or not String(value.extension).is_valid_ascii_identifier() or not value.get("params") is Dictionary:
		return false
	for key: Variant in value.params:
		if not key is String or not value.params[key] is String:
			return false
	return true
