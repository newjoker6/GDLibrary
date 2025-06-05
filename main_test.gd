extends Control


func _ready():
	#GDL_Core.convert_all_gdl_to_binary()
	print(GDL_Core.get_available_modules())
	print(GDL_Core.get_loaded_modules())
	var utils = GDL_Core.get_module("Utils")
	print(utils.print_function_signature("rainbowLog"))
	#print(GDL_Core.print_module_function_signature("Utils", "rainbowLog"))
	#for arg in utils.get_function_argument_details("rainbowLog"):
		#print(utils.printPretty(arg))
		
	if not utils:
		print("Failed to load Utils module")
		return
	
	# Test logging functions
	utils.rainbowLog("Welcome to Utils Module!")
	utils.flashLog("This is a flash message!", Color.RED, 2.0)
	utils.gradientLog("Gradient text example", Color.BLUE, Color.PURPLE)
	utils.highlightLog("Important message!", Color.YELLOW, Color.BLACK)
