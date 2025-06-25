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
		var settings = EditorInterface.get_editor_settings()
		var exts = settings.get_setting("docks/filesystem/textfile_extensions")
		if (!"gdl" in exts) and (!"gdlb" in exts):
			var newexts = "%s,gdl,gdlb" %exts
			settings.set_setting("docks/filesystem/textfile_extensions", newexts)
		
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
		
		# Handle .gdl and .gdlb files specially
		if script_path.ends_with(".gdl") or script_path.ends_with(".gdlb"):
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

# Enhanced load_gdl_file to support both text and binary formats
func load_gdl_file(path: String) -> GDScript:
	var script = GDScript.new()
	
	if path.ends_with(".gdlb"):
		# Load binary format
		var gdl_data = GDLBinaryFormat.load_gdl_binary(path)
		if gdl_data.is_empty():
			push_error("Failed to load binary GDL file: " + path)
			return null
		
		script.source_code = gdl_data.source_code
		script.reload()
		
		# Store metadata for later use
		if gdl_data.has("metadata"):
			script.set_meta("gdl_metadata", gdl_data.metadata)
		
		return script
	else:
		# Load text format (.gdl)
		var file = FileAccess.open(path, FileAccess.READ)
		if not file:
			push_error("Could not open .gdl file: " + path)
			return null
		
		var content = file.get_as_text()
		file.close()
		
		script.source_code = content
		script.reload()
		
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

