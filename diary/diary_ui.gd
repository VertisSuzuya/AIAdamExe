extends Control
# Kořen scény diary_ui. Panel (uzel "panel") vyjíždí zleva, když myš najede
# na úzký pruh u levého okraje obrazovky.
# Myš se zjišťuje proti pevným oblastem (ne přes signály panelu), takže se při
# pohybu panelu otevírání a zavírání nepřepíná dokola.
#
# Obsah bere z autoloadu diary: záložky dnů (jen dny do aktuálního),
# záznamy vybraného dne a u aktuálního dne tlačítko „Začít den znovu“
# (načte checkpoint dne, potvrzuje se druhým kliknutím).
# Záložky a tlačítko se vytváří ze skriptu, pozice jsou v exportech níže.

const DAY_NAMES = ["Pondělí", "Úterý", "Středa", "Čtvrtek", "Pátek", "Sobota", "Neděle"]
const DAY_SHORT = ["Po", "Út", "St", "Čt", "Pá", "So", "Ne"]

@export var peek_width: float = 48.0      # kolik panelu zůstane vidět, když je zavřený
@export var slide_time: float = 0.35
@export var close_delay: float = 0.15     # jak dlouho musí být myš mimo, než se zavře
@export var hover_margin: float = 12.0    # tolerance okolo otevřeného panelu

## Oblast záložek dnů a tlačítka v souřadnicích panelu (x, y, šířka, výška).
@export var tabs_rect: Rect2 = Rect2(60, 110, 405, 56)
@export var restart_rect: Rect2 = Rect2(60, 690, 405, 50)
@export var button_font_size: int = 24
## Jak dlouho čeká tlačítko „Začít den znovu“ na potvrzení (s).
@export var confirm_time: float = 3.0

@onready var panel: Control = $panel
@onready var day_label: Label = $panel/den
@onready var entries_label: RichTextLabel = $panel/MarginContainer/VBoxContainer/RichTextLabel

var _tween: Tween
var _is_open: bool = false
var _open_x: float = 0.0
var _outside_time: float = 0.0
var _initialized: bool = false

var _tab_buttons: Array = []
var _restart_button: Button
var _selected_day: int = 0
var _confirming: bool = false
var _confirm_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Zavřený panel nesmí chytat kliknutí do hry. Při otevření se přepne na Stop.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entries_label.bbcode_enabled = true
	_build_controls()
	diary.changed.connect(_refresh)
	_select_day(_current_day())
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

	if _confirming:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			_cancel_confirm()

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
	_set_buttons_mouse(value)
	if value:
		# Při otevření ukázat aktuální den.
		_select_day(_current_day())
	else:
		_cancel_confirm()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var target_x: float = _open_x if value else _closed_x()
	var t := _tween.tween_property(panel, "position:x", target_x, slide_time)
	t.set_trans(Tween.TRANS_CUBIC)
	t.set_ease(Tween.EASE_OUT)


func _build_controls() -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "day_tabs"
	tabs.position = tabs_rect.position
	tabs.size = tabs_rect.size
	tabs.add_theme_constant_override("separation", 4)
	panel.add_child(tabs)
	for i in DAY_SHORT.size():
		var button := Button.new()
		button.text = DAY_SHORT[i]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", button_font_size)
		button.pressed.connect(_select_day.bind(i))
		tabs.add_child(button)
		_tab_buttons.append(button)

	_restart_button = Button.new()
	_restart_button.name = "restart_day"
	_restart_button.position = restart_rect.position
	_restart_button.size = restart_rect.size
	_restart_button.add_theme_font_size_override("font_size", button_font_size)
	_restart_button.pressed.connect(_on_restart_pressed)
	panel.add_child(_restart_button)
	_cancel_confirm()
	_set_buttons_mouse(false)


# Zavřený deník nesmí chytat kliknutí do hry ani přes tlačítka.
func _set_buttons_mouse(enabled: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	for button in _tab_buttons:
		button.mouse_filter = filter
	_restart_button.mouse_filter = filter


func _current_day() -> int:
	if escoria.globals_manager != null and escoria.globals_manager.has("game_day"):
		return clampi(int(escoria.globals_manager.get_global("game_day")), 0, 6)
	return 0


func _select_day(day: int) -> void:
	_selected_day = clampi(day, 0, _current_day())
	_cancel_confirm()
	_refresh()


func _refresh() -> void:
	var today: int = _current_day()
	_selected_day = mini(_selected_day, today)
	day_label.text = DAY_NAMES[_selected_day]
	for i in _tab_buttons.size():
		_tab_buttons[i].disabled = i > today
		_tab_buttons[i].set_pressed_no_signal(i == _selected_day)

	var entries: Array = diary.entries_for_day(_selected_day)
	if entries.is_empty():
		entries_label.text = "[i]Zatím nic.[/i]"
	else:
		var lines: PackedStringArray = []
		for entry in entries:
			lines.append("• " + str(entry))
		entries_label.text = "\n".join(lines)

	_restart_button.visible = _selected_day == today and _can_restart()


# Restart dne jde jen ve hře, s uloženým checkpointem a když hodiny běží
# (ne v laboratoři před příchodem domů).
func _can_restart() -> bool:
	if escoria.globals_manager == null or not escoria.globals_manager.has("clock_enabled"):
		return false
	if not escoria.globals_manager.get_global("clock_enabled"):
		return false
	return FileAccess.file_exists(game_clock.CHECKPOINT_PATH)


func _on_restart_pressed() -> void:
	if not _confirming:
		_confirming = true
		_confirm_left = confirm_time
		_restart_button.text = "Opravdu? Ztratíš dnešní postup."
		return
	_cancel_confirm()
	_set_open(false)
	# Stejně jako vypršení dne v 1:00: game_clock načte checkpoint.
	escoria.globals_manager.set_global("checkpoint_load_requested", true)


func _cancel_confirm() -> void:
	_confirming = false
	if _restart_button:
		_restart_button.text = "Začít den znovu"
