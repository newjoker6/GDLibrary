@tool
extends RefCounted

const AssetInstall = preload("asset_install.gd")
const Package = preload("package.gd")
const API_DIR: String = "res://gdlib_api"
const NAMESPACE_WARNING_IGNORE: String = '@warning_ignore_start("shadowed_global_identifier")'

var issues: PackedStringArray = PackedStringArray()
var touched: PackedStringArray = PackedStringArray()
var cache: Dictionary = {}
var status: PackedStringArray = PackedStringArray()
var providers: Dictionary = {}
var package_states: Dictionary = {}
var package_infos: Dictionary = {}
signal catalog_changed
var package_ids: PackedStringArray = PackedStringArray()

func refresh(filesystem: EditorFileSystem) -> bool:
	issues.clear()
	var groups: Dictionary = {}
	var scripts: Dictionary = {}
	collect(filesystem.get_filesystem(), groups, scripts)
	return apply(groups, scripts)

func apply(groups: Dictionary, scripts: Dictionary) -> bool:
	touched.clear()
	var installed_assets: AssetInstall = AssetInstall.new()
	var wanted: Dictionary = {}
	var archives: PackedStringArray = PackedStringArray()
	var available: Dictionary = {}
	var owners: Dictionary = {}
	var blocked: Dictionary = {}
	var keys: Array = groups.keys()
	keys.sort()
	status.clear()
	providers.clear()
	package_states.clear()
	package_infos.clear()
	package_ids = PackedStringArray(keys)
	for id: String in keys:
		var copies: Array = groups[id]
		if copies.size() != 1:
			issues.append("Multiple packages declare ID '%s': %s" % [id, ", ".join(copies.map(func(item: Dictionary) -> String: return item.path))])
			blocked[id] = true
			continue
		var library: Dictionary = copies[0]
		package_infos[id] = library
		for member: Dictionary in exported_globals(library):
			if member.get("private", false):
				continue
			var key: String = String(member.name).to_lower()
			if not owners.has(key):
				owners[key] = []
			owners[key].append(id)
			if owners[key].size() == 1:
				providers[member.name] = id
			else:
				providers.erase(member.name)
	for id: String in keys:
		if blocked.has(id):
			continue
		var library: Dictionary = groups[id][0]
		for member: Dictionary in exported_globals(library):
			if member.get("private", false):
				continue
			var name_: String = member.name
			var key: String = name_.to_lower()
			var output: String = API_DIR.path_join(name_ + ".gd")
			var matching_author: bool = not library.get("scoped", false) and scripts.has(key) and same_source(scripts[key], member)
			var conflicting_source: bool = scripts.has(key) and not matching_author
			if owners[key].size() > 1 or conflicting_source or ClassDB.class_exists(name_) or ProjectSettings.has_setting("autoload/" + name_):
				issues.append("%s cannot register '%s' because another definition exists." % [id, name_])
				blocked[id] = true
			elif FileAccess.file_exists(output) and not is_binding(output) and String(scripts.get(key, "")) != output:
				issues.append("%s cannot replace the existing file %s." % [id, output])
				blocked[id] = true
		for asset: String in library.get("assets", []):
			if not FileAccess.file_exists(asset):
				issues.append("%s requires asset %s. Install it at that project path." % [id, asset])
				blocked[id] = true
		for dep: String in library.requires:
			if not groups.has(dep):
				issues.append("%s requires %s. Add the .gdlib with package ID '%s'." % [id, dep, dep])
				blocked[id] = true
			elif groups[dep].size() == 1:
				var rule: String = library.get("rules", {}).get(dep, "")
				var installed: String = groups[dep][0].get("version", "")
				if not Package.Versions.accepts(installed, rule):
					issues.append("%s requires %s. Installed %s: %s." % [id, Package.Versions.describe(dep, rule), dep, installed if not installed.is_empty() else "unversioned"])
					blocked[id] = true
	var pending: Array = keys.duplicate()
	var progressed: bool = true
	while progressed:
		progressed = false
		for id: String in pending.duplicate():
			if blocked.has(id):
				pending.erase(id)
				continue
			var library: Dictionary = groups[id][0]
			if not dependencies_ready(library.requires, available):
				continue
			if not installed_assets.install(library):
				blocked[id] = true
				pending.erase(id)
				continue
			if library.get("scoped", false):
				var namespace_source: String = "class_name %s\nextends RefCounted\nconst _GDLIB_NAMESPACE: bool = true\n%s\n" % [id, NAMESPACE_WARNING_IGNORE]
				for member: Dictionary in library.members:
					archives.append(Package.archive_path(member))
					if not member.private:
						namespace_source += "const %s = preload(%s)\n" % [member.name, JSON.stringify(Package.body_path(member))]
				wanted[API_DIR.path_join(id + ".gd")] = namespace_source
				available[id] = true
				pending.erase(id)
				progressed = true
				continue
			for member: Dictionary in library.members:
				if member.get("private", false):
					archives.append(Package.archive_path(member))
					continue
				var key: String = String(member.name).to_lower()
				var output: String = API_DIR.path_join(String(member.name) + ".gd")
				if scripts.has(key):
					if scripts[key] != output:
						wanted[output] = "extends " + JSON.stringify(scripts[key]) + "\n" + "const _GDLIB_AUTHOR_ALIAS: bool = true\n"
					continue
				var flags: int = member.flags
				var header: String = ""
				if flags & Package.TOOL:
					header += "@tool\n"
				if flags & Package.ABSTRACT:
					header += "@abstract\n"
				wanted[output] = header + "class_name %s\nextends \"%s\"\n" % [member.name, Package.body_path(member)]
				archives.append(Package.archive_path(member))
			available[id] = true
			pending.erase(id)
			progressed = true
	for id: String in pending:
		var unmet: PackedStringArray = PackedStringArray()
		for dep: String in groups[id][0].requires:
			if not available.has(dep):
				unmet.append(dep)
		issues.append("%s is waiting for %s. Check blocked packages or circular dependencies." % [id, ", ".join(unmet)])
	for id: String in keys:
		var library: Dictionary = groups[id][0]
		var requirements: PackedStringArray = PackedStringArray()
		for dep: String in library.requires:
			requirements.append(Package.Versions.describe(dep, library.get("rules", {}).get(dep, "")))
		var requires_text: String = ", ".join(requirements)
		var state: String = "Ready" if available.has(id) else "Blocked"
		package_states[id] = state
		var count_text: String = "%d classes" % library.members.size() if library.members.size() != 1 else "1 class"
		status.append("%s  •  %s  •  %s%s" % [id, state, count_text, ("  •  requires " + requires_text) if not requires_text.is_empty() else ""])
	installed_assets.finish()
	issues.append_array(installed_assets.issues)
	var changed: bool = installed_assets.changed
	for output: String in wanted:
		var contents: String = wanted[output]
		if FileAccess.file_exists(output) and FileAccess.get_file_as_string(output) == contents:
			continue
		if Package.write_bytes(output, contents.to_utf8_buffer()) == OK:
			touched.append(output)
			changed = true
		else:
			issues.append("GDLibrary could not write " + output)
	if DirAccess.dir_exists_absolute(API_DIR):
		for filename: String in DirAccess.get_files_at(API_DIR):
			var path: String = API_DIR.path_join(filename)
			if path.get_extension() == "gd" and not wanted.has(path) and is_binding(path):
				if DirAccess.remove_absolute(path) == OK:
					if FileAccess.file_exists(path + ".uid"):
						DirAccess.remove_absolute(path + ".uid")
					touched.append(path)
					changed = true
				else:
					issues.append("GDLibrary could not remove obsolete binding " + path)
	var embedded_packages: PackedStringArray = PackedStringArray()
	for id: String in available:
		if not package_infos[id].get("embedded", {}).is_empty():
			embedded_packages.append(id)
	embedded_packages.sort()
	var asset_index: String = JSON.stringify(embedded_packages)
	var asset_index_path: String = preload("assets.gd").INDEX
	if not FileAccess.file_exists(asset_index_path) or FileAccess.get_file_as_string(asset_index_path) != asset_index:
		if Package.write_bytes(asset_index_path, asset_index.to_utf8_buffer()) != OK:
			issues.append("Could not write the embedded asset index.")
		else:
			preload("assets.gd").read_index()
	var index: String = JSON.stringify(archives)
	if not FileAccess.file_exists(Package.INDEX) or FileAccess.get_file_as_string(Package.INDEX) != index:
		if Package.write_bytes(Package.INDEX, index.to_utf8_buffer()) != OK:
			issues.append("GDLibrary could not write " + Package.INDEX)
	catalog_changed.emit()
	return changed

