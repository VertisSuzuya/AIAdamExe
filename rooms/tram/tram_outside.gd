extends Sprite2D
# Krajina za okny tramvaje. Tramvaj chvíli stojí a pak se sama rozjede
# (nastaví globál tram_moving, podle něj mapa počítá čas jízdy).

## Rychlost jízdy v pixelech za sekundu.
@export var speed: float = 300.0
## Za kolik sekund se tramvaj rozjede.
@export var depart_delay: float = 20.0
## Jak rychle se rozjede (sekundy do plné rychlosti).
@export var accel_time: float = 3.0

var _time: float = 0.0
var _moving: bool = false


func _ready() -> void:
	centered = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	region_enabled = true
	region_rect = Rect2(0, 0, 1920, 1080)
	escoria.globals_manager.set_global("tram_moving", false)


func _process(delta: float) -> void:
	_time += delta
	if _time < depart_delay:
		return
	if not _moving:
		_moving = true
		escoria.globals_manager.set_global("tram_moving", true)
	# plynulý rozjezd
	var k: float = clampf((_time - depart_delay) / accel_time, 0.0, 1.0)
	region_rect.position.x = fmod(region_rect.position.x + speed * k * delta,
		texture.get_width())
