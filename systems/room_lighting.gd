extends CanvasModulate
# Tónování místnosti podle části dne (globál day_phase, počítá game_clock).
#
# Použití: do místnosti přidat uzel CanvasModulate a dát mu tenhle skript.
# Tónuje všechno ve vrstvě místnosti (pozadí, postavy, předměty), UI na
# vlastních CanvasLayer zůstává beze změny.
#
# Barva se mění skokem, změnu části dne zakryje mrknutí (game_clock).

@export var morning_color: Color = Color(1.0, 1.0, 1.0)
@export var afternoon_color: Color = Color(1.0, 0.95, 0.85)
@export var evening_color: Color = Color(0.85, 0.62, 0.5)
@export var night_color: Color = Color(0.32, 0.36, 0.55)

## Volitelná vrstva světel (lampy, okna), viditelná jen v částech dne níže.
@export var lights: CanvasItem
@export var lights_phases: PackedStringArray = ["evening", "night"]


func _ready() -> void:
	escoria.globals_manager.global_changed.connect(_on_global_changed)
	if escoria.globals_manager.has("day_phase"):
		_apply(str(escoria.globals_manager.get_global("day_phase")))
	else:
		_apply("morning")


func _exit_tree() -> void:
	if escoria.globals_manager.global_changed.is_connected(_on_global_changed):
		escoria.globals_manager.global_changed.disconnect(_on_global_changed)


# Escoria posílá signál ještě před uložením nové hodnoty, proto new_value.
func _on_global_changed(global: String, _old_value, new_value) -> void:
	if global == "day_phase":
		_apply(str(new_value))


func _apply(phase: String) -> void:
	match phase:
		"afternoon":
			color = afternoon_color
		"evening":
			color = evening_color
		"night":
			color = night_color
		_:
			color = morning_color
	if lights:
		lights.visible = phase in lights_phases
