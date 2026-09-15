@tool
extends McpTestSuite

## Smoke suite for the shared project itself.
## Catches "someone broke project settings / disabled the AI plugin" before it
## reaches a teammate's machine.
##
## Run: MCP tool `test_run` (suite_id "project") against the connected editor.

func suite_name() -> String:
	return "project"


func test_project_name_is_set() -> void:
	var project_name: String = ProjectSettings.get_setting("application/config/name", "")
	assert_true(project_name != "", "application/config/name must not be empty")


func test_engine_is_godot_4() -> void:
	var version: Dictionary = Engine.get_version_info()
	assert_eq(version.get("major", 0), 4)


func test_godot_ai_plugin_enabled() -> void:
	var enabled: PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled", PackedStringArray()
	)
	assert_true(
		enabled.has("res://addons/godot_ai/plugin.cfg"),
		"Godot AI plugin must stay enabled for the team toolchain"
	)


func test_game_helper_autoload_present() -> void:
	var autoload: String = ProjectSettings.get_setting("autoload/_mcp_game_helper", "")
	assert_true(
		autoload != "",
		"godot-ai registers _mcp_game_helper; losing it breaks project_run liveness checks"
	)


func test_main_scene_resolves() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene.is_empty():
		skip("main scene is not set yet")
		return
	assert_true(
		ResourceLoader.exists(main_scene),
		"main scene %s must exist" % main_scene
	)