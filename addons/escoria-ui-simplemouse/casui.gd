extends CanvasLayer

const DAYS = ["PONDĚLÍ", "ÚTERÝ", "STŘEDA", "ČTVRTEK", "PÁTEK", "SOBOTA", "NEDĚLE"]

# Hodnoty se berou z globálů game_day a day_minute (počítá je autoload
# game_clock). Tyhle se použijí jen, dokud globály neexistují (před New Game).
@export_range(0, 6) var day_index: int = 0
@export var minute_of_day: int = 7 * 60   # 7:00

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
	escoria.globals_manager.global_changed.connect(_on_global_changed)
	_update_visibility()
	refresh()


# Escoria posílá signál ještě před uložením nové hodnoty, proto se bere
# new_value ze signálu, ne get_global().
func _on_global_changed(global: String, _old_value, new_value) -> void:
	if global == "game_day":
		day_index = clampi(int(new_value), 0, 6)
		_redraw()
	elif global == "day_minute":
		minute_of_day = int(new_value)
		_redraw()


func refresh() -> void:
	if escoria.globals_manager.has("game_day"):
		day_index = clampi(int(escoria.globals_manager.get_global("game_day")), 0, 6)
	if escoria.globals_manager.has("day_minute"):
		minute_of_day = int(escoria.globals_manager.get_global("day_minute"))
	_redraw()


func _redraw() -> void:
	var m: int = posmod(minute_of_day, 1440)
	den_label.text = DAYS[day_index]
	cas_label.text = "%02d:%02d" % [floori(m / 60.0), m % 60]


func _update_visibility() -> void:
	visible = not (pause_menu.visible or main_menu.visible)
