extends Node

var failures: int = 0
var state: String = ""
var wreck: bool = false

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	WorldSimulation.set_process(false)
	SignalBus.alife_cargo_queried.connect(_query)
	var ui: CaravanCargoUI = WorldSimulation.cargo_ui
	ui._open("preview")
	check(not ui._escort_button.disabled and ui._ids.size() == 3, "Available escort and sorted cargo render together")
	for entry: Array in [["accepted", "reserved"], ["reward_pending", "pending"], ["paid", "paid"], ["failed", "failed"]]:
		state = str(entry[0])
		ui._refresh()
		check(ui._escort_button.disabled and str(entry[1]) in ui._escort_button.text, "Contract status explains unavailable action: " + state)
	wreck = true
	ui._refresh()
	check(not ui._escort_button.visible and "Salvage" in ui._note.text, "Wreck exposes salvage without live-caravan escort or theft warning")
	wreck = false
	state = "accepted"
	ui._refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	check(viewport_rect.encloses(ui._items.get_global_rect()) and viewport_rect.encloses(ui._escort_button.get_global_rect()), "Cargo list and contract action fit viewport")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://output/alife_escort_ui.png") == OK, "Rendered preview saved")
	ui.close_panel()
	check(not ui._panel.visible, "Panel closes normally")
	print("ALIFE CARGO UI TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _query(_id: String, result: Dictionary) -> void:
	result.merge({"title": "Merchant convoy supplies", "cargo": {"food": 36, "wool": 20, "iron_ore": 8},
		"escort_state": state, "escort_available": state.is_empty() and not wreck, "is_wreck": wreck}, true)
