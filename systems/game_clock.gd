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
# Při změně dne nebo části dne spustí :update_schedule z game.esc (rozvrh světa).
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

var _minute_accumulator: float = 0.0
# Pro jaký den a část dne naposledy proběhl rozvrh ("den_cast").
var _schedule_key: String = ""
# Právě čekáme na dokončení události (aby se nespouštělo víckrát).
var _busy: bool = false
# Událost z game.esc, na kterou čekáme, a klíč rozvrhu, pro který běží.
var _pending_event: String = ""
var _pending_key: String = ""
# Den už vypršel, čekáme, až skript posune čas zpátky.
var _timed_out: bool = false


func _process(delta: float) -> void:
	if _busy:
		_check_pending()
		return
	if not _is_running():
		return

	var minute: int = int(escoria.globals_manager.get_global("day_minute"))

	if minute >= DAY_END:
		if not _timed_out:
			_timed_out = true
			_run_game_event("day_timeout")
		return
	_timed_out = false

	# Rozvrh podle aktuálního dne a části dne (i po načtení hry nebo když
	# skript změní čas, např. spánek).
	var phase: String = phase_for_minute(minute)
	if escoria.globals_manager.get_global("day_phase") != phase:
		escoria.globals_manager.set_global("day_phase", phase)
	var key: String = "%d_%s" % [int(escoria.globals_manager.get_global("game_day")), phase]
	if key != _schedule_key:
		_update_schedule(key)
		return

	# Běh času.
	_minute_accumulator += delta * minutes_per_second
	if _minute_accumulator >= 1.0:
		var whole: int = int(_minute_accumulator)
		_minute_accumulator -= whole
		escoria.globals_manager.set_global("day_minute", mini(minute + whole, DAY_END))


## Vrátí část dne pro danou minutu.
static func phase_for_minute(minute: int) -> String:
	var m: int = posmod(minute, 24 * 60)
	for p in PHASES:
		if m >= p[0]:
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


func _update_schedule(key: String) -> void:
	_pending_key = key
	_run_game_event("update_schedule")


# Zařadí událost z game.esc do fronty Escorie (nečeká na ni).
#
# Na dokončení se nečeká přes await: Escoria při změně scény frontu vymaže
# a vymazaná událost signál event_finished nepošle, takže by await visel
# navždy. Dokončení hlídá _on_event_finished, zmizení z fronty _check_pending.
func _run_game_event(event_name: String) -> void:
	var script: ESCScript = escoria.start_script
	if script == null or not script.has_event_with_target(event_name):
		_finish_pending(event_name, ESCExecution.RC_OK)
		return
	if not escoria.event_manager.event_finished.is_connected(_on_event_finished):
		escoria.event_manager.event_finished.connect(_on_event_finished)
	_busy = true
	_pending_event = event_name
	escoria.event_manager.queue_event_from_esc(
		script, event_name, escoria.event_manager.CHANNEL_FRONT, false
	)


func _on_event_finished(return_code: int, event_name: String) -> void:
	if event_name == _pending_event:
		_finish_pending(event_name, return_code)


func _finish_pending(event_name: String, return_code: int) -> void:
	if event_name == "update_schedule" and return_code == ESCExecution.RC_OK:
		_schedule_key = _pending_key
	_pending_event = ""
	_busy = false


# Událost už neběží ani nečeká ve frontě, a přitom nedoběhla (vymazaná při
# změně scény nebo ji Escoria odmítla zařadit). Uvolní hodiny, příště se
# spustí znovu.
func _check_pending() -> void:
	var manager = escoria.event_manager
	var running = manager.get_running_event(manager.CHANNEL_FRONT)
	if running != null and running.get_event_name() == _pending_event:
		return
	for event in manager.events_queue.get(manager.CHANNEL_FRONT, []):
		if event.get_event_name() == _pending_event:
			return
	if _pending_event == "day_timeout":
		_timed_out = false
	_pending_event = ""
	_busy = false
