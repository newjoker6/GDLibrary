# GDLibrary

**GDLibrary** is a pure GDScript system for building reusable, distributable libraries—similar to DLLs—directly in Godot Engine. It allows you to define, export, load, and package modular `.gdl` files and convert them into binary `.gdlb` format for efficient use and distribution.

---

## 🚀 Features

- 📦 Define modular libraries using `.gdl` files
- 🔐 Package them into `.gdlb` binary format with compression and checksums
- 🧠 Load libraries dynamically at runtime
- 📁 Compatible with `.pck` packaging
- 💡 No C++, GDExtension, or plugins required—just GDScript

---

## 📁 Installation

1. Clone or download the repository.
2. Add the `GDLibrary` folder to your Godot project.
3. In **Project Settings → Global**, add the `GDL_Core.gd` script as a global singleton named `GDL_Core`.

   Example:

   | Path                            | Name       | Enabled |
   |----------------------------------|------------|---------|
   | `res://GDLibrary/GDL_Core.gd`   | `GDL_Core` | ✅       |

4. You're now ready to create and load `.gdl` libraries.

---

## 📚 Creating a New GDL Library

To create a new module (library), run the following GDScript commands:

```gdscript
GDL_Core.create_gdl_module("testModule")
GDL_Core.export_module_source("testModule")```

This creates a new file at res://gdl_modules/testModule.gdl with:

- Metadata block (name, version, dependencies, exports)

- Function stubs

- Ready for editing

You can now open and modify testModule.gdl like any other GDScript file.

---
## 🚀 Loading a Module at Runtime
Once a `.gdlb` or `.gdlb` file is in res://gdl_modules/, you can load it:

```gdscript
var test = GDL_Core.get_module("testModule")
test.some_function()```

get_module("name") returns the loaded module (as a script instance) or loads it if not already active.

---

## 📤 Compiling Modules for Distribution

To convert all `.gdl` source files into `.gdlb` binaries:

```gdscript
GDL_Core.convert_all_gdl_to_binary()```

This compresses and saves .gdlb files alongside the originals for shipping in .pck or .zip exports.

---

## 📦 Using in Exported Projects

- .gdlb files are fully compatible with .pck exports.

- As long as the binary is present in res://gdl_modules/, it can be loaded like any other module.

- Source `.gdl` files are prioritized in editor, but `.gdlb` will be used in release builds if source is missing.

---

## 🔍 Checking for Module Dependencies
At runtime, you can check if those dependencies are loaded:

```gdscript
check_dependencies()```

This returns true if all required modules are loaded, otherwise logs which are missing.

## 📚 Example

```gdscript
func _ready():
	var utils = GDL_Core.get_module("Utils")
	if utils and utils.check_dependencies():
		utils.rainbow_log("Hello from GDLibrary!")```

---

## 📂 GDL File Format (Binary Overview)
.gdlb files are compiled containers with:

- Magic header: GDL\x01

- File version and timestamp

- Sections:

 - metadata: Dictionary (name, version, exports, dependencies)

 - source_code: Compressed UTF-8 GDScript string

 - exports: Dictionary or list of callable functions

 - dependencies: Array of required module names

 - resources: Optional embedded resources

- Checksums to validate integrity

---

## 🧪 Development Notes
Source modules (.gdl) are editable and good for iteration.

Binary modules (.gdlb) are preferred for release builds and protect source logic.

Both formats can coexist in the same folder—.gdl takes precedence in the editor.

---

## 📝 License
MIT License — use freely in open-source or commercial projects. No credit required, but always appreciated!