# GDL_BinaryFormat.gd - Custom binary format for GDL modules
class_name GDLBinaryFormat
extends RefCounted

# File format constants
const MAGIC_HEADER = "GDL" + char(1) # Magic bytes + version
const CURRENT_VERSION = 1

# Section types
enum SectionType {
	METADATA = 0x01,
	SOURCE_CODE = 0x02,
	RESOURCES = 0x03,
	DEPENDENCIES = 0x04,
	EXPORTS = 0x05,
	CHECKSUMS = 0x06
}

# Compression types
enum CompressionType {
	NONE = 0,
	GZIP = 1,
	ZSTD = 2
}

# Save GDL module to binary format
static func save_gdl_binary(path: String, gdl_data: Dictionary) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Cannot create file: " + path)
		return false
	
	# Write magic header
	file.store_string(MAGIC_HEADER)
	
	# Write file format version
	file.store_8(CURRENT_VERSION)
	
	# Write timestamp
	file.store_64(Time.get_unix_time_from_system())
	
	# Prepare sections
	var sections = []
	
	# Metadata section
	if gdl_data.has("metadata"):
		sections.append(_create_section(SectionType.METADATA, var_to_bytes(gdl_data.metadata)))
	
	# Source code section (compressed)
	if gdl_data.has("source_code"):
		var source_bytes = gdl_data.source_code.to_utf8_buffer()
		var compressed = source_bytes.compress(FileAccess.COMPRESSION_GZIP)
		sections.append(_create_section(SectionType.SOURCE_CODE, compressed, CompressionType.GZIP))
	
	# Dependencies section
	if gdl_data.has("dependencies"):
		sections.append(_create_section(SectionType.DEPENDENCIES, var_to_bytes(gdl_data.dependencies)))
	
	# Exports section
	if gdl_data.has("exports"):
		sections.append(_create_section(SectionType.EXPORTS, var_to_bytes(gdl_data.exports)))
	
	# Resources section
	if gdl_data.has("resources"):
		sections.append(_create_section(SectionType.RESOURCES, var_to_bytes(gdl_data.resources)))
	
	# Write section count
	file.store_32(sections.size())
	
	# Write section table (offsets will be calculated)
	var section_table_pos = file.get_position()
	for section in sections:
		file.store_8(section.type)
		file.store_8(section.compression)
		file.store_32(0)  # Placeholder for offset
		file.store_32(section.data.size())
		file.store_32(_calculate_checksum(section.data))
	
	# Write sections and update offsets
	var current_pos = file.get_position()
	for i in range(sections.size()):
		var section = sections[i]
		
		# Update offset in section table
		var table_offset = section_table_pos + (i * 14) + 2  # Skip type and compression
		var saved_pos = file.get_position()
		file.seek(table_offset)
		file.store_32(current_pos)
		file.seek(saved_pos)
		
		# Write section data
		file.store_buffer(section.data)
		current_pos = file.get_position()
	
	file.close()
	print("Saved GDL binary: " + path)
	return true

