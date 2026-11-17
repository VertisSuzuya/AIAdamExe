extends Node
# Ladicí zkratky (autoload "debug_tools"). Fungují jen ve vývojové verzi
# (spuštění z editoru), ve vydané hře se vypnou samy.
#
#   Ctrl+šipka nahoru / dolů   další / předchozí den (game_day)
#   Ctrl+šipka doprava / doleva   čas +1 hodina / -1 hodina
#   Ctrl+T   zrychlení času x60 zapnout / vypnout
#   Ctrl+K   denní úkol splněn (day_task_done = true), jde se spát
#   Ctrl+1 až Ctrl+9   skok do místnosti ze seznamu ROOMS
#
# Funguje až po New Game (dokud neexistují globály, nic nedělá).

## Místnosti pro Ctrl+1 až Ctrl+9 (doplňuj podle potřeby).
const ROOMS: Array = [
	"res://rooms/oldas_room/oldas_room.tscn",      # Ctrl+1
	"res://rooms/home_street/home_street.tscn",    # Ctrl+2
	"res://rooms/laboratory/laboratory.tscn",      # Ctrl+3
]

const DAY_NAMES = ["pondělí", "úterý", "středa", "čtvrtek", "pátek", "sobota", "neděle"]

var _normal_speed: float = 1.0
var _fast: bool = false


func _ready() -> void:
	if not OS.is_debug_build():
		set_process_input(false)


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
		KEY_T:
			_toggle_speed()
		KEY_K:
			escoria.globals_manager.set_global("day_task_done", true)
			print("[debug] úkol dne splněn")
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
	# Mezi 7:00 a 1:59 (2:00 by hned spustilo vypršení dne).
	minute = clampi(minute, 7 * 60, 26 * 60 - 1)
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
