extends Node
# Deník AIdama (autoload "diary").
#
# Zapisuje správné kroky hráče. Skript nastaví globál s předponou "diary_"
# na true (např. set_global("diary_alarm_set", true)) a deník si ho zapíše
# k aktuálnímu dni (game_day). Texty pro hráče jsou v ENTRIES_PATH.
#
# Záznamy se ukládají do SAVE_PATH, mimo savy Escorie, takže přežijí načtení
# checkpointu dne. Když hráč krok po návratu udělá znovu, záznam se nezdvojí.
# New Game deník vymaže.
#
# Omezení: ruční načtení staršího savu deník nevrátí (deník je jeden na hraní).

signal changed

const SAVE_PATH: String = "user://diary.json"
const ENTRIES_PATH: String = "res://diary/diary_entries.json"
const PREFIX: String = "diary_"
const DAY_COUNT: int = 7

# Pro každý den (0 = pondělí ... 6 = neděle) seznam příznaků v pořadí zápisu.
var _days: Array = []
# Příznak -> text pro hráče.
var _texts: Dictionary = {}


func _ready() -> void:
	_clear_days()
	# Godot importuje .json v res:// jako zdroj JSON (funguje i v exportu).
	var texts_res = load(ENTRIES_PATH)
	if texts_res is JSON and texts_res.data is Dictionary:
		_texts = texts_res.data
	var data = _read_json(SAVE_PATH)
	if data is Dictionary and data.get("days") is Array:
		for day in mini(data["days"].size(), DAY_COUNT):
			for key in data["days"][day]:
				_days[day].append(str(key))


# Na globály se napojí, až je Escoria připravená.
func _process(_delta: float) -> void:
	if escoria.globals_manager == null:
		return
	escoria.globals_manager.global_changed.connect(_on_global_changed)
	set_process(false)


## Texty záznamů daného dne v pořadí, v jakém je hráč získal.
func entries_for_day(day: int) -> Array:
	var result: Array = []
	if day < 0 or day >= DAY_COUNT:
		return result
	for key in _days[day]:
		result.append(str(_texts.get(key, key)))
	return result


func has_entry(key: String) -> bool:
	for day_keys in _days:
		if key in day_keys:
			return true
	return false


# Escoria posílá signál ještě před uložením nové hodnoty, proto new_value.
func _on_global_changed(global: String, old_value, new_value) -> void:
	# New Game: :newgame poprvé nastaví game_day (globály jsou předtím smazané).
	if global == "game_day" and old_value == null and escoria.creating_new_game \
			and not escoria.save_manager.is_loading_game:
		_clear_days()
		_save()
		changed.emit()
		return

	if not global.begins_with(PREFIX) or new_value != true:
		return
	# Načítání savu nastavuje uložené globály znovu, to nejsou nové kroky.
	if escoria.save_manager.is_loading_game or has_entry(global):
		return

	var day: int = 0
	if escoria.globals_manager.has("game_day"):
		day = clampi(int(escoria.globals_manager.get_global("game_day")), 0, DAY_COUNT - 1)
	_days[day].append(global)
	_save()
	changed.emit()


func _clear_days() -> void:
	_days.clear()
	for i in DAY_COUNT:
		_days.append([])


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		escoria.logger.warn(self, "Deník se nepodařilo uložit do %s." % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"days": _days}, "\t"))


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
