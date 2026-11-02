class_name TradeMenuUI
extends Control

# Interactive Buy/Sell trading window opened when bartering with NPCs.

var _current_trader: Node = null
var _trader_stock: Array[String] = ["bread", "cooked_food", "bandage", "medicine", "arrow", "stone_axe", "stone_pickaxe", "iron_sword", "hunting_bow", "iron_chainmail"]
var _stock_list: ItemList = null
var _player_list: ItemList = null
var _player_item_ids: Array[String] = []
var _info_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.trade_session_requested.connect(_on_trade_session_requested)
	SignalBus.ui_close_all_requested.connect(close_trade)
	SignalBus.inventory_changed.connect(func(_e: Node, _s: Dictionary) -> void:
		if visible:
			_refresh_lists()
	)

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# 1. Full-screen dark medieval background texture
	var bg_tex: TextureRect = TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.offset_left = 0
	bg_tex.offset_top = 0
	bg_tex.offset_right = 0
	bg_tex.offset_bottom = 0
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	var bg_img_path: String = "res://assets/sprites/ui/dark_medieval_ui_bg.jpg"
	if ResourceLoader.exists(bg_img_path) or FileAccess.file_exists(ProjectSettings.globalize_path(bg_img_path)):
		bg_tex.texture = load(bg_img_path) as Texture2D
	bg_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg_tex)
	move_child(bg_tex, 0)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 36.0
	panel.offset_top = 28.0
	panel.offset_right = -36.0
	panel.offset_bottom = -28.0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.82)
	sb.border_color = Color(0.25, 0.28, 0.34, 0.90)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var hdr_row: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "MERCHANT CARAVAN BARTER & TRADE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.88, 0.86, 0.82)
	hdr_row.add_child(title)

	var close_btn_top: Button = Button.new()
	close_btn_top.text = " [X] Close "
	close_btn_top.add_theme_font_size_override("font_size", 11)
	close_btn_top.pressed.connect(close_trade)
	hdr_row.add_child(close_btn_top)
	vbox.add_child(hdr_row)

	_info_label = Label.new()
	_info_label.text = "Select an item to buy or barter from your inventory."
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.modulate = Color(0.70, 0.74, 0.80)
	vbox.add_child(_info_label)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	_stock_list = ItemList.new()
	_stock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_stock_list)

	_player_list = ItemList.new()
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_player_list)

	var btn_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(btn_row)

	var buy_btn: Button = Button.new()
	buy_btn.text = "Buy Selected (1x)"
	buy_btn.pressed.connect(_on_buy_pressed)
	btn_row.add_child(buy_btn)

	var sell_btn: Button = Button.new()
	sell_btn.text = "Sell Selected (1x)"
	sell_btn.pressed.connect(_on_sell_pressed)
	btn_row.add_child(sell_btn)

	var close_btn: Button = Button.new()
	close_btn.text = "Close Trade"
	close_btn.pressed.connect(close_trade)
	btn_row.add_child(close_btn)

func _on_trade_session_requested(trader: Node) -> void:
	_current_trader = trader
	visible = true
	SignalBus.ui_panel_toggled.emit("trade", true, true)
	_refresh_lists()

func close_trade() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit("trade", false, true)

func _refresh_lists() -> void:
	if _stock_list == null or _player_list == null:
		return
	_stock_list.clear()
	for item_id in _trader_stock:
		var def: Dictionary = DataRegistry.get_item(item_id)
		var val: int = maxi(1, int(round(float(def.get("value", 8)) * 1.25)))
		_stock_list.add_item("[BUY] %s - %d Gold" % [str(def.get("name", item_id)), val])

	_player_list.clear()
	_player_item_ids.clear()
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.get("inventory") is InventoryComponent:
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if _info_label != null:
			_info_label.text = "Your Gold: %d | Select an item on the left to Buy, or on the right to Sell." % inv.gold
		for slot in inv.slots:
			var iid: String = str(slot.get("item_id", ""))
			var cnt: int = int(slot.get("count", 0))
			var def: Dictionary = DataRegistry.get_item(iid)
			var sell_val: int = maxi(1, int(round(float(def.get("value", 5)) * 0.65)))
			_player_item_ids.append(iid)
			_player_list.add_item("[SELL] %s x%d (+%d Gold ea)" % [str(def.get("name", iid)), cnt, sell_val])

func _on_buy_pressed() -> void:
	var sel: PackedInt32Array = _stock_list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	if idx >= 0 and idx < _trader_stock.size():
		var item_id: String = _trader_stock[idx]
		SignalBus.trade_transaction_requested.emit(_current_trader, item_id, 1, true)
		_refresh_lists()

func _on_sell_pressed() -> void:
	var sel: PackedInt32Array = _player_list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	if idx >= 0 and idx < _player_item_ids.size():
		var item_id: String = _player_item_ids[idx]
		SignalBus.trade_transaction_requested.emit(_current_trader, item_id, 1, false)
		_refresh_lists()
