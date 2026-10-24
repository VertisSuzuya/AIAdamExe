extends Node
# Herní hodiny (autoload "game_clock").
#
# Čas je uložený v globálech Escorie, takže přežije uložení a načtení hry:
#   game_day   0 = pondělí ... 6 = neděle
#   day_minute minuty od půlnoci dne (7:00 = 420, 2:00 ráno = 26 * 60 = 1560)
#   day_phase  "morning" / "afternoon" / "evening" / "night"
#
# Hodiny běží jen ve stavu DEFAULT (stojí v dialozích, při načítání a v pauze,
# pauza zastaví celý strom). Před New Game globály neexistují, takže nic nedělají.
#
# Změna části dne, když je hráč v místnosti ("mrknutí"):
#   :time_fade_out (game.esc) -> nastaví se day_phase -> :update_schedule
#   (game.esc) -> :apply_time (skript místnosti, pokud ji má) -> :time_fade_in
# Po New Game a načtení hry (day_phase už sedí) proběhne jen :update_schedule.
#
# :apply_time místnosti se spouští i při příchodu do místnosti, hned po :setup
# (ještě před prolnutím), a po načtení hry (tam Escoria :setup nespouští).
#
# Ve 2:00 se zastaví a spustí :day_timeout z game.esc.

## Kolik herních minut uběhne za jednu reálnou sekundu.
@export var minutes_per_second: float = 60

const DAY_START: int = 7 * 60    # 7:00
const DAY_END: int = 26 * 60     # 2:00 ráno dalšího dne

# Začátky částí dne (v minutách), seřazené od nejpozdější.
const PHASES: Array = [
	[22 * 60, "night"],
	[18 * 60, "evening"],
	[12 * 60, "afternoon"],
	[0, "morning"],
]

const EVENT_APPLY_TIME: String = "apply_time"

var _minute_accumulator: float = 0.0
# Pro jaký den a část dne naposledy proběhl rozvrh ("den_cast").
var _schedule_key: String = ""
# Právě běží posloupnost kroků (aby se nespouštělo víckrát).
var _busy: bool = false
# Zbývající kroky posloupnosti: Callable, nebo [ESCScript, název události].
var _steps: Array = []
# Událost, na kterou čekáme, a klíč rozvrhu, pro který běží.
var _pending_event: String = ""
var _pending_key: String = ""
# Den už vypršel, čekáme, až skript posune čas zpátky.
var _timed_out: bool = false
# Místnost, pro kterou už proběhla :apply_time (aby se nespouštěla znovu).
var _applied_room: Node = null


func _process(delta: float) -> void:
	_connect_signals()
	if _busy:
		_check_pending()
		return
	if not _is_running():
		return

	var room: ESCRoom = escoria.main.current_scene

	# Místnost bez :setup nebo po načtení hry: :apply_time ještě neproběhla.
	if room != _applied_room:
		_applied_room = room
		if _room_has_apply_time(room):
			_run_steps([[room.compiled_script, EVENT_APPLY_TIME]])
			return

	var minute: int = int(escoria.globals_manager.get_global("day_minute"))

	if minute >= DAY_END:
		if not _timed_out:
			_timed_out = true
			_run_steps([[escoria.start_script, "day_timeout"]])
		return
	_timed_out = false

	var phase: String = phase_for_minute(minute)
	var key: String = "%d_%s" % [int(escoria.globals_manager.get_global("game_day")), phase]

	# Čas přešel do jiné části dne: mrknutí.
	if escoria.globals_manager.get_global("day_phase") != phase:
		_pending_key = key
		var steps: Array = [
			[escoria.start_script, "time_fade_out"],
			func(): escoria.globals_manager.set_global("day_phase", phase),
			[escoria.start_script, "update_schedule"],
		]
		if _room_has_apply_time(room):
			steps.append([room.compiled_script, EVENT_APPLY_TIME])
		steps.append([escoria.start_script, "time_fade_in"])
		_run_steps(steps)
		return

	# Rozvrh ještě neproběhl (po New Game, načtení hry, změně dne skriptem).
	if key != _schedule_key:
		_pending_key = key
		_run_steps([[escoria.start_script, "update_schedule"]])
		return

	# Běh času.
	_minute_accumulator += delta * minutes_per_second
	if _minute_accumulator >= 1.0:
		var whole: int = int(_minute_accumulator)
		_minute_accumulator -= whole
		escoria.globals_manager.set_global("day_minute", mini(minute + whole, DAY_END))


