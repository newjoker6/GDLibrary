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
3. In **Project Settings → AutoLoad**, add the `GDL_Core.gd` script as a global singleton named `GDL_Core`.

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
GDL_Core.export_module_source("testModule")
