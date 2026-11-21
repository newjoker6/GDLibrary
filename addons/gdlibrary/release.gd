extends SceneTree

const Catalog = preload("catalog.gd")
const Package = preload("package.gd")
const TOOL_DIR: String = "res://addons/gdlibrary"
var scratch: String = ""

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] == "pack":
		if args.size() < 3:
			printerr("Usage: pack <definition.gdlib.tres> <output.gdlib> [--baseline <previous.gdlib>] [--allow-api-changes]")
			quit(2)
			return
		if not engine(["--path", absolute("res://"), "--editor", "--import"]):
			quit(1)
			return
		var command: PackedStringArray = PackedStringArray(["--headless", "--path", absolute("res://"), "--script", TOOL_DIR + "/pack_command.gd", "--"])
		command.append_array(args.slice(1))
		var output: Array = []
		var status: int = OS.execute(OS.get_executable_path(), command, output, true)
		var log_text: String = "\n".join(output)
		print(log_text.strip_edges())
		quit(1 if status < 0 or (status == 0 and log_text.contains("ERROR:")) else status)
		return
	if args.size() != 3 or args[0] not in ["export-pack", "test"]:
		printerr("Usage: export-pack <preset> <output.pck> | test <package.gdlib> <assets-root>")
		quit(2)
		return
	var temp: DirAccess = DirAccess.create_temp("gdlib-release", true)
	if temp == null:
		printerr("Could not create a temporary directory.")
		quit(1)
		return
	scratch = temp.get_current_dir()
	if temp.make_dir("runtime") != OK:
		remove_tree(scratch)
		quit(1)
		return
	var ok: bool = false
	if args[0] == "test":
		ok = clean_test(ProjectSettings.localize_path(absolute(args[1])), absolute(args[2]))
	else:
		ok = export_project(args[1], absolute(args[2]))
	remove_tree(scratch)
	if ok:
		print("GDLibrary verification passed.")
	quit(0 if ok else 1)

