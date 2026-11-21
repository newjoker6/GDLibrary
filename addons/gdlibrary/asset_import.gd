@tool
extends RefCounted

const Package := preload("package.gd")

static func ready(path: String) -> bool:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path + ".import") or config.load(path + ".import") != OK:
		return false
	var files: Array = config.get_value("deps", "dest_files", [])
	if files.is_empty():
		return false
	for dest: String in files:
		if not FileAccess.file_exists(dest):
			return false
	return true

static func compile(paths: Dictionary) -> Error:
	if paths.is_empty():
		return OK
	var temp := DirAccess.create_temp("gdlib-import")
	if temp == null:
		return ERR_CANT_CREATE
	var root := temp.get_current_dir()
	var config := ConfigFile.new()
	config.set_value("", "config_version", 5)
	config.set_value("rendering", "renderer/rendering_method", ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"))
	if config.save(root.path_join("project.godot")) != OK:
		return ERR_CANT_CREATE
	for path: String in paths:
		var input := root.path_join(path.trim_prefix("res://"))
		if DirAccess.make_dir_recursive_absolute(input.get_base_dir()) != OK or DirAccess.copy_absolute(ProjectSettings.globalize_path(path), input) != OK:
			return ERR_FILE_CANT_WRITE
		var settings: Dictionary = paths[path]
		var seed := ConfigFile.new()
		seed.set_value("remap", "importer", settings.importer)
		seed.set_value("remap", "type", settings.type)
		seed.set_value("remap", "path", "res://.godot/imported/" + path.get_file() + "-" + path.md5_text() + "." + String(settings.extension))
		if FileAccess.file_exists(path + ".import"):
			var old := ConfigFile.new()
			if old.load(path + ".import") == OK and old.has_section_key("remap", "uid"):
				seed.set_value("remap", "uid", old.get_value("remap", "uid"))
		seed.set_value("deps", "source_file", path)
		for key: String in settings.params:
			seed.set_value("params", key, str_to_var(settings.params[key]))
		if seed.save(input + ".import") != OK:
			return ERR_FILE_CANT_WRITE
	var output := []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path", root, "--editor", "--import"], output, true)
	if status != 0 or "\n".join(output).contains("ERROR:"):
		push_error("Could not import embedded resources.\n" + "\n".join(output))
		return ERR_CANT_CREATE
	var imported := root.path_join(".godot/imported")
	if DirAccess.make_dir_recursive_absolute("res://.godot/imported") != OK:
		return ERR_CANT_CREATE
	for name_ in DirAccess.get_files_at(imported):
		if name_.begins_with("."):
			continue
		var bytes := FileAccess.get_file_as_bytes(imported.path_join(name_))
		if Package.write_bytes("res://.godot/imported/" + name_, bytes) != OK:
			return ERR_FILE_CANT_WRITE
	for path: String in paths:
		var sidecar := root.path_join(path.trim_prefix("res://") + ".import")
		if not FileAccess.file_exists(sidecar) or Package.write_bytes(path + ".import", FileAccess.get_file_as_bytes(sidecar)) != OK or not ready(path):
			return ERR_FILE_CANT_WRITE
	return OK
