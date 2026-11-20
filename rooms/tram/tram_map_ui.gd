extends CanvasLayer
# Mapa linek v tramvaji. Otevře se, když map.esc nastaví tram_map_open.
# Ukazuje jen odemčené zastávky. Klik na zastávku spustí :travel
# v tram.esc, klik mimo mapu mapu zavře.

const MAP_TEXTURE = preload("res://rooms/tram/tram_map.png")
const INK = Color(0.2, 0.2, 0.24)
const ACCENT = Color(0.0, 0.79, 0.8)

# id cílové místnosti: [název pro hráče, globál odemčení ("" = vždy), pozice na mapě]
const STOPS = {
	"home_street": ["Domov", "", Vector2(420, 560)],
	"fit_front": ["Dejvice", "stop_dejvice", Vector2(980, 330)],
	"city_center": ["Centrum", "stop_center", Vector2(700, 470)],
	"in_laws_house": ["Konečná", "stop_in_laws", Vector2(1240, 690)],
}

var _map: TextureRect
var _stops: Dictionary = {}


func _ready() -> void:
	layer = 50
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(1920, 1080)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_map = TextureRect.new()
	_map.texture = MAP_TEXTURE
	_map.position = (Vector2(1920, 1080) - MAP_TEXTURE.get_size()) / 2
	_map.mouse_filter = Control.MOUSE_FILTER_STOP   # klik na mapu ji nezavře
	add_child(_map)

	for id in STOPS:
		var stop := Button.new()
		stop.text = "  " + STOPS[id][0]
		stop.flat = true
		stop.alignment = HORIZONTAL_ALIGNMENT_LEFT
		stop.add_theme_font_size_override("font_size", 34)
		stop.add_theme_color_override("font_color", INK)
		stop.add_theme_color_override("font_hover_color", ACCENT)
		stop.add_theme_color_override("font_pressed_color", ACCENT)
		stop.icon = _circle_icon()
		stop.position = STOPS[id][2] - Vector2(24, 30)
		stop.pressed.connect(_on_stop_pressed.bind(id))
		_map.add_child(stop)
		_stops[id] = stop

	escoria.globals_manager.global_changed.connect(_on_global_changed)
	visible = false


func _exit_tree() -> void:
	if escoria.globals_manager.global_changed.is_connected(_on_global_changed):
		escoria.globals_manager.global_changed.disconnect(_on_global_changed)



# Při otevření pauzového menu (Esc) se mapa zavře, jinak by ležela přes menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and visible:
		escoria.globals_manager.set_global("tram_map_open", false)

# Escoria posílá signál před uložením hodnoty, proto new_value.
func _on_global_changed(global: String, _old, new_value) -> void:
	if global == "tram_map_open":
		visible = bool(new_value)
		if visible:
			_refresh()


func _refresh() -> void:
	var g = escoria.globals_manager
	for id in STOPS:
		var unlock: String = STOPS[id][1]
		_stops[id].visible = unlock == "" or (g.has(unlock) and bool(g.get_global(unlock)))


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		escoria.globals_manager.set_global("tram_map_open", false)


func _on_stop_pressed(id: String) -> void:
	escoria.globals_manager.set_global("tram_target", id)
	escoria.globals_manager.set_global("tram_map_open", false)
	var room = escoria.main.current_scene
	escoria.event_manager.queue_event_from_esc(
		room.compiled_script, "travel", escoria.event_manager.CHANNEL_FRONT, false
	)


# Kolečko zastávky (kreslené za běhu, aby nebyl potřeba další obrázek).
func _circle_icon() -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 48:
			var d := Vector2(x - 23.5, y - 23.5).length()
			if d < 22.0:
				img.set_pixel(x, y, INK if d > 15.0 else Color(0.98, 0.98, 0.96))
	return ImageTexture.create_from_image(img)
