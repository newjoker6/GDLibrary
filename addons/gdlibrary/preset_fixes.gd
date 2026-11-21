@tool
extends RefCounted

const Package = preload("package.gd")
const PATH: String = "res://export_presets.cfg"
const FILTER: String = "gdlib_api/*.gd"
const ASSETS: String = "gdlib_assets/*"
const RUNTIME_HELPER: String = "addons/gdlibrary/assets.gd"

static func missing() -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var result: Dictionary = {}
	if not FileAccess.file_exists(PATH) or config.load(PATH) != OK:
		return result
	for section: String in config.get_sections():
		if not section.begins_with("preset.") or section.contains(".options"):
			continue
		if config.get_value(section, "export_filter", "") not in ["scenes", "resources"]:
			continue
		if not covers(String(config.get_value(section, "include_filter", ""))):
			result[section] = config.get_value(section, "name", section)
	return result

static func covers(include_filter: String) -> bool:
	var scripts: bool = false
	var helper: bool = false
	var assets: bool = not DirAccess.dir_exists_absolute("res://gdlib_assets")
	for entry: String in include_filter.split(",", false):
		var pattern: String = entry.strip_edges().trim_prefix("res://")
		scripts = scripts or pattern in ["*", "**", "*.gd", "gdlib_api/*", FILTER]
		helper = helper or RUNTIME_HELPER.matchn(pattern) or pattern == "**"
		assets = assets or pattern in ["*", "**", ASSETS]
	return scripts and assets and helper

static func fix(section: String, expected_name: String) -> Error:
	if missing().get(section, "") != expected_name or expected_name.is_empty():
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(PATH)
	if error != OK:
		return error
	var previous: String = String(config.get_value(section, "include_filter", "")).strip_edges()
	var patterns: PackedStringArray = previous.split(",", false)
	for pattern: String in [FILTER, ASSETS, RUNTIME_HELPER]:
		if not patterns.has(pattern):
			patterns.append(pattern)
	config.set_value(section, "include_filter", ",".join(patterns))
	return Package.write_bytes(PATH, config.encode_to_text().to_utf8_buffer())
