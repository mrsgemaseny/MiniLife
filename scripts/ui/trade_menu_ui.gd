class_name TradeMenuUI
extends Control

# Interactive Buy/Sell trading window opened when bartering with NPCs.

var _current_trader: Node = null
var _trader_stock: Array[String] = ["cooked_meat", "bandage", "arrow", "wood_axe", "stone_pickaxe", "iron_sword", "hunting_bow", "chainmail_armor"]
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
	var panel: Panel = Panel.new()
	panel.position = Vector2(220, 90)
	panel.size = Vector2(760, 480)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(16, 16)
	vbox.size = Vector2(728, 448)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Caravan Barter & Trade"
	vbox.add_child(title)

	_info_label = Label.new()
	_info_label.text = "Select an item to buy or sell."
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
