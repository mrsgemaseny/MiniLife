class_name CurrencyPolicy
extends RefCounted

# One rate throughout the world: travel cannot create money by conversion.
const SILVER_PER_GOLD: int = 20

static func total_value(inventory: InventoryComponent) -> int:
	return (inventory.gold + inventory.count_of("gold_coin")) * SILVER_PER_GOLD + inventory.silver + inventory.count_of("silver_coin")

static func spend_value(inventory: InventoryComponent, silver_value: int) -> bool:
	if silver_value <= 0 or total_value(inventory) < silver_value:
		return false
	for item: String in ["silver_coin", "gold_coin"]:
		var coins: int = inventory.count_of(item)
		if coins > 0:
			inventory.remove_item(item, coins)
			if item == "gold_coin":
				inventory.add_gold(coins)
			else:
				inventory.add_silver(coins)
	if inventory.silver >= silver_value:
		return inventory.spend_silver(silver_value)
	var shortfall: int = silver_value - inventory.silver
	var gold_needed: int = int(ceil(float(shortfall) / float(SILVER_PER_GOLD)))
	inventory.spend_silver(inventory.silver)
	inventory.spend_gold(gold_needed)
	inventory.add_silver(gold_needed * SILVER_PER_GOLD - shortfall)
	return true

static func exchange(inventory: InventoryComponent, to_gold: bool, amount: int) -> bool:
	if inventory == null or amount <= 0 or amount > 100000000:
		return false
	var source: String = "silver_coin" if to_gold else "gold_coin"
	var balance: int = inventory.silver if to_gold else inventory.gold
	var cost: int = amount * SILVER_PER_GOLD if to_gold else amount
	if balance + inventory.count_of(source) < cost:
		return false
	var wallet_cost: int = mini(balance, cost)
	if to_gold:
		inventory.spend_silver(wallet_cost)
	else:
		inventory.spend_gold(wallet_cost)
	if cost > wallet_cost:
		inventory.remove_item(source, cost - wallet_cost)
	# Credit only the wallet; crediting a coin stack as well doubles the payout.
	if to_gold:
		inventory.add_gold(amount)
	else:
		inventory.add_silver(amount * SILVER_PER_GOLD)
	return true