# Load GDL module from binary format
static func load_gdl_binary(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Cannot open file: " + path)
		return {}
	
	# Verify magic header
	var magic = file.get_buffer(4)
	#print("Raw magic header:", magic)
	#print("As string:", magic.get_string_from_utf8())
	if magic.get_string_from_utf8() != MAGIC_HEADER:
		push_error("Invalid GDL binary file: " + path)
		file.close()
		return {}
	
	# Read version
	var version = file.get_8()
	if version != CURRENT_VERSION:
		push_warning("GDL binary version mismatch: expected %d, got %d" % [CURRENT_VERSION, version])
	
	# Read timestamp
	var timestamp = file.get_64()
	
	# Read section count
	var section_count = file.get_32()
	
	# Read section table
	var sections = []
	for i in range(section_count):
		var section_info = {
			"type": file.get_8(),
			"compression": file.get_8(),
			"offset": file.get_32(),
			"size": file.get_32(),
			"checksum": file.get_32()
		}
		sections.append(section_info)
	
	# Read sections
	var gdl_data = {
		"timestamp": timestamp,
		"version": version
	}
	
	for section_info in sections:
		file.seek(section_info.offset)
		var data = file.get_buffer(section_info.size)
		
		# Verify checksum
		if _calculate_checksum(data) != section_info.checksum:
			push_error("Checksum mismatch in section type %d" % section_info.type)
			continue
		
		# Decompress if needed
		if section_info.compression == CompressionType.GZIP:
			data = data.decompress(data.size() * 4, FileAccess.COMPRESSION_GZIP)
		
		# Parse section based on type
		match section_info.type:
			SectionType.METADATA:
				gdl_data.metadata = bytes_to_var(data)
			SectionType.SOURCE_CODE:
				gdl_data.source_code = data.get_string_from_utf8()
			SectionType.DEPENDENCIES:
				gdl_data.dependencies = bytes_to_var(data)
			SectionType.EXPORTS:
				gdl_data.exports = bytes_to_var(data)
			SectionType.RESOURCES:
				gdl_data.resources = bytes_to_var(data)
	
	file.close()
	print("Loaded GDL binary: " + path)
	return gdl_data

# Create a section structure
static func _create_section(type: SectionType, data: PackedByteArray, compression: CompressionType = CompressionType.NONE) -> Dictionary:
	return {
		"type": type,
		"compression": compression,
		"data": data
	}

# Simple checksum calculation
static func _calculate_checksum(data: PackedByteArray) -> int:
	var checksum = 0
	for byte in data:
		checksum = (checksum + byte) & 0xFFFFFFFF
	return checksum

# Convert .gdl text file to binary
static func convert_gdl_to_binary(gdl_path: String, binary_path: String) -> bool:
	var file = FileAccess.open(gdl_path, FileAccess.READ)
	if not file:
		push_error("Cannot read GDL file: " + gdl_path)
		return false
	
	var source_code = file.get_as_text()
	file.close()
	
	# Parse metadata from comments (simple approach)
	var metadata = _parse_gdl_metadata(source_code)
	
	var gdl_data = {
		"source_code": source_code,
		"metadata": metadata,
		"dependencies": metadata.get("dependencies", []),
		"exports": metadata.get("exports", {}),
		"resources": {}
	}
	
	return save_gdl_binary(binary_path, gdl_data)

# Simple metadata parser (looks for special comments)
static func _parse_gdl_metadata(source: String) -> Dictionary:
	var metadata = {}
	var lines = source.split("\n")
	
	for line in lines:
		line = line.strip_edges()
		if line.begins_with("# @gdl:"):
			var parts = line.substr(7).split(":", 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges()
				var value = parts[1].strip_edges()
				
				# Parse arrays
				if value.begins_with("[") and value.ends_with("]"):
					value = value.substr(1, value.length() - 2)
					metadata[key] = Array(value.split(",")).map(func(s): return s.strip_edges())
				else:
					metadata[key] = value
	
	return metadata

# Example usage functions
static func example_save_module():
	var gdl_data = {
		"metadata": {
			"name": "TestModule",
			"version": "1.0.0",
			"author": "Your Name"
		},
		"source_code": """
# @gdl:name: TestModule
# @gdl:version: 1.0.0
# @gdl:dependencies: [CoreUtils, MathHelper]

extends GDLModule

func _init():
	module_name = "TestModule"

func test_function(a: int, b: String = "default") -> String:
	return "Result: %d, %s" % [a, b]
""",
		"dependencies": ["CoreUtils", "MathHelper"],
		"exports": {
			"functions": ["test_function"],
			"variables": []
		}
	}
	
	save_gdl_binary("res://test_module.gdlb", gdl_data)

static func example_load_module():
	var data = load_gdl_binary("res://test_module.gdlb")
	print("Loaded module: ", data.metadata.name)
	print("Source code length: ", data.source_code.length())
	print("Dependencies: ", data.dependencies)
