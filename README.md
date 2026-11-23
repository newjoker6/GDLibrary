# GDLibrary

**Distribute GDScript classes and assets in a single `.gdlib` file.** Once a library is imported, its public classes are available in Godot’s script editor with autocomplete, type checking and method signatures.

GDLibrary 2.5.7 is a pure GDScript editor add-on tested with Godot 4.7.2. A package contains compressed GDScript and its source can be recovered.

## Install the add-on

1. Open your own Godot project. Copy [addons/gdlibrary](addons/gdlibrary/) into it so the plugin file is at `res://addons/gdlibrary/plugin.cfg`.
2. Open **Project → Project Settings → Plugins** and enable **GDLibrary**.
3. GDLibrary creates `res://libraries/` automatically. Drop any `.gdlib` packages you receive there, along with their required packages. Other imported project folders also work.

Select a `.gdlib` in the **FileSystem** dock. Its Inspector shows the **Package ID**, **Status**, **Public classes**, dependencies and asset paths. When the status is **Ready**, use the names under **Public classes** in your scripts. The package ID is what you use for dependency declarations and asset lookups.

Document public methods and properties with GDScript `##` comments before packing. GDLibrary registers the imported script descriptions with the editor so consumers can read them on hover.

For a namespaced package, open its package ID in the Godot class reference. Each public constant includes a link to its packaged class documentation.

## Create your first library

This example creates a package named `BoardGames` and calls `BoardGames.Dice.total(2, 3)` from another project.

### In the author project

1. Install the add-on as described above. Create `res://dice.gd` with the following contents and save it.

   ```gdscript
   extends RefCounted

   static func total(first: int, second: int) -> int:
   	return first + second
   ```

2. Right-click `dice.gd` in the FileSystem dock and choose **Pack as Library…**. You can also use **Project → Tools → Pack GDScript Library…** or the command palette.
3. Set **Package ID** to `BoardGames`, **Version** to `1.0.0`, and enable **Use package ID as a namespace**. The filename `dice.gd` gives this script the public name `Dice`.
4. Click **Validate**, then **Choose Destination…**. Save `BoardGames.gdlib` in a `dist` folder beside the author project. GDLibrary also saves `res://gdlib_definitions/BoardGames.gdlib.tres` inside the project for future repacks.

### In the consuming project

1. Enable GDLibrary, copy `BoardGames.gdlib` into the automatically created `res://libraries/` folder and let Godot finish importing.
2. Create a scene with a `Node` root, attach the script below, save the scene and press **F6**. The Output panel should print `5`.

   ```gdscript
   extends Node

   func _ready() -> void:
   	print(BoardGames.Dice.total(2, 3))
   ```

## Package options and updates

- **Public names.** A script uses its declared `class_name`, or its filename in PascalCase. With namespaces enabled, `BoardGames.Dice` and `Casino.Dice` can coexist. With namespaces off, each public class is registered by its own name. Generated namespace aliases suppress the `shadowed_global_identifier` warning if an alias shares a name with a global class.
- **Multiple scripts.** Use **Add scripts…** to include classes and **Toggle public/private** for implementation helpers. Each package needs at least one public script.
- **Package IDs.** Use letters, digits or underscores, starting with a letter or underscore. Consumers can use **Copy Package ID** in the Inspector.
- **Repacking.** Right-click the saved definition and choose **Repack Library**. If public declarations changed, the editor shows the differences before replacing the previous package. Distribute the resulting `.gdlib`, its required packages and any assets you chose to keep external.

## Dependencies

Use **Add installed dependency** or enter comma-separated requirements. Version checks use the package ID recorded inside each file.

| Requirement | Accepted versions |
| --- | --- |
| `GatorMath` | Any installed version |
| `GatorMath@1.2.0` | Exactly 1.2.0 |
| `GatorMath@^1.2.0` | 1.2.0 up to, but excluding, 2.0.0 |
| `GatorMath@^0.3.1` | 0.3.1 up to, but excluding, 0.4.0 |

Open **Project → Tools → GDLibrary Dependencies…** to find missing packages, incompatible versions, duplicate IDs or dependency cycles.

## Textures and other assets