static func exported_globals(library: Dictionary) -> Array:
	if library.get("scoped", false):
		return [{"name": library.id, "flags": 0, "base": "RefCounted"}]
	return library.members

static func dependencies_ready(deps: PackedStringArray, available: Dictionary) -> bool:
	for dep: String in deps:
		if not available.has(dep):
			return false
	return true

static func same_source(path: String, member: Dictionary) -> bool:
	var name_: String = member.name
	var source: String = Package.strip_global_name(FileAccess.get_file_as_string(path), name_)
	if source.is_empty():
		return false
	var digest: PackedByteArray = Package.checksum(name_.to_ascii_buffer(), member.flags, source.to_utf8_buffer())
	return digest.hex_encode() == member.get("author_digest", member.digest)

func collect(directory: EditorFileSystemDirectory, groups: Dictionary, scripts: Dictionary) -> void:
	if directory == null:
		return
	for index: int in directory.get_file_count():
		var path: String = directory.get_file_path(index)
		match path.get_extension().to_lower():
			"gd":
				var library_name: String = directory.get_file_script_class_name(index)
				if not library_name.is_empty() and not (path.get_base_dir() == API_DIR and is_binding(path)):
					scripts[library_name.to_lower()] = path
			"gdlib":
				add_package(path, groups)
	for index: int in directory.get_subdir_count():
		collect(directory.get_subdir(index), groups, scripts)

