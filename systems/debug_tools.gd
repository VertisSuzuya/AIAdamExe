extends Node
# Ladicí zkratky (autoload "debug_tools"). Fungují jen ve vývojové verzi
# (spuštění z editoru), ve vydané hře se vypnou samy.
#
#   Ctrl+šipka nahoru / dolů   další / předchozí den (game_day)
#   Ctrl+šipka doprava / doleva   čas +1 hodina / -1 hodina
#   Ctrl+T   zrychlení času x60 zapnout / vypnout
#   Ctrl+K   denní úkol splněn (day_task_done = true), jde se spát
#   Ctrl+1 až Ctrl+8   skok do místnosti ze seznamu ROOMS
#   Ctrl+W   hodinky zapnout / vypnout (čas vidět i mimo pokoj)
#   Ctrl+R   rychlá chůze Oldy zapnout / vypnout (doběhne skoro hned)
#   Ctrl+C   rovnou na koncert (středa, studenti a kavárna hotové)
#
# Funguje až po New Game (dokud neexistují globály, nic nedělá).

## Místnosti pro Ctrl+1 až Ctrl+8 (doplňuj podle potřeby).
const ROOMS: Array = [
	"res://rooms/oldas_room/oldas_room.tscn",                # Ctrl+1
	"res://rooms/home_street/home_street.tscn",              # Ctrl+2
	"res://rooms/corner_shop/corner_shop.tscn",              # Ctrl+3
	"res://rooms/tram/tram.tscn",                            # Ctrl+4
	"res://rooms/fit_front/fit_front.tscn",                  # Ctrl+5
	"res://rooms/city_center/city_center.tscn",              # Ctrl+6
	"res://rooms/in_laws_house/in_laws_house.tscn",          # Ctrl+7
	"res://rooms/laboratory/laboratory.tscn",                # Ctrl+8
]

const DAY_NAMES = ["pondělí", "úterý", "středa", "čtvrtek", "pátek", "sobota", "neděle"]
const FAST_WALK_SPEED = 20000

var _normal_speed: float = 1.0
var _fast: bool = false
var _fast_walk: bool = false
var _normal_walk_speed: int = 300


func _ready() -> void:
	if not OS.is_debug_build():
		set_process_input(false)
		set_process(false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not event.ctrl_pressed:
		return
	if escoria.globals_manager == null or not escoria.globals_manager.has("game_day"):
		return

	match event.keycode:
		KEY_UP:
			_set_day(_get_int("game_day") + 1)
		KEY_DOWN:
			_set_day(_get_int("game_day") - 1)
		KEY_RIGHT:
			_set_minute(_get_int("day_minute") + 60)
		KEY_LEFT:
			_set_minute(_get_int("day_minute") - 60)
		KEY_W:
			_toggle_watch()
		KEY_T:
			_toggle_speed()
		KEY_K:
			escoria.globals_manager.set_global("day_task_done", true)
			print("[debug] úkol dne splněn")
		KEY_R:
			_fast_walk = not _fast_walk
			print("[debug] rychlá chůze: %s" % ("ano" if _fast_walk else "ne"))
		KEY_C:
			_start_concert()
		_:
			var index: int = event.keycode - KEY_1
			if index >= 0 and index < ROOMS.size():
				_go_to_room(ROOMS[index])
				get_viewport().set_input_as_handled()
				return
			return
	get_viewport().set_input_as_handled()


func _get_int(global_name: String) -> int:
	return int(escoria.globals_manager.get_global(global_name))


func _set_day(day: int) -> void:
	day = clampi(day, 0, 6)
	escoria.globals_manager.set_global("game_day", day)
	escoria.globals_manager.set_global("day_task_done", false)
	# Hodiny musí běžet i po skoku z laboratoře.
	escoria.globals_manager.set_global("clock_enabled", true)
	print("[debug] den: %s" % DAY_NAMES[day])


func _set_minute(minute: int) -> void:
	# Mezi 9:00 a 0:59 (1:00 by hned spustilo vypršení dne).
	minute = clampi(minute, 9 * 60, 25 * 60 - 1)
	escoria.globals_manager.set_global("day_minute", minute)
	print("[debug] čas: %02d:%02d" % [(minute / 60) % 24, minute % 60])


func _toggle_speed() -> void:
	_fast = not _fast
	if _fast:
		_normal_speed = game_clock.minutes_per_second
		game_clock.minutes_per_second = 60.0
	else:
		game_clock.minutes_per_second = _normal_speed
	print("[debug] rychlost času: %s min/s" % game_clock.minutes_per_second)


# Stejně jako room selector Escorie (ui_library/tools/room_select).
func _go_to_room(path: String) -> void:
	var current = escoria.main.current_scene
	# change_scene na stejnou místnost Escorii shodí (viz CLAUDE.md).
	if current != null and current.scene_file_path == path:
		print("[debug] už jsi v %s" % path)
		return
	escoria.globals_manager.set_global(
		escoria.room_manager.GLOBAL_FORCE_LAST_SCENE_NULL, true, true
	)
	escoria.event_manager.interrupt()
	escoria.room_manager.change_scene_to_file(path, false)
	print("[debug] místnost: %s" % path)


# Hodinky zapnout/vypnout: v UI je pak vidět čas všude (casui.gd čte
# watch_taken). Do inventáře se nepřidávají, jde jen o zobrazení času.
func _toggle_watch() -> void:
	var has_watch: bool = escoria.globals_manager.has("watch_taken") \
			and bool(escoria.globals_manager.get_global("watch_taken"))
	escoria.globals_manager.set_global("watch_taken", not has_watch)
	print("[debug] hodinky: %s" % ("ano" if not has_watch else "ne"))


# Rychlá chůze: Olda je v každé místnosti nová instance, proto se rychlost
# nastavuje každý snímek (po změně místnosti by se vrátila na výchozí).
func _process(_delta: float) -> void:
	if escoria.object_manager == null or not escoria.object_manager.has("olda"):
		return
	var olda = escoria.object_manager.get_object("olda").node
	if not is_instance_valid(olda):
		return
	if _fast_walk:
		if olda.speed != FAST_WALK_SPEED:
			_normal_walk_speed = olda.speed
			olda.speed = FAST_WALK_SPEED
	elif olda.speed == FAST_WALK_SPEED:
		olda.speed = _normal_walk_speed


# Rovnou na koncert: středa, po studentech i kavárně, těsně před 18:00.
func _start_concert() -> void:
	var g = escoria.globals_manager
	g.set_global("game_day", 2)
	g.set_global("clock_enabled", true)
	g.set_global("students_talked", true)
	g.set_global("cafe_reserved", true)
	g.set_global("concert_seen", false)
	g.set_global("day_minute", 1075)
	_go_to_room("res://rooms/concert/concert.tscn")
	print("[debug] koncert")
