extends CanvasModulate
# Tónování místnosti podle části dne (globál day_phase, počítá game_clock)
# a světla (lampy, okna) podle času (globál day_minute).
#
# Použití: do místnosti přidat uzel CanvasModulate a dát mu tenhle skript.
# Tónuje všechno ve vrstvě místnosti (pozadí, postavy, předměty), UI na
# vlastních CanvasLayer zůstává beze změny.
#
# Barva se mění skokem, změnu části dne zakryje mrknutí (game_clock).
# Světla se rozsvěcují a zhasínají plynule (lights_fade).

@export var morning_color: Color = Color(1.0, 1.0, 1.0)
@export var afternoon_color: Color = Color(1.0, 0.95, 0.85)
@export var evening_color: Color = Color(0.85, 0.62, 0.5)
@export var night_color: Color = Color(0.32, 0.36, 0.55)

## Volitelná světla (PointLight2D, nebo obrázek / skupina uzlů).
@export var lights: CanvasItem
## Kdy se světla rozsvítí (hodiny: 20.0 = 20:00, 19.5 = 19:30).
@export var lights_on_hour: float = 20.0
## Kdy zhasnou. Po půlnoci se počítá přes 24 (26.0 = 2:00 ráno; den končí v 1:00, v sobotu běží dál).
@export var lights_off_hour: float = 26.0
## Jak dlouho se světla rozsvěcují a zhasínají (sekundy).
@export var lights_fade: float = 2.0

var _lights_on: bool = false
var _light_amount: float = 0.0
var _full_energy: float = 1.0
var _tween: Tween


func _ready() -> void:
	escoria.globals_manager.global_changed.connect(_on_global_changed)
	if lights is Light2D:
		_full_energy = (lights as Light2D).energy
	if escoria.globals_manager.has("day_phase"):
		_apply(str(escoria.globals_manager.get_global("day_phase")))
	else:
		_apply("morning")
	# Při příchodu do místnosti bez prolínání, rovnou správný stav.
	var minute: int = 540
	if escoria.globals_manager.has("day_minute"):
		minute = int(escoria.globals_manager.get_global("day_minute"))
	_lights_on = _lights_wanted(minute)
	_set_light_amount(1.0 if _lights_on else 0.0)


func _exit_tree() -> void:
	if escoria.globals_manager.global_changed.is_connected(_on_global_changed):
		escoria.globals_manager.global_changed.disconnect(_on_global_changed)


# Escoria posílá signál ještě před uložením nové hodnoty, proto new_value.
func _on_global_changed(global: String, _old_value, new_value) -> void:
	if global == "day_phase":
		_apply(str(new_value))
	elif global == "day_minute":
		_update_lights(int(new_value))


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


func _lights_wanted(minute: int) -> bool:
	return minute >= int(lights_on_hour * 60.0) and minute < int(lights_off_hour * 60.0)


# Rozsvítit / zhasnout plynule, jen když se stav opravdu mění.
func _update_lights(minute: int) -> void:
	if not lights:
		return
	var want: bool = _lights_wanted(minute)
	if want == _lights_on:
		return
	_lights_on = want
	if _tween:
		_tween.kill()
	if lights_fade <= 0.0:
		_set_light_amount(1.0 if want else 0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_set_light_amount, _light_amount, 1.0 if want else 0.0, lights_fade)


# 0 = zhasnuto, 1 = plně rozsvíceno. U PointLight2D se mění síla (Energy),
# u ostatních uzlů průhlednost.
func _set_light_amount(a: float) -> void:
	_light_amount = a
	if not lights:
		return
	lights.visible = a > 0.0
	if lights is Light2D:
		(lights as Light2D).energy = _full_energy * a
	else:
		lights.modulate.a = a