func absolute(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(path).simplify_path()

func engine(args: PackedStringArray, expected: String = "") -> bool:
	var output: Array = []
	var command: PackedStringArray = PackedStringArray(["--headless"])
	command.append_array(args)
	var status: int = OS.execute(OS.get_executable_path(), command, output, true)
	var log_text: String = "\n".join(output)
	if status != 0 or log_text.contains("ERROR:") or (not expected.is_empty() and not log_text.contains(expected)):
		printerr(log_text)
		return false
	return true

func export_project(preset: String, output: String) -> bool:
	if output.get_extension().to_lower() != "pck":
		printerr("Choose a .pck output path.")
		return false
	var project: String = absolute("res://")
	if not engine(["--path", project, "--editor", "--import"]):
		return false
	var catalog: Catalog = Catalog.new()
	catalog.bootstrap()
	if not catalog.issues.is_empty():
		printerr("\n".join(catalog.issues))
		return false
	var probe: String = write_probe(catalog.package_infos.values())
	if probe.is_empty() or not engine(["--path", project, "--script", probe, "--quit-after", "300"], "GDLIB_PROBE_OK"):
		return false
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK:
		return false
	var staging: String = output.get_base_dir().path_join(".gdlib-%s.pck" % ResourceUID.create_id())
	var ok: bool = engine(["--path", project, "--export-pack", preset, staging])
	if ok:
		ok = FileAccess.file_exists(staging) and engine(["--path", scratch.path_join("runtime"), "--main-pack", staging, "--script", probe, "--quit-after", "300"], "GDLIB_PROBE_OK")
	if ok:
		ok = DirAccess.rename_absolute(staging, output) == OK
	if FileAccess.file_exists(staging):
		DirAccess.remove_absolute(staging)
	if not ok:
		printerr("GDLibrary did not publish " + output)
	return ok

func write_probe(packages: Array) -> String:
	var lines: PackedStringArray = PackedStringArray(["extends RefCounted", "static func usable(script: Script) -> bool:", "\treturn script.can_instantiate() or script.is_abstract()", "static func verify() -> bool:"])
	for info: Dictionary in packages:
		for member: Dictionary in info.members:
			if member.get("private", false):
				continue
			var name_: String = (String(info.id) + "." if info.get("scoped", false) else "") + String(member.name)
			lines.append("\tif not usable(%s):" % name_)
			lines.append("\t\tprinterr(" + JSON.stringify("Unusable library class " + name_) + ")")
			lines.append("\t\treturn false")
		var resources: PackedStringArray = PackedStringArray(info.get("assets", []))
		for path: String in info.get("embedded", {}):
			resources.append(Package.Embedded.destination(info.id, path))
		for resource: String in resources:
			lines.append("\tif load(" + JSON.stringify(resource) + ") == null:")
			lines.append("\t\treturn false")
	lines.append("\treturn true")
	var path: String = scratch.path_join("verify.gd")
	if Package.write_bytes(path, ("\n".join(lines) + "\n").to_utf8_buffer()) != OK:
		return ""
	var runner: String = scratch.path_join("runner.gd")
	var source: String = """extends SceneTree

func _init() -> void:
	check.call_deferred()

func check() -> void:
	var probe: GDScript = load(%s) as GDScript
	if probe and probe.can_instantiate() and probe.call("verify"):
		print("GDLIB_PROBE_OK")
		quit(0)
	else:
		quit(1)
""" % JSON.stringify(path)
	return runner if Package.write_bytes(runner, source.to_utf8_buffer()) == OK else ""

func clean_test(package: String, assets_root: String) -> bool:
	var groups: Dictionary = {}
	var installed: bool = preload("validation.gd").imported_destination(package)
	if installed:
		var catalog: Catalog = Catalog.new()
		catalog.scan_disk("res://", groups, {})
	else:
		var folder: String = package.get_base_dir()
		index_distribution(folder, groups)
		var libraries: String = folder.path_join("libraries")
		if DirAccess.dir_exists_absolute(libraries):
			index_distribution(libraries, groups)
	var root: String = scratch.path_join("consumer")
	if not copy_addon(root):
		return false
	var config: ConfigFile = ConfigFile.new()
	config.set_value("", "config_version", 5)
	config.set_value("application", "config/name", "GDLibrary Consumer Test")
	config.set_value("editor_plugins", "enabled", PackedStringArray([TOOL_DIR + "/plugin.cfg"]))
	config.set_value("autoload", "GDLibraryMounts", "*" + TOOL_DIR + "/mounts.gd")
	if config.save(root.path_join("project.godot")) != OK:
		return false
	var queue: PackedStringArray = PackedStringArray([package])
	var packages: Dictionary = {}
	while not queue.is_empty():
		var path: String = queue[queue.size() - 1]
		queue.resize(queue.size() - 1)
		var info: Dictionary = Package.read_package(path)
		if info.is_empty():
			printerr("Unreadable package " + path)
			return false
		if packages.has(info.id):
			continue
		packages[info.id] = info
		if not copy_input(path, root.path_join("libraries/" + String(info.id) + ".gdlib")):
			return false
		for member: Dictionary in info.members:
			member.erase("body")
		for asset: String in info.get("assets", []):
			var relative: String = asset.trim_prefix("res://")
			if relative.begins_with("addons/gdlibrary/") or relative.begins_with("gdlib_api/") or relative.ends_with(".gdlib"):
				printerr("Asset conflicts with the test project: " + asset)
				return false
			var source: String = assets_root.path_join(relative)
			if not copy_input(source, root.path_join(relative)):
				return false
			for sidecar: String in [".import", ".uid"]:
				if FileAccess.file_exists(source + sidecar) and not copy_input(source + sidecar, root.path_join(relative + sidecar)):
					return false
		for dep: String in info.requires:
			if packages.has(dep):
				continue
			var copies: Array = groups.get(dep, [])
			if copies.size() != 1:
				printerr("%s needs exactly one package with ID %s in %s." % [info.id, dep, "the project" if installed else "the distribution"])
				return false
			queue.append(copies[0].path)
	if not engine(["--path", root, "--editor", "--import"]):
		return false
	var probe: String = write_probe(packages.values())
	if probe.is_empty() or not engine(["--path", root, "--script", probe, "--quit-after", "300"], "GDLIB_PROBE_OK"):
		return false
	var preset: ConfigFile = ConfigFile.new()
	preset.set_value("preset.0", "name", "Consumer")
	preset.set_value("preset.0", "platform", "Linux")
	preset.set_value("preset.0", "export_filter", "all_resources")
	preset.set_value("preset.0", "include_filter", "gdlib_api/*.gd")
	preset.set_value("preset.0", "exclude_filter", "")
	preset.set_value("preset.0.options", "binary_format/architecture", "x86_64")
	if preset.save(root.path_join("export_presets.cfg")) != OK:
		return false
	var output: String = scratch.path_join("consumer.pck")
	if not engine(["--path", root, "--export-pack", "Consumer", output]):
		return false
	return engine(["--path", scratch.path_join("runtime"), "--main-pack", output, "--script", probe, "--quit-after", "300"], "GDLIB_PROBE_OK")

func index_distribution(folder: String, groups: Dictionary) -> void:
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() != "gdlib":
			continue
		var path: String = folder.path_join(file)
		var info: Dictionary = Package.read_package(path)
		if not info.is_empty():
			if not groups.has(info.id):
				groups[info.id] = []
			groups[info.id].append({"path": path})

func copy_input(source: String, target: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) == OK and DirAccess.copy_absolute(absolute(source), target) == OK:
		return true
	printerr("Could not copy required file: " + source)
	return false

func copy_addon(root: String) -> bool:
	for filename: String in DirAccess.get_files_at(TOOL_DIR):
		if not copy_input(TOOL_DIR.path_join(filename), root.path_join("addons/gdlibrary").path_join(filename)):
			return false
	return true

func remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var child: String = path.path_join(entry)
		if dir.current_is_dir() and not dir.is_link(entry):
			remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
