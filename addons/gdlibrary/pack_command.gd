extends SceneTree

const Package := preload("package.gd")
const Catalog := preload("catalog.gd")
const Definition := preload("definition.gd")
const Validation := preload("validation.gd")

func _init() -> void:
	run.call_deferred()

func run() -> void:
	quit(pack(OS.get_cmdline_user_args()))

func local_path(value: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://"):
		return value.simplify_path()
	var path := value if value.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(value)
	return ProjectSettings.localize_path(path.simplify_path())

func pack(args: PackedStringArray) -> int:
	if args.size() < 2:
		printerr("Expected <definition.gdlib.tres> <output.gdlib> [--baseline <previous.gdlib>] [--allow-api-changes]")
		return 2
	var definition := local_path(args[0])
	var output := local_path(args[1])
	var baseline := ""
	var accept := false
	var i := 2
	while i < args.size():
		match args[i]:
			"--allow-api-changes":
				accept = true
			"--baseline":
				i += 1
				if i >= args.size() or not baseline.is_empty():
					printerr("Expected one baseline package path.")
					return 2
				baseline = local_path(args[i])
				if not FileAccess.file_exists(baseline):
					printerr("Missing baseline " + baseline)
					return 1
			_:
				printerr("Unknown pack option " + args[i])
				return 2
		i += 1
	if not definition.ends_with(".gdlib.tres") or output.get_extension().to_lower() != "gdlib":
		printerr("Choose a .gdlib.tres definition and a .gdlib output.")
		return 2
	var recipe := ResourceLoader.load(definition) as Definition
	if recipe == null:
		printerr("Cannot load library definition " + definition)
		return 1
	var catalog := Catalog.new()
	catalog.bootstrap()
	var result := Validation.review(recipe, catalog)
	var errors: PackedStringArray = result.errors
	for id: String in result.suggestions:
		errors.append("Declare package requirement " + id)
	var destination_problem := Validation.destination_error(recipe.package_id, output, catalog, result)
	if not destination_problem.is_empty():
		errors.append(destination_problem)
	if not errors.is_empty():
		printerr("\n".join(errors))
		return 1
	var previous_hash := FileAccess.get_sha256(output) if FileAccess.file_exists(output) else ""
	if not previous_hash.is_empty():
		var existing := Package.read_package(output)
		if existing.is_empty() or existing.id != recipe.package_id:
			printerr("Output already exists and does not contain package " + recipe.package_id)
			return 1
	if baseline.is_empty():
		if not previous_hash.is_empty():
			baseline = output
		elif not recipe.output_path.is_empty() and FileAccess.file_exists(recipe.output_path):
			baseline = recipe.output_path
	if not baseline.is_empty():
		var previous := Package.read_package(baseline)
		if previous.is_empty() or previous.id != recipe.package_id:
			printerr("Invalid baseline for package " + recipe.package_id)
			return 1
	var temp := DirAccess.create_temp("gdlib-pack")
	if temp == null:
		printerr("Cannot create a staging directory.")
		return 1
	var candidate := temp.get_current_dir().path_join("candidate.gdlib")
	var error := Package.pack_definition(recipe, candidate)
	if error != OK:
		printerr("Packing failed: " + error_string(error))
		return 1
	if not baseline.is_empty():
		var changes := Package.api_changes(recipe.package_id, baseline, candidate)
		if not changes.is_empty():
			print("API review against ", baseline, "\n", "\n".join(changes))
			if not accept:
				printerr("Review the differences and use --allow-api-changes to publish.")
				return 3
	var current_hash := FileAccess.get_sha256(output) if FileAccess.file_exists(output) else ""
	if current_hash != previous_hash:
		printerr("Output changed during packing. Retry the comparison.")
		return 1
	var bytes := FileAccess.get_file_as_bytes(candidate)
	if bytes.is_empty() or Package.write_bytes(output, bytes) != OK:
		printerr("Could not write " + output)
		return 1
	print("Packed ", recipe.package_id, "@", recipe.version, " to ", output)
	return 0
