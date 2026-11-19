class_name BiomeParams
extends RefCounted

const DOMINANT_SHARE: float = 0.85

var elevation: float
var temperature: float
var moisture: float
var relief: float


func _init(base_elevation: float, base_temperature: float, base_moisture: float, relief_amplitude: float) -> void:
	elevation = base_elevation
	temperature = base_temperature
	moisture = base_moisture
	relief = relief_amplitude


# WorldDataLoader normalizes the WorldStudio "sands" code to the game's "desert" family.
# Temperature is measured at the anchor elevation, before noise.
static func for_family(family: String) -> BiomeParams:
	match family:
		"plains":
			return BiomeParams.new(0.32, 0.52, 0.50, 0.08)
		"forest":
			return BiomeParams.new(0.40, 0.45, 0.70, 0.10)
		"mountains":
			return BiomeParams.new(0.80, 0.22, 0.28, 0.20)
		"desert":
			return BiomeParams.new(0.30, 0.82, 0.14, 0.07)
	return null