| How the library uses an asset | What to pack |
| --- | --- |
| A script uses a literal path such as `preload("res://cards/ace.png")` | Enable **Embed referenced resources**. The packer follows the reference and its resource dependencies. |
| A function builds a path from a card ID at runtime | Use **Additional asset files and folders… → Add folder…** and select `res://cards/`. This enables embedding and includes supported files recursively. |
| You distribute assets separately | Leave embedding off and supply the required assets at the project-relative paths shown in the Inspector. |

For an embedded folder, use the package ID and the original path relative to `res://`. For example, a package with ID `CardArt` can load a card by name:

```gdscript
static func card_texture(card_id: String) -> Texture2D:
	var path: String = GDLibraryAssets.path("CardArt", "cards/%s.png" % card_id)
	return load(path) as Texture2D
```

With `CardArt` installed, the path for `ace` resolves to `res://gdlib_assets/CardArt/cards/ace.png`. If it resolves to `res://cards/ace.png` in a consumer project, check the installed package’s **Package ID** and **Embedded resources** in the Inspector. **Copy Package ID** gives you the exact spelling.

Supported assets include textures, audio, fonts, text scenes and resources, and self-contained binary scenes and resources. For scenes with attached GDScripts, add the scripts with **Add scripts…**. Asset folders skip `.gd` files. The [embedded resource handler](addons/gdlibrary/embedded.gd) lists the supported extensions.

## Test, export and debug

- **Test a package in isolation.** Select the `.gdlib` and click **Test in Clean Project**. GDLibrary creates a disposable consumer, imports the package and dependencies, checks public classes and resources, then repeats the checks in an exported PCK. For an external distribution, put its required packages beside it or in an adjacent `libraries/` folder.
- **Export a game.** Export through Godot as usual. For a preset that exports only selected scenes or resources, open **Project → Tools → GDLibrary Export Presets…**, apply **Fix Export Preset**, and reopen the editor before exporting. This includes bindings and assets reached only at runtime.
- **Trace a runtime error.** Copy a stack frame from a package built with 2.5 or later. In the matching author project, open **Project → Tools → Go to GDLibrary Source…** and paste it to jump to the original script and line.
- **First import.** A scene that already references a packaged class can briefly report an unknown identifier while Godot registers the generated classes. Let the import finish. If the error persists, check the package’s status and dependencies.

### Command line

Run these commands with the Godot editor executable on your PATH. The first two use the BoardGames definition and output from the walkthrough. For the third, create an export preset in your project and substitute its name for `Linux`.

```sh
godot --headless --script res://addons/gdlibrary/release.gd -- pack res://gdlib_definitions/BoardGames.gdlib.tres ../dist/BoardGames.gdlib
godot --headless --script res://addons/gdlibrary/release.gd -- test ../dist/BoardGames.gdlib ../dist
godot --headless --script res://addons/gdlibrary/release.gd -- export-pack Linux builds/game.pck
```

`pack` can compare against a specific previous release with `--baseline <previous.gdlib>`. A public API change returns exit code `3` and preserves the previous output. Review the differences and pass `--allow-api-changes` to accept them. `export-pack` takes an export preset name and verifies the PCK before publishing it.

## Migrating from GDLibrary 1.x

The original project used a `GDL_Core` autoload, `.gdl` and `.gdlb` modules, and calls such as `GDL_Core.get_module("Utils")`. Those files require the original loader. To move a library to 2.5:

1. Move the reusable implementation into ordinary `.gd` scripts. Replace dependencies on `GDLModule` and move any work done in the old load or cleanup hooks into methods your application calls explicitly.
2. Pack the scripts with the editor and declare the package dependencies. Update callers to use the public classes. For stateful modules, create and retain an instance where the old loader held one for you.
3. Once all legacy callers are migrated, remove the old `GDL_Core` autoload.

GDLibrary 2.5.5 reads earlier **2.x** `.gdlib` packages. Consumers need **2.5 or newer** to import packages written by this version. This release packages libraries for editor import and game export. Loading player-supplied mods into an already-exported game is outside its current scope.

## License

[MIT License](LICENSE) · Blackwater Gator Studios