## Vrátí část dne pro danou minutu. Minuty po půlnoci jdou dál (0:30 = 1470),
## takže se neořezávají na 24 h, jinak by 0:00–2:00 vyšlo jako ráno.
static func phase_for_minute(minute: int) -> String:
	for p in PHASES:
		if minute >= p[0]:
			return p[1]
	return "morning"


# Hodiny běží jen ve hře (po New Game nebo načtení), v místnosti
# a když se zrovna nic jiného neděje (žádný dialog, načítání).
func _is_running() -> bool:
	if not escoria.globals_manager.has("day_minute"):
		return false
	if escoria.main == null or not (escoria.main.current_scene is ESCRoom):
		return false
	return escoria.current_state == escoria.GameState.DEFAULT


func _room_has_apply_time(room: ESCRoom) -> bool:
	return room != null and room.compiled_script != null \
			and room.compiled_script.has_event_with_target(EVENT_APPLY_TIME)


func _connect_signals() -> void:
	if escoria.event_manager == null:
		return
	if not escoria.event_manager.event_finished.is_connected(_on_event_finished):
		escoria.event_manager.event_finished.connect(_on_event_finished)
	if not escoria.event_manager.event_started.is_connected(_on_event_started):
		escoria.event_manager.event_started.connect(_on_event_started)


# Spustí kroky postupně. Na události se nečeká přes await: Escoria při změně
# scény frontu vymaže a vymazaná událost signál event_finished nepošle, takže
# by await visel navždy. Dokončení hlídá _on_event_finished, zmizení
# z fronty _check_pending.
func _run_steps(steps: Array) -> void:
	_steps = steps
	_busy = true
	_next_step()


func _next_step() -> void:
	while not _steps.is_empty():
		var step = _steps.pop_front()
		if step is Callable:
			step.call()
			continue
		var script: ESCScript = step[0]
		var event_name: String = step[1]
		if script == null or not script.has_event_with_target(event_name):
			continue
		_pending_event = event_name
		escoria.event_manager.queue_event_from_esc(
			script, event_name, escoria.event_manager.CHANNEL_FRONT, false
		)
		return
	_pending_event = ""
	_busy = false


func _on_event_finished(return_code: int, event_name: String) -> void:
	if not _busy or event_name != _pending_event:
		return
	if event_name == "update_schedule" and return_code == ESCExecution.RC_OK:
		_schedule_key = _pending_key
	_pending_event = ""
	_next_step()


# Při příchodu do místnosti zařadí :apply_time hned za její :setup, takže
# proběhne ještě před prolnutím do místnosti. Escoria během změny scény
# nepřijímá nové události, proto force = true (stejně to dělá room manager
# se :setup).
func _on_event_started(event_name: String) -> void:
	if event_name != escoria.event_manager.EVENT_SETUP:
		return
	var room = escoria.main.current_scene if escoria.main else null
	if not (room is ESCRoom) or not _room_has_apply_time(room):
		return
	var setup_event = room.compiled_script.get_event_with_target(event_name)
	if escoria.event_manager.get_running_event(escoria.event_manager.CHANNEL_FRONT) != setup_event:
		return
	_applied_room = room
	escoria.event_manager.queue_event(
		room.compiled_script.get_event_with_target(EVENT_APPLY_TIME), true
	)


# Čekaná událost už neběží ani nečeká ve frontě, a přitom nedoběhla (vymazaná
# při změně scény nebo ji Escoria odmítla zařadit). Zbytek kroků se zahodí,
# příště se to spustí znovu.
func _check_pending() -> void:
	if _pending_event.is_empty():
		return
	var manager = escoria.event_manager
	var running = manager.get_running_event(manager.CHANNEL_FRONT)
	if running != null and running.get_event_name() == _pending_event:
		return
	for event in manager.events_queue.get(manager.CHANNEL_FRONT, []):
		if event.get_event_name() == _pending_event:
			return
	if _pending_event == "day_timeout":
		_timed_out = false
	_steps.clear()
	_pending_event = ""
	_busy = false
