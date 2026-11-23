extends Label
# Displej digitálního budíku v Oldově pokoji (Label v items/inventory/alarm.tscn).
# Ukazuje herní čas z globálu day_minute, ale jen když je budík nastavený
# (alarm_set, s baterkami na nočním stolku). Jinak je displej zhasnutý.
# Escoria posílá global_changed ještě před uložením hodnoty, proto new_value.

var _minute: int = 0
var _alarm_set: bool = false


func _ready() -> void:
	var g = escoria.globals_manager
	if g == null:
		return
	if g.has("day_minute"):
		_minute = int(g.get_global("day_minute"))
	if g.has("alarm_set"):
		_alarm_set = bool(g.get_global("alarm_set"))
	g.global_changed.connect(_on_global_changed)
	_redraw()


func _exit_tree() -> void:
	var g = escoria.globals_manager
	if g != null and g.global_changed.is_connected(_on_global_changed):
		g.global_changed.disconnect(_on_global_changed)


func _on_global_changed(global: String, _old_value, new_value) -> void:
	match global:
		"day_minute":
			_minute = int(new_value)
		"alarm_set":
			_alarm_set = bool(new_value)
		_:
			return
	_redraw()


func _redraw() -> void:
	if not _alarm_set:
		text = ""
		return
	var m: int = posmod(_minute, 1440)
	text = "%02d:%02d" % [m / 60, m % 60]
