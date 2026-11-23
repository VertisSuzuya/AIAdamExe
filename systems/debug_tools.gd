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
#   Ctrl+S   sobota 9:00 doma, celý týden hotový, kamera v keři na Konečné
#   Ctrl+D   totéž, ale bez kamery (v pátek ji nekoupil)
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
		KEY_S:
			_start_saturday(true)
		KEY_D:
			_start_saturday(false)
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


# Sobota 9:00 doma, jako by hráč prošel celý týden: všechny zastávky,
# hodinky, upravený Olda, nálezy středa až pátek na účtu (3 body),
# 2 energetiky za koncert. Sobotní věci (zprávy, nůž, nálezy, důkazy)
# zůstávají neudělané. Ráno se uloží jako checkpoint (usnutí ho načte).
func _start_saturday(with_camera: bool) -> void:
	var g = escoria.globals_manager
	var values: Dictionary = {
		"game_day": 5, "day_minute": 9 * 60, "day_phase": "morning",
		"day_task_done": false, "clock_enabled": true, "no_day_limit": true,
		"shop_open": true,
		# pondělí až pátek hotové
		"tutorial_step": 7, "alarm_set": true, "alarm_taken": true, "battery_taken": true,
		"watch_taken": true, "ticket_taken": true, "drunk_gone": true, "home_talk_done": true,
		"salon_seen": true, "envelope_taken": true, "money_taken": true, "olda_groomed": true,
		"students_talked": true, "cafe_reserved": true, "concert_seen": true, "concert_score": 90,
		"wife_number_known": true, "wife_called": true, "family_met": true,
		"park_waited": true, "phone_no_answer": true, "in_laws_visited": true, "neighbor_talked": true,
		"stop_dejvice": true, "stop_center": true, "stop_in_laws": true,
		"camera_bought": with_camera, "camera_placed": with_camera,
		# sběr: středa až pátek odevzdané, energetiky za koncert
		"find_wed": true, "find_thu": true, "find_fri": true,
		"bag_points": 0, "shop_credit": 3, "shop_credit_explained": true, "energy_drinks": 2,
		# sobota od začátku
		"news_seen": false, "knife_found": false, "knife_taken": false,
		"blackout_0": false, "blackout_1": false, "blackout_2": false,
		"blackout_tram": false, "blackout_park": false, "blackout_home": false,
		"blackout_last": 0, "terminal_seen": false, "ending_kind": "",
		"fatigue_on": false, "fatigue": 0, "drinks_drunk": 0, "fell_asleep": false,
		"fatigue_warn_50": false, "fatigue_warn_70": false, "fatigue_warn_85": false,
		"camera_taken": false, "in_laws_sat_seen": false, "police_left": false,
		"shop_testimony": false, "shop_footage_seen": false, "camera_footage_seen": false,
		"usb_taken": false, "find_sat_street": false, "find_sat_center": false, "find_sat_tram": false,
		"sleep_requested": false, "checkpoint_load_requested": false,
	}
	for key in values:
		g.set_global(key, values[key])

	# Inventář: hodinky, lítačka a energetiky ano, peníze sebral AIdam.
	var inv = escoria.inventory_manager
	for item in ["watches", "ticket", "energy_drink"]:
		if not inv.inventory_has(item):
			inv.add_item(item)
	for item in ["money", "camera", "collected_bag", "knife", "usb_drive", "envelope", "coffee"]:
		if inv.inventory_has(item):
			inv.remove_item(item)

	# Upravený Olda (stejně jako set_animations v salonu).
	var clean: String = "res://characters/olda/olda_clean.tres"
	var anims: Dictionary = {}
	if g.has(escoria.room_manager.GLOBAL_ANIMATION_RESOURCES):
		anims = g.get_global(escoria.room_manager.GLOBAL_ANIMATION_RESOURCES)
	anims["olda"] = clean
	g.set_global(escoria.room_manager.GLOBAL_ANIMATION_RESOURCES, anims, true)

	# Ranní checkpoint, až bude v místnosti klid.
	g.set_global("checkpoint_pending", true)
	var room: String = "res://rooms/oldas_room/oldas_room.tscn"
	var current = escoria.main.current_scene
	if current != null and current.scene_file_path == room:
		# Stejná místnost by Escorii shodila: přes ulici, ať proběhne :apply_time.
		room = "res://rooms/home_street/home_street.tscn"
	_go_to_room(room)
	print("[debug] sobota %s kamery" % ("s" if with_camera else "bez"))
