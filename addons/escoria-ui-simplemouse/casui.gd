extends CanvasLayer

const DAYS = ["PONDĚLÍ", "ÚTERÝ", "STŘEDA", "ČTVRTEK", "PÁTEK", "SOBOTA", "NEDĚLE"]

# Filler hodnoty, jdou měnit v Inspectoru.
@export_range(0, 6) var day_index: int = 0
@export var minute_of_day: int = 19 * 60 + 30   # 19:30

@onready var den_label: Label = $TextureRect/Den
@onready var cas_label: Label = $TextureRect/Cas
@onready var pause_menu = get_node("../ui/pause_menu")
@onready var main_menu = get_node("../ui/main_menu")


func _ready() -> void:
	# Aby hodiny nechytaly kliknutí do hry.
	for n in [$TextureRect, den_label, cas_label]:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_menu.visibility_changed.connect(_update_visibility)
	main_menu.visibility_changed.connect(_update_visibility)
	_update_visibility()
	refresh()


# Později sem místo filler hodnot přijdou game_day a day_minute z globálů.
func refresh() -> void:
	var m: int = posmod(minute_of_day, 1440)
	den_label.text = DAYS[day_index]
	cas_label.text = "%02d:%02d" % [floori(m / 60.0), m % 60]


func _update_visibility() -> void:
	visible = not (pause_menu.visible or main_menu.visible)
