@tool
# GDL_Core.gd - Your main library autoload
extends Node

# Version info
const VERSION = "1.0.0"
const API_VERSION = 1

# Library registry for dynamic module loading
var loaded_modules = {}
var module_paths = {}

# Creates the module path if none exists
func _init() -> void:
	if Engine.is_editor_hint():
		var dir = DirAccess.open("res://")
		if dir and not dir.dir_exists("gdl_modules"):
			var err = dir.make_dir("gdl_modules")
			if err == OK:
				print("Created folder: res://gdl_modules")
			else:
				print("Failed to create folder: ", err)
		else:
			print("Folder already exists: res://gdl_modules")


# Initialize the library system
func _ready():
	print("GDL Core v%s initialized" % VERSION)
	scan_for_modules()

# Register a module path for lazy loading
func register_module_path(module_name: String, script_path: String):
	module_paths[module_name] = script_path
	print("Registered module: %s -> %s" % [module_name, script_path])

# Load a module dynamically
func load_module(module_name: String):
	if module_name in loaded_modules:
		return loaded_modules[module_name]
	
	if module_name in module_paths:
		var script_path = module_paths[module_name]
		var script
		
		# Handle .gdl files specially
		if script_path.ends_with(".gdl"):
			script = load_gdl_file(script_path)
		else:
			script = load(script_path)
		
		if script:
			var module_instance = script.new()
			loaded_modules[module_name] = module_instance
			
			# Call module initialization if it exists
			if module_instance.has_method("_gdl_init"):
				module_instance._gdl_init()
			
			print("Loaded module: %s" % module_name)
			return module_instance
	
	push_error("Module not found: %s" % module_name)
	return null

# Custom loader for .gdl files
func load_gdl_file(path: String) -> GDScript:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Could not open .gdl file: " + path)
		return null
	
	var content = file.get_as_text()
	file.close()
	
	# Create a temporary .gd file to load the script
	var temp_path = "user://temp_gdl_" + str(randi()) + ".gd"
	var temp_file = FileAccess.open(temp_path, FileAccess.WRITE)
	temp_file.store_string(content)
	temp_file.close()
	
	# Load the script from temporary file
	var script = GDScript.new()
	script.source_code = content
	script.reload()
	
	# Clean up temporary file
	DirAccess.remove_absolute(temp_path)
	
	return script

# Get a loaded module
func get_module(module_name: String):
	if module_name in loaded_modules:
		return loaded_modules[module_name]
	return load_module(module_name)

# Unload a module
func unload_module(module_name: String):
	if module_name in loaded_modules:
		var module = loaded_modules[module_name]
		if module.has_method("_gdl_cleanup"):
			module._gdl_cleanup()
		loaded_modules.erase(module_name)
		print("Unloaded module: %s" % module_name)

# Auto-scan for modules in a specific directory
func scan_for_modules():
	var dir = DirAccess.open("res://gdl_modules/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".gdl"):
				var module_name = file_name.get_basename()
				register_module_path(module_name, "res://gdl_modules/" + file_name)
			file_name = dir.get_next()

# Call a function from any loaded module
func call_module_function(module_name: String, function_name: String, args: Array = []):
	var module = get_module(module_name)
	if module and module.has_method(function_name):
		return module.callv(function_name, args)
	else:
		push_error("Function %s not found in module %s" % [function_name, module_name])
		return null

# Get list of available modules
func get_available_modules() -> Array:
	return module_paths.keys()

# Get list of loaded modules
func get_loaded_modules() -> Array:
	return loaded_modules.keys()
