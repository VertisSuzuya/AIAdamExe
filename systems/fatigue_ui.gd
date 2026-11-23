extends CanvasLayer
# Únava na obrazovce (autoload "fatigue_ui"): víčka shora a zdola a ikona oka.
# Čte globály fatigue_on a fatigue (0-100, počítá game_clock).
# Vrstva 1: nad hrou, pod UI (inventář, hodiny, deník, mapa ve vrstvě 2),
# kurzorem (3) a dialogy (4). Vrstvy UI posunuté v game.tscn pluginu.

## Kolik obrazovky zakryje jedno víčko při únavě 100 (0.5 = půlka).
@export var lid_max: float = 0.46
## Od jaké únavy se víčka začnou zavírat a od jaké Olda mrká.
@export var lids_from: float = 50.0
@export var blink_from: float = 70.0

var _top: ColorRect
var _bottom: ColorRect
var _eye: EyeIcon
var _panel: NinePatchRect
var _blink_left: float = 0.0
var _blink_timer: float = 4.0


func _ready() -> void:
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_top = _make_lid()
	_bottom = _make_lid()
	# Panel nahoře uprostřed ve stylu hodin (stejná textura s tyrkysovým
	# rámečkem), uvnitř lišta bdělosti a pod ní oko.
	_panel = NinePatchRect.new()
	_panel.texture = load("res://grafika/timebackground.png")
	_panel.patch_margin_left = 10
	_panel.patch_margin_right = 10
	_panel.patch_margin_top = 10
	_panel.patch_margin_bottom = 10
	_panel.position = Vector2(880, 0)
	_panel.size = Vector2(160, 86)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_eye = EyeIcon.new()
	_eye.position = Vector2(10, 10)
	_eye.size = Vector2(140, 70)
	_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_eye)
	visible = false


func _make_lid() -> ColorRect:
	var lid := ColorRect.new()
	lid.color = Color(0, 0, 0, 0.97)
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lid)
	return lid


func _process(delta: float) -> void:
	var g = escoria.globals_manager if escoria else null
	var on: bool = g != null and g.has("fatigue_on") and bool(g.get_global("fatigue_on")) \
			and not get_tree().paused
	visible = on
	if not on:
		return
	var fatigue: float = float(g.get_global("fatigue"))
	var close: float = clampf((fatigue - lids_from) / (100.0 - lids_from), 0.0, 1.0) * lid_max

	# Mrknutí: čím unavenější, tím častěji.
	if fatigue >= blink_from:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_left = 0.25
			_blink_timer = randf_range(2.0, 6.0) * (1.6 - fatigue / 100.0)
	if _blink_left > 0.0:
		_blink_left -= delta
		close = 0.5

	var screen: Vector2 = get_viewport().get_visible_rect().size
	_top.position = Vector2.ZERO
	_top.size = Vector2(screen.x, screen.y * close)
	_bottom.position = Vector2(0, screen.y * (1.0 - close))
	_bottom.size = Vector2(screen.x, screen.y * close)
	_eye.amount = fatigue / 100.0
	_eye.queue_redraw()


# Lišta bdělosti (ubývá s únavou, energetik ji doplní) a pod ní oko,
# které se zavírá s únavou a nad 85 zčervená.
class EyeIcon extends Control:
	var amount: float = 0.0

	func _draw() -> void:
		# Lišta: plná = odpočatý, prázdná = usne.
		# Barvy jako UI hodin: tyrkysová (#00CACD, popisek dne #76FFE8),
		# v poslední čtvrtině varovně červená.
		var bar := Rect2(Vector2(8, 4), Vector2(124, 12))
		var awake: float = clampf(1.0 - amount, 0.0, 1.0)
		var fill := Color(0.46, 1.0, 0.91)
		if awake < 0.25:
			fill = Color(1.0, 0.35, 0.35)
		draw_rect(bar, Color(0, 0.1, 0.1, 0.9))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * awake, bar.size.y)), fill)
		draw_rect(bar, Color(0, 0.79, 0.8), false, 2.0)

		# Oko pod lištou.
		var c := Vector2(70, 46)
		var open: float = maxf(1.0 - amount, 0.06)
		var pts := PackedVector2Array()
		for i in 21:
			var t: float = i / 20.0 * PI
			pts.append(c + Vector2(cos(t) * 34.0, -sin(t) * 18.0 * open))
		for i in range(1, 20):
			var t: float = i / 20.0 * PI
			pts.append(c + Vector2(-cos(t) * 34.0, sin(t) * 18.0))
		# Oko v barvách UI: tmavé bělmo, tyrkysový obrys a duhovka.
		var accent := Color(1.0, 0.35, 0.35) if amount > 0.85 else Color(0.46, 1.0, 0.91)
		draw_colored_polygon(pts, Color(0, 0.22, 0.22, 0.95))
		if open > 0.35:
			draw_circle(c + Vector2(0, 3), 9.0 * open, accent)
			draw_circle(c + Vector2(0, 3), 4.0 * open, Color(0, 0.1, 0.1))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0.79, 0.8), 3.0, true)