static func is_binding(path: String) -> bool:
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var library_name: String = path.get_file().get_basename()
	if lines.size() >= 4 and lines[0] == "class_name " + library_name and lines[1] == "extends RefCounted" and lines[2] in ["const _GDLIB_NAMESPACE := true", "const _GDLIB_NAMESPACE: bool = true"]:
		var first_alias: int = 4 if lines[3] == NAMESPACE_WARNING_IGNORE else 3
		if first_alias == lines.size():
			return false
		for i: int in range(first_alias, lines.size()):
			if not lines[i].begins_with("const ") or not (lines[i].contains(' = preload("res://.godot/gdlib/private/') or lines[i].contains(' = preload("res://.godot/gdlib/source/')) or not lines[i].ends_with('.gd")'):
				return false
		return true
	if lines.size() == 2 and lines[0].begins_with("extends \"res://") and lines[1] in ["const _GDLIB_AUTHOR_ALIAS := true", "const _GDLIB_AUTHOR_ALIAS: bool = true"]:
		return true
	var start: int = 0
	if lines.size() > start and lines[start] == "@tool":
		start += 1
	if lines.size() > start and lines[start] == "@abstract":
		start += 1
	if lines.size() != start + 2 or lines[start] != "class_name " + library_name:
		return false
	var prefix: String = "extends \"" + Package.ROOT + "code/" + library_name + "/"
	var last: String = lines[start + 1]
	if last.begins_with('extends "res://.godot/gdlib/source/') and last.ends_with('.gd"'):
		return not Package.source_location(last.trim_prefix('extends "').trim_suffix('"')).is_empty()
	if not last.begins_with(prefix) or not last.ends_with(".gd\""):
		return false
	var digest: String = last.trim_prefix(prefix).trim_suffix(".gd\"")
	return digest.length() == 64 and digest.is_valid_hex_number()

func bootstrap() -> void:
	issues.clear()
	var groups: Dictionary = {}
	var scripts: Dictionary = {}
	scan_disk("res://", groups, scripts)
	apply(groups, scripts)

func scan_disk(folder: String, groups: Dictionary, scripts: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null or FileAccess.file_exists(folder.path_join(".gdignore")):
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var path: String = folder.path_join(entry)
		if not entry.begins_with(".") and not dir.is_link(entry):
			if dir.current_is_dir():
				if not FileAccess.file_exists(path.path_join("project.godot")):
					scan_disk(path, groups, scripts)
			elif entry.get_extension() == "gdlib":
				add_package(path, groups)
			elif entry.get_extension() == "gd" and not (folder == API_DIR and is_binding(path)):
				var declaration: RegExMatch = Package.global_declaration(FileAccess.get_file_as_string(path))
				if declaration != null:
					scripts[declaration.get_string(1).to_lower()] = path
		entry = dir.get_next()
	dir.list_dir_end()

func add_package(path: String, groups: Dictionary) -> void:
	if not FileAccess.file_exists(path):
		return
	var modified: int = FileAccess.get_modified_time(path)
	var info: Dictionary = cache.get(path, {})
	if info.is_empty() or info.stamp != modified or not Package.is_cached(info):
		info = Package.read_package(path)
		if info.is_empty() or Package.prepare(info) != OK:
			cache.erase(path)
			issues.append("GDLibrary could not verify or prepare " + path)
			return
		info.path = path
		info.stamp = modified
		cache[path] = info
	var id: String = info.id
	if not groups.has(id):
		groups[id] = []
	groups[id].append(info)
