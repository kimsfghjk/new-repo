@tool
extends McpTestSuite

## Guards the EasyRPG RTP asset bundle that tools/prepare-easyrtp.ps1 generates.
##
## The valuable part of these tests is the GBM2K contract: PawnGrid reads a
## custom data layer named "coll_type" from the painted tilemap layers and stores
## the value as a collision-layer source id, where -1 means EMPTY (walkable).
## A TileSet whose tiles default to 0 (ACTOR) silently freezes every pawn, so the
## explicit -1 on every generated tile is asserted here rather than trusted.
##
## Run: MCP tool `test_run` (suite "assets").

const MANIFEST_PATH := "res://assets/easyrtp.manifest.json"
const CHIPSET_TILESETS := [
	"res://assets/art/easyrtp/tilesets/Dungeon.tres",
	"res://assets/art/easyrtp/tilesets/Exterior.tres",
	"res://assets/art/easyrtp/tilesets/Interior.tres",
	"res://assets/art/easyrtp/tilesets/Ship.tres",
	"res://assets/art/easyrtp/tilesets/World.tres",
	"res://assets/art/easyrtp/tilesets/retro_Dungeon.tres",
	"res://assets/art/easyrtp/tilesets/retro_Exterior.tres",
	"res://assets/art/easyrtp/tilesets/retro_World.tres",
]
const CHIPSET_SIZE := Vector2i(480, 256)
const CHARACTER_SIZE := Vector2i(72, 128)
const CHARACTER_COUNT := 136   # 17 sheets x 8 characters
const MINIMUM_TILE_COUNT := 400


func suite_name() -> String:
	return "assets"


func _manifest() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	assert_true(raw != "", "%s must exist; run tools/prepare-easyrtp.ps1" % MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest must parse as a JSON object")
	return parsed


func test_manifest_lists_assets_that_exist() -> void:
	var manifest: Dictionary = _manifest()
	var files: Dictionary = manifest.get("files", {})
	assert_true(files.size() >= 280, "expected the full bundle, got %d entries" % files.size())
	var missing: Array[String] = []
	for relative in files.keys():
		if not ResourceLoader.exists("res://" + relative):
			missing.append(relative)
	assert_eq(missing.size(), 0, "manifested files missing from disk: %s" % [missing])


func test_manifest_is_pinned_to_a_commit() -> void:
	var manifest: Dictionary = _manifest()
	assert_true(
		String(manifest.get("upstream_commit", "")).length() == 40,
		"manifest must record the full upstream commit sha"
	)
	assert_true(
		not (manifest.get("skipped", []) as Array).is_empty(),
		"MIDI music is deliberately skipped; the manifest should say so"
	)


func test_chipsets_have_expected_dimensions() -> void:
	for name in ["Dungeon", "Exterior", "Interior", "Ship", "World",
			"retro_Dungeon", "retro_Exterior", "retro_World"]:
		var path: String = "res://assets/art/easyrtp/chipsets/%s.png" % name
		var texture: Texture2D = load(path)
		assert_true(texture != null, "%s must load as a texture" % path)
		if texture:
			assert_eq(Vector2i(texture.get_size()), CHIPSET_SIZE,
				"%s must stay %s" % [name, CHIPSET_SIZE])


func test_chipset_tilesets_are_wired_for_gbm2k() -> void:
	for path in CHIPSET_TILESETS:
		var tileset: TileSet = load(path)
		assert_true(tileset != null, "%s must load as a TileSet" % path)
		if tileset == null:
			continue
		assert_eq(tileset.tile_size, Vector2i(16, 16), "%s tile size" % path)

		var layer_names: Array[String] = []
		for index in tileset.get_custom_data_layers_count():
			layer_names.append(tileset.get_custom_data_layer_name(index))
		assert_true(
			layer_names.has("coll_type"),
			"%s must expose the coll_type layer GBM2K reads" % path
		)

		var source: TileSetSource = tileset.get_source(tileset.get_source_id(0))
		assert_true(source is TileSetAtlasSource, "%s needs an atlas source" % path)
		if not (source is TileSetAtlasSource):
			continue
		var atlas: TileSetAtlasSource = source
		assert_true(
			atlas.get_tiles_count() >= MINIMUM_TILE_COUNT,
			"%s registered only %d tiles" % [path, atlas.get_tiles_count()]
		)

		# Every tile must default to -1 (EMPTY / walkable).
		var blocking: Array[String] = []
		for index in atlas.get_tiles_count():
			var coords: Vector2i = atlas.get_tile_id(index)
			var data: TileData = atlas.get_tile_data(coords, 0)
			if data.get_custom_data("coll_type") != -1:
				blocking.append(str(coords))
		assert_eq(
			blocking.size(), 0,
			"%s has tiles that are not walkable: %s" % [path, blocking.slice(0, 8)]
		)


func test_pixel_art_filter_is_nearest() -> void:
	# Every asset in this bundle is 16px pixel art. With the default (Linear)
	# filter Godot blurs them, so the project-wide filter is pinned here.
	var filter: int = ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", -1)
	assert_eq(filter, 0, "canvas default_texture_filter must be 0 (Nearest)")


func test_character_cells_are_gbm2k_sized() -> void:
	var directory := DirAccess.open("res://assets/art/easyrtp/characters")
	assert_true(directory != null, "characters directory must exist")
	if directory == null:
		return

	var wrong: Array[String] = []
	var checked: int = 0
	for file_name in directory.get_files():
		# Godot adds a .import sidecar next to every PNG; those are not assets.
		if not file_name.ends_with(".png"):
			continue
		checked += 1
		var texture: Texture2D = load("res://assets/art/easyrtp/characters/%s" % file_name)
		if texture == null or Vector2i(texture.get_size()) != CHARACTER_SIZE:
			wrong.append(file_name)

	assert_eq(checked, CHARACTER_COUNT, "expected %d character cells" % CHARACTER_COUNT)
	assert_eq(wrong.size(), 0, "unexpected character size: %s" % [wrong.slice(0, 8)])


func test_conversion_actually_keyed_out_pixels() -> void:
	# A file that still has zero transparent pixels would render its flat key
	# colour as if it were art - the exact failure this pipeline exists to stop.
	var samples: Array[String] = [
		"res://assets/art/easyrtp/chipsets/Dungeon.png",
		"res://assets/art/easyrtp/characters/People1_1.png",
		"res://assets/art/easyrtp/monsters/Hornet.png",
	]
	for path in samples:
		var texture: Texture2D = load(path)
		assert_true(texture != null, "%s must load" % path)
		if texture == null:
			continue
		var image: Image = texture.get_image()
		var transparent: int = 0
		var step: int = max(1, image.get_width() / 32)
		for y in range(0, image.get_height(), step):
			for x in range(0, image.get_width(), step):
				if image.get_pixel(x, y).a == 0.0:
					transparent += 1
		assert_true(
			transparent > 0,
			"%s has no transparency - the colour key was not applied" % path
		)


func test_passthrough_families_stay_opaque() -> void:
	# FaceSet, Panorama, Title, System and GameOver are full-canvas artwork: a
	# key conversion there would erase real pixels, so they are copied verbatim.
	var path := "res://assets/art/easyrtp/panoramas/Sky1.png"
	var texture: Texture2D = load(path)
	assert_true(texture != null, "%s must exist" % path)
	if texture == null:
		return
	var image: Image = texture.get_image()
	assert_eq(image.get_size(), Vector2i(640, 480), "panorama stays at native size")
	assert_true(
		image.detect_alpha() == Image.ALPHA_NONE,
		"panoramas must not gain an alpha channel"
	)

