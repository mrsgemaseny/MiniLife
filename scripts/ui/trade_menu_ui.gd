class_name TradeMenuUI
extends Control

# Interactive Buy/Sell trading window opened when bartering with NPCs.

var _current_trader: Node = null
const DEFAULT_STOCK: Array[String] = ["bread", "cooked_food", "bandage", "medicine", "arrow", "stone_axe", "stone_pickaxe", "iron_sword", "hunting_bow", "iron_chainmail"]
var _trader_stock: Array[String] = DEFAULT_STOCK.duplicate()
var _stock_list: ItemList = null
var _player_list: ItemList = null
var _player_item_ids: Array[String] = []
var _info_label: Label = null
var _amnesty_button: Button
var _amnesty_quote: int = 0

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

func _make_mc_btn_style(hover: bool = false) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.68, 0.68, 0.68, 1.0) if hover else Color(0.58, 0.58, 0.58, 1.0)
	sb.border_color = Color(0.22, 0.22, 0.22, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# 1. Dark World Dimmer (Minecraft authentic - NO BLUE, NO TEXTURE)
	var dimmer: ColorRect = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.65)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)
	move_child(dimmer, 0)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360.0
	panel.offset_top = -250.0
	panel.offset_right = 360.0
	panel.offset_bottom = 250.0
	panel.custom_minimum_size = Vector2(720.0, 500.0)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.776, 0.776, 0.776, 1.0) # Solid neutral grey
	sb.border_color = Color(0.22, 0.22, 0.22, 1.0) # Dark pixel border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var hdr_row: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "Торговля и обмен каравана"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.modulate = Color(0.24, 0.24, 0.24, 1.0) # Minecraft dark text #3f3f3f
	hdr_row.add_child(title)

	var close_btn_top: Button = Button.new()
	close_btn_top.text = " ✕ "
	close_btn_top.add_theme_font_size_override("font_size", 11)
	close_btn_top.add_theme_color_override("font_color", Color(0.24, 0.24, 0.24, 1.0))
	close_btn_top.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	close_btn_top.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	close_btn_top.pressed.connect(close_trade)
	hdr_row.add_child(close_btn_top)
	vbox.add_child(hdr_row)

	_info_label = Label.new()
	_info_label.text = "Выберите предмет для покупки или продажи."
	_info_label.add_theme_font_size_override("font_size", 10)
	_info_label.modulate = Color(0.35, 0.35, 0.35, 1.0)
	vbox.add_child(_info_label)

	_amnesty_button = Button.new()
	_amnesty_button.hide()
	_amnesty_button.pressed.connect(_on_amnesty_pressed)
	vbox.add_child(_amnesty_button)

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

	var buy_gold_btn: Button = Button.new()
	buy_gold_btn.text = "Exchange: Silver -> 1 Gold"
	buy_gold_btn.pressed.connect(_on_buy_gold_pressed)
	btn_row.add_child(buy_gold_btn)

	var sell_gold_btn: Button = Button.new()
	sell_gold_btn.text = "Exchange: 1 Gold -> Silver"
	sell_gold_btn.pressed.connect(_on_sell_gold_pressed)
	btn_row.add_child(sell_gold_btn)

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
	var market: Dictionary = {}
	SignalBus.alife_market_queried.emit(_current_trader, market)
	_amnesty_quote = int(market.get("amnesty_silver", 0))
	_amnesty_button.visible = _amnesty_quote > 0
	_amnesty_button.text = "Pay amnesty — %d silver" % _amnesty_quote
	var managed: bool = bool(market.get("managed", false))
	if managed:
		_trader_stock.assign((market.get("items", {}) as Dictionary).keys())
		_trader_stock.sort()
	else:
		_trader_stock.assign(DEFAULT_STOCK)
	var parameters: Dictionary = _trade_parameters()
	for item_id in _trader_stock:
		var def: Dictionary = DataRegistry.get_item(item_id)
		var val: int = maxi(1, int(round(float(def.get("value", 8)) * 1.25)))
		if managed:
			var quote: Dictionary = MarketPricing.quote(item_id, market, true, parameters.skill, parameters.memory)
			if quote.is_empty():
				_stock_list.add_item("Unavailable")
			else:
				_stock_list.add_item("[BUY] %s x%d - %d %s" % [str(def.get("name", item_id)), int(quote["available"]), int(quote["price"]), str(quote["currency"])])
		else:
			_stock_list.add_item("[BUY] %s - %d Gold" % [str(def.get("name", item_id)), val])

	_player_list.clear()
	_player_item_ids.clear()
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.get("inventory") is InventoryComponent:
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if _info_label != null:
			var is_city: bool = false
			if _current_trader != null and "is_in_city" in _current_trader:
				is_city = bool(_current_trader.get("is_in_city"))
			var rate: int = CurrencyPolicy.SILVER_PER_GOLD
			var loc_name: String = str(market.get("name", "Trade City" if is_city else "Village / Frontier"))
			_info_label.text = "Wealth: %d Gold | %d Silver  [Rate at %s: 1 Gold = %d Silver]" % [inv.gold + inv.count_of("gold_coin"), inv.silver + inv.count_of("silver_coin"), loc_name, rate]
			if market.has("close_reason"):
				_info_label.text = "%s  |  %d gold, %d silver" % [market["close_reason"], inv.gold, inv.silver]
		for slot in inv.slots:
			var iid: String = str(slot.get("item_id", ""))
			var cnt: int = int(slot.get("count", 0))
			if iid.is_empty() or cnt <= 0:
				continue
			var def: Dictionary = DataRegistry.get_item(iid)
			var sell_val: int = maxi(1, int(round(float(def.get("value", 5)) * 0.65)))
			_player_item_ids.append(iid)
			if managed:
				var quote: Dictionary = MarketPricing.quote(iid, market, false, parameters.skill, parameters.memory)
				if quote.is_empty():
					_player_list.add_item("%s x%d (not traded)" % [str(def.get("name", iid)), cnt])
				else:
					_player_list.add_item("[SELL] %s x%d (+%d %s ea)" % [str(def.get("name", iid)), cnt, int(quote["price"]), str(quote["currency"])])
			else:
				_player_list.add_item("[SELL] %s x%d (+%d Gold ea)" % [str(def.get("name", iid)), cnt, sell_val])

func _on_amnesty_pressed() -> void:
	var result: Dictionary = {}
	SignalBus.local_amnesty_requested.emit(_current_trader, _amnesty_quote, result)
	_refresh_lists()
	if result.has("message"):
		SignalBus.notification_posted.emit(str(result["message"]))

func _trade_parameters() -> Dictionary:
	var result: Dictionary = {"skill": 0.0, "memory": 1.0}
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.get("skills") is SkillsComponent:
		var skills: SkillsComponent = player.get("skills") as SkillsComponent
		result["skill"] = clampf(float(skills.get_level("trading") + skills.get_level("persuasion")) * 0.004, 0.0, 0.30)
	if is_instance_valid(_current_trader) and _current_trader.get("memory") is MemoryComponent:
		result["memory"] = (_current_trader.get("memory") as MemoryComponent).get_price_discount_multiplier()
	return result

func _on_buy_gold_pressed() -> void:
	SignalBus.currency_exchange_requested.emit(_current_trader, true, 1)
	_refresh_lists()

func _on_sell_gold_pressed() -> void:
	SignalBus.currency_exchange_requested.emit(_current_trader, false, 1)
	_refresh_lists()

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
