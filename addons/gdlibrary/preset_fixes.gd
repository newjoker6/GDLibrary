@tool
extends RefCounted

const Package := preload("package.gd")
const PATH := "res://export_presets.cfg"
const FILTER := "gdlib_api/*.gd"
const ASSETS := "gdlib_assets/*"
const RUNTIME_HELPER := "addons/gdlibrary/assets.gd"

static func missing() -> Dictionary:
	var config := ConfigFile.new()
	var result := {}
	if not FileAccess.file_exists(PATH) or config.load(PATH) != OK:
		return result
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.contains(".options"):
			continue
		if config.get_value(section, "export_filter", "") not in ["scenes", "resources"]:
			continue
		if not covers(String(config.get_value(section, "include_filter", ""))):
			result[section] = config.get_value(section, "name", section)
	return result

static func covers(include_filter: String) -> bool:
	var scripts := false
	var helper := false
	var assets := not DirAccess.dir_exists_absolute("res://gdlib_assets")
	for entry in include_filter.split(",", false):
		var pattern := entry.strip_edges().trim_prefix("res://")
		scripts = scripts or pattern in ["*", "**", "*.gd", "gdlib_api/*", FILTER]
		helper = helper or RUNTIME_HELPER.matchn(pattern) or pattern == "**"
		assets = assets or pattern in ["*", "**", ASSETS]
	return scripts and assets and helper

static func fix(section: String, expected_name: String) -> Error:
	if missing().get(section, "") != expected_name or expected_name.is_empty():
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	var error := config.load(PATH)
	if error != OK:
		return error
	var previous := String(config.get_value(section, "include_filter", "")).strip_edges()
	var patterns := previous.split(",", false)
	for pattern in [FILTER, ASSETS, RUNTIME_HELPER]:
		if not patterns.has(pattern):
			patterns.append(pattern)
	config.set_value(section, "include_filter", ",".join(patterns))
	return Package.write_bytes(PATH, config.encode_to_text().to_utf8_buffer())