# Enhanced scan_for_modules to include binary files
func scan_for_modules():
	var dir = DirAccess.open("res://gdl_modules/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".gdl") or file_name.ends_with(".gdlb"):
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

# Enhanced call_module_function with argument validation
func call_module_function_safe(module_name: String, function_name: String, args: Array = []):
	var module = get_module(module_name)
	if not module:
		return null
		
	if not module.has_method(function_name):
		push_error("Function %s not found in module %s" % [function_name, module_name])
		return null
	
	# Get method info for validation
	var method_info = get_module_method_info(module_name, function_name)
	if not method_info.is_empty():
		var required_args = method_info.get("args", [])
		var min_args = 0
		var max_args = required_args.size()
		
		# Count required arguments (those without defaults)
		for arg in required_args:
			if not arg.has("default_value"):
				min_args += 1
		
		# Validate argument count
		if args.size() < min_args:
			push_error("Too few arguments for %s.%s(). Expected at least %d, got %d" % [module_name, function_name, min_args, args.size()])
			return null
		elif args.size() > max_args:
			push_error("Too many arguments for %s.%s(). Expected at most %d, got %d" % [module_name, function_name, max_args, args.size()])
			return null
	
	return module.callv(function_name, args)

# Get detailed method information including arguments
func get_module_method_info(module_name: String, function_name: String) -> Dictionary:
	var module = get_module(module_name)
	if not module:
		push_error("Module not found: %s" % module_name)
		return {}
	
	var method_list = module.get_method_list()
	for method_info in method_list:
		if method_info.name == function_name:
			return method_info
	
	push_error("Method %s not found in module %s" % [function_name, module_name])
	return {}

# Get just the argument names as an array
func get_module_function_args(module_name: String, function_name: String) -> Array:
	var method_info = get_module_method_info(module_name, function_name)
	if method_info.is_empty():
		return []
	
	var arg_names = []
	if method_info.has("args"):
		for arg in method_info.args:
			arg_names.append(arg.name)
	
	return arg_names

# Get detailed argument information (name, type, default values)
func get_module_function_arg_details(module_name: String, function_name: String) -> Array:
	var method_info = get_module_method_info(module_name, function_name)
	if method_info.is_empty():
		return []
	
	var arg_details = []
	if method_info.has("args"):
		for arg in method_info.args:
			var arg_info = {
				"name": arg.name,
				"type": arg.type,
				"type_name": type_string(arg.type),
				"has_default": arg.has("default_value"),
				"default_value": arg.get("default_value", null)
			}
			arg_details.append(arg_info)
	
	return arg_details

# Print function signature for debugging
func print_module_function_signature(module_name: String, function_name: String):
	var arg_details = get_module_function_arg_details(module_name, function_name)
	if arg_details.is_empty():
		print("Function not found or has no arguments")
		return
	
	var signature = "%s.%s(" % [module_name, function_name]
	var arg_strings = []
	
	for arg in arg_details:
		var arg_str = "%s: %s" % [arg.name, arg.type_name]
		if arg.has_default:
			arg_str += " = %s" % str(arg.default_value)
		arg_strings.append(arg_str)
	
	signature += ", ".join(arg_strings) + ")"
	print("Function signature: %s" % signature)

# List all methods in a module with their signatures
func list_module_methods(module_name: String):
	var module = get_module(module_name)
	if not module:
		return
	
	print("Methods in module '%s':" % module_name)
	var method_list = module.get_method_list()
	for method_info in method_list:
		var method_name = method_info.name
		# Skip internal methods
		if method_name.begins_with("_") and method_name != "_gdl_init" and method_name != "_gdl_cleanup":
			continue
			
		print_module_function_signature(module_name, method_name)

# Get list of available modules
func get_available_modules() -> Array:
	return module_paths.keys()

# Get list of loaded modules
func get_loaded_modules() -> Array:
	return loaded_modules.keys()

# Convert existing .gdl files to binary format
func convert_all_gdl_to_binary():
	var dir = DirAccess.open("res://gdl_modules/")
	if not dir:
		push_error("Cannot access gdl_modules directory")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gdl"):
			var gdl_path = "res://gdl_modules/" + file_name
			var binary_path = "res://gdl_modules/" + file_name.get_basename() + ".gdlb"
			
			print("Converting %s to %s" % [gdl_path, binary_path])
			if GDLBinaryFormat.convert_gdl_to_binary(gdl_path, binary_path):
				print("Conversion successful!")
				# Optionally remove the old .gdl file
				# dir.remove(file_name)
			else:
				print("Conversion failed!")
		
		file_name = dir.get_next()

# Get module metadata (works with both formats)
func get_module_metadata(module_name: String) -> Dictionary:
	var module = get_module(module_name)
	if not module:
		return {}
	
	var script = module.get_script()
	if script and script.has_meta("gdl_metadata"):
		return script.get_meta("gdl_metadata")
	
	# Fallback to module properties
	if module.has_method("get_module_info"):
		return module.get_module_info()
	
	return {}

# Create a new GDL module file (binary format)
func create_gdl_module(module_name: String, template_data: Dictionary = {}) -> bool:
	var default_template = {
		"metadata": {
			"name": module_name,
			"version": "1.0.0",
			"author": "Unknown",
			"description": "A new GDL module"
		},
		"source_code": """
# @gdl:name: %s
# @gdl:version: 1.0.0
# @gdl:author: Unknown

extends GDLModule

func _init():
	module_name = "%s"
	module_version = "1.0.0"
	author = "Unknown"
	description = "library description"
	dependencies = []

func get_exported_functions() -> Array[String]:
	return ["hello_world"]

func hello_world() -> String:
	return "Hello from %s!"
""" % [module_name, module_name, module_name],
		"dependencies": [],
		"exports": {
			"functions": ["hello_world"],
			"variables": []
		}
	}
	
	# Merge with provided template
	for key in template_data:
		default_template[key] = template_data[key]
	
	var path = "res://gdl_modules/%s.gdlb" % module_name
	return GDLBinaryFormat.save_gdl_binary(path, default_template)

# Get file format info
func get_module_format(module_name: String) -> String:
	if module_name in module_paths:
		var path = module_paths[module_name]
		if path.ends_with(".gdlb"):
			return "binary"
		elif path.ends_with(".gdl"):
			return "text"
	return "unknown"

# Development helper: Export module to text format for editing
func export_module_source(module_name: String, output_path: String = "") -> bool:
	if output_path.is_empty():
		output_path = "res://gdl_modules/%s.gdl" % module_name
	
	var format = get_module_format(module_name)
	if format == "binary":
		var binary_path = module_paths[module_name]
		var gdl_data = GDLBinaryFormat.load_gdl_binary(binary_path)
		if gdl_data.has("source_code"):
			var file = FileAccess.open(output_path, FileAccess.WRITE)
			if file:
				file.store_string(gdl_data.source_code)
				file.close()
				print("Exported source to: " + output_path)
				return true
	
	push_error("Cannot export source for module: " + module_name)
	return false
