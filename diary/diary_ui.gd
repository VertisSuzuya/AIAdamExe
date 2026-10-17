extends Control
# Kořen scény diary_ui. Panel (uzel "panel") vyjíždí zleva, když myš najede
# na úzký pruh u levého okraje obrazovky.
# Myš se zjišťuje proti pevným oblastem (ne přes signály panelu), takže se při
# pohybu panelu otevírání a zavírání nepřepíná dokola.

@export var peek_width: float = 48.0      # kolik panelu zůstane vidět, když je zavřený
@export var slide_time: float = 0.35
@export var close_delay: float = 0.15     # jak dlouho musí být myš mimo, než se zavře
@export var hover_margin: float = 12.0    # tolerance okolo otevřeného panelu

@onready var panel: Control = $panel

var _tween: Tween
var _is_open: bool = false
var _open_x: float = 0.0
var _outside_time: float = 0.0
var _initialized: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Zavřený panel nesmí chytat kliknutí do hry. Při otevření se přepne na Stop.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame
	# Otevřená pozice = tak, jak jsi panel umístil v editoru. Velikost se nemění.
	_open_x = panel.position.x
	panel.position.x = _closed_x()
	_initialized = true


func _closed_x() -> float:
	return -panel.size.x + peek_width


func _process(delta: float) -> void:
	if not _initialized:
		return
	var mouse: Vector2 = get_local_mouse_position()
	var top: float = panel.position.y
	var height: float = panel.size.y
	# Pruh u levého okraje, který otevírá deník (pevná pozice, nehýbe se s panelem).
	var strip := Rect2(-100.0, top, 100.0 + peek_width, height)

	if _is_open:
		var open_rect := Rect2(_open_x, top, panel.size.x, height).grow(hover_margin)
		if open_rect.has_point(mouse) or strip.has_point(mouse):
			_outside_time = 0.0
		else:
			_outside_time += delta
			if _outside_time >= close_delay:
				_set_open(false)
	else:
		if strip.has_point(mouse):
			_set_open(true)


func _set_open(value: bool) -> void:
	_is_open = value
	_outside_time = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var target_x: float = _open_x if value else _closed_x()
	var t := _tween.tween_property(panel, "position:x", target_x, slide_time)
	t.set_trans(Tween.TRANS_CUBIC)
	t.set_ease(Tween.EASE_OUT)
