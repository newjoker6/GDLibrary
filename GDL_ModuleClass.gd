# GDL_Module.gd - Base class for all GDL modules
class_name GDLModule
extends RefCounted

# Module metadata
var module_name: String = ""
var module_version: String = "1.0.0"
var module_author: String = ""
var module_description: String = ""
var dependencies: Array[String] = []

# Initialization - called when module is loaded
func _gdl_init():
	print("Module %s v%s loaded" % [module_name, module_version])

# Cleanup - called when module is unloaded
func _gdl_cleanup():
	print("Module %s unloaded" % module_name)

# Get module info
func get_module_info() -> Dictionary:
	return {
		"name": module_name,
		"version": module_version,
		"author": module_author,
		"description": module_description,
		"dependencies": dependencies
	}

# Check if dependencies are met
func check_dependencies() -> bool:
	for dep in dependencies:
		if not GDL_Core.get_module(dep):
			push_error("Dependency not met: %s" % dep)
			return false
	return true

# Export function list (override in derived modules)
func get_exported_functions() -> Array[String]:
	return []

# Export variable list (override in derived modules)  
func get_exported_variables() -> Array[String]:
	return []


# NEW: Get function arguments for a specific function
func get_function_arguments(function_name: String) -> Array:
	var method_list = get_method_list()
	for method_info in method_list:
		if method_info.name == function_name:
			var arg_names = []
			if method_info.has("args"):
				for arg in method_info.args:
					arg_names.append(arg.name)
			return arg_names
	
	push_warning("Function '%s' not found in module '%s'" % [function_name, module_name])
	return []

# NEW: Get detailed function argument information
func get_function_argument_details(function_name: String) -> Array:
	var method_list = get_method_list()
	for method_info in method_list:
		if method_info.name == function_name:
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
	
	push_warning("Function '%s' not found in module '%s'" % [function_name, module_name])
	return []

# NEW: Get all exported functions with their arguments
func get_exported_functions_with_args() -> Dictionary:
	var exported_funcs = get_exported_functions()
	var functions_with_args = {}
	
	for func_name in exported_funcs:
		functions_with_args[func_name] = {
			"arguments": get_function_arguments(func_name),
			"argument_details": get_function_argument_details(func_name)
		}
	
	return functions_with_args

# NEW: Print function signature
func print_function_signature(function_name: String):
	var arg_details = get_function_argument_details(function_name)
	if arg_details.is_empty():
		print("Function '%s' not found or has no arguments" % function_name)
		return
	
	var signature = "%s(" % function_name
	var arg_strings = []
	
	for arg in arg_details:
		var arg_str = "%s: %s" % [arg.name, arg.type_name]
		if arg.has_default:
			arg_str += " = %s" % str(arg.default_value)
		arg_strings.append(arg_str)
	
	signature += ", ".join(arg_strings) + ")"
	print("Function signature: %s" % signature)

# NEW: List all public methods with signatures
func list_all_functions():
	print("Functions in module '%s':" % module_name)
	var method_list = get_method_list()
	for method_info in method_list:
		var method_name = method_info.name
		# Skip internal methods except GDL specific ones
		if method_name.begins_with("_") and not method_name.begins_with("_gdl"):
			continue
		# Skip built-in RefCounted methods
		if method_name in ["get_reference_count", "init_ref", "reference", "unreference"]:
			continue
			
		print_function_signature(method_name)

# NEW: Validate function call arguments
func validate_function_args(function_name: String, args: Array) -> bool:
	var method_list = get_method_list()
	for method_info in method_list:
		if method_info.name == function_name:
			var required_args = method_info.get("args", [])
			var min_args = 0
			var max_args = required_args.size()
			
			# Count required arguments (those without defaults)
			for arg in required_args:
				if not arg.has("default_value"):
					min_args += 1
			
			# Validate argument count
			if args.size() < min_args:
				push_error("Too few arguments for %s(). Expected at least %d, got %d" % [function_name, min_args, args.size()])
				return false
			elif args.size() > max_args:
				push_error("Too many arguments for %s(). Expected at most %d, got %d" % [function_name, max_args, args.size()])
				return false
			
			return true
	
	push_error("Function '%s' not found" % function_name)
	return false

# NEW: Safe function calling with validation
func call_function_safe(function_name: String, args: Array = []):
	if not has_method(function_name):
		push_error("Function '%s' not found in module '%s'" % [function_name, module_name])
		return null
	
	if validate_function_args(function_name, args):
		return callv(function_name, args)
	
	return null
