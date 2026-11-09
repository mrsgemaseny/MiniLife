extends Node

var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")


func run() -> void:
	GameManager.set_process(false)
	GameManager._open_blocking_panels.clear()
	GameManager._application_focused = true
	GameManager._state = GameManager.State.PLAYING
	check(Config.SECONDS_PER_GAME_HOUR * Config.HOURS_PER_DAY == 1440.0, "Full day is not 24 real minutes")
	GameManager._day = 1
	GameManager._hour = 6.0
	GameManager._advance_clock(30.0)
	check(is_equal_approx(GameManager.get_hour(), 6.5), "Clock does not use slower time scale")
	GameManager._hour = 23.75
	GameManager._advance_clock(30.0)
	check(GameManager.get_day() == 2 and is_equal_approx(GameManager.get_hour(), 0.25), "Midnight rollover broke")
	GameManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(GameManager.is_paused() and get_tree().paused, "Alt-tab did not pause the world")
	var hour: float = GameManager.get_hour()
	var autosave: float = GameManager._autosave_elapsed
	GameManager._process(30.0)
	check(GameManager.get_hour() == hour and GameManager._autosave_elapsed == autosave, "Clock/autosave advances out of focus")
	GameManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	GameManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not GameManager.is_paused() and not get_tree().paused, "Focus did not restore auto-paused game")
	GameManager.pause()
	GameManager._on_application_focus_lost()
	GameManager._on_application_focus_gained()
	check(GameManager.is_paused() and get_tree().paused, "Focus removed a manual pause")
	GameManager.resume()
	SignalBus.ui_panel_toggled.emit("inventory", true, true)
	GameManager._on_application_focus_lost()
	GameManager._on_application_focus_gained()
	check(GameManager.is_paused(), "Focus removed a menu pause")
	SignalBus.ui_panel_toggled.emit("inventory", false, true)
	check(not GameManager.is_paused(), "Closing menu no longer resumes")
	# Closing a panel while unfocused must not resume in the background.
	SignalBus.ui_panel_toggled.emit("inventory", true, true)
	GameManager._on_application_focus_lost()
	SignalBus.ui_panel_toggled.emit("inventory", false, true)
	check(GameManager.is_paused() and get_tree().paused, "Panel close resumed in background")
	GameManager._on_application_focus_gained()
	check(not GameManager.is_paused(), "Deferred resume did not occur on return")
	# A menu opened after focus loss continues to own the pause after returning.
	GameManager._on_application_focus_lost()
	SignalBus.ui_panel_toggled.emit("pause", true, true)
	GameManager._on_application_focus_gained()
	check(GameManager.is_paused(), "Auto-resume bypassed an open menu")
	SignalBus.ui_panel_toggled.emit("pause", false, true)
	check(not GameManager.is_paused(), "Menu could not release transferred focus pause")
	GameManager._state = GameManager.State.DEAD
	GameManager._on_application_focus_lost()
	GameManager._on_application_focus_gained()
	check(GameManager.is_dead(), "Focus restored a dead game")
	GameManager._state = GameManager.State.BOOT
	get_tree().paused = false
	print("TIME_FOCUS_RUNTIME: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
