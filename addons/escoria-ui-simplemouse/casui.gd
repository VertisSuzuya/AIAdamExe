extends CanvasLayer

const DAYS = ["PONDĚLÍ", "ÚTERÝ", "STŘEDA", "ČTVRTEK", "PÁTEK", "SOBOTA", "NEDĚLE"]

# Místnost, kde Olda vidí čas i bez hodinek (digitální budík).
const CLOCK_ROOM = "oldas_room"

# Hodnoty se berou z globálů game_day a day_minute (počítá je autoload
# game_clock). Tyhle se použijí jen, dokud globály neexistují (před New Game).
@export_range(0, 6) var day_index: int = 0
@export var minute_of_day: int = 9 * 60   # 9:00

# Čas je vidět jen s hodinkami (watch_taken) nebo v Oldově pokoji.
var has_watch: bool = false
var current_room: String = ""

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
	match global:
		"game_day":
			day_index = clampi(int(new_value), 0, 6)
		"day_minute":
			minute_of_day = int(new_value)
		"watch_taken":
			has_watch = bool(new_value)
		escoria.room_manager.GLOBAL_CURRENT_SCENE:
			current_room = str(new_value)
		_:
			return
	_redraw()


func refresh() -> void:
	var g = escoria.globals_manager
	if g.has("game_day"):
		day_index = clampi(int(g.get_global("game_day")), 0, 6)
	if g.has("day_minute"):
		minute_of_day = int(g.get_global("day_minute"))
	if g.has("watch_taken"):
		has_watch = bool(g.get_global("watch_taken"))
	if g.has(escoria.room_manager.GLOBAL_CURRENT_SCENE):
		current_room = str(g.get_global(escoria.room_manager.GLOBAL_CURRENT_SCENE))
	_redraw()



func _redraw() -> void:
	# Po půlnoci (day_minute >= 1440) už je další den, i když game_day
	# se mění až spánkem (v sobotu se nespí, noc běží do neděle).
	den_label.text = DAYS[clampi(day_index + floori(minute_of_day / 1440.0), 0, 6)]
	if has_watch or current_room == CLOCK_ROOM:
		var m: int = posmod(minute_of_day, 1440)
		cas_label.text = "%02d:%02d" % [floori(m / 60.0), m % 60]
	else:
		cas_label.text = "##:##"


func _update_visibility() -> void:
	visible = not (pause_menu.visible or main_menu.visible)
