extends Control


func _ready():
	print(GDL_Core.get_available_modules())
	print(GDL_Core.get_loaded_modules())
	var utils = GDL_Core.get_module("Utils")
	print(utils.print_function_signature("rainbowLog"))
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
