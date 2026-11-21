@tool
extends Resource

@export var package_id: String
@export var version: String = "1.0.0"
@export var sources: PackedStringArray
@export var private_sources: PackedStringArray
@export var requirements: PackedStringArray
@export var output_path: String

@export var namespace_enabled: bool = false
@export var embed_resources: bool = false
@export var asset_inputs: PackedStringArray
