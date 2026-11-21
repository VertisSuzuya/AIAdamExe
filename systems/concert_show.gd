extends Node2D
# Koncert v atriu: dav ze stínů, blikající reflektory, hudba a rytmická
# minihra se šipkami (tři dráhy, šipky padají na terčíky).
# Ovládání: šipka vlevo / nahoru / vpravo (nebo A / W / D), Enter přeskočí písničku.
# Nejde prohrát, výsledek (0-100) jde do globálu concert_score a AIdam podle něj
# po koncertu komentuje.
#
# Průběh: :ready v concert.esc nechá AIdama promluvit a nastaví concert_play,
# teprve pak začne hudba. Po poslední písničce se spustí :concert_end.

## Písničky (mp3/ogg), hrají za sebou.
@export var songs: Array[AudioStream] = []
## Noty ke každé písničce ve stejném pořadí (JSON z rooms/concert/).
@export_file("*.json") var note_files: Array[String] = []
## Siluety davu (crowd_1.png až crowd_6.png).
@export var crowd_textures: Array[Texture2D] = []
## Odkud svítí reflektory (stojany na pódiu a strop).
@export var light_origins: Array[Vector2] = [
	Vector2(1330, 320), Vector2(1600, 190), Vector2(700, 0), Vector2(1100, 0)
]
## Kolik řad davu (od zadní stěny dopředu).
@export var row_count: int = 9
## Ladění: cvaknutí na každou notu (jen ve vývojové verzi).
@export var metronome: bool = false

# Dav vyplňuje podlahu od zadní stěny dopředu. Vzadu menší a světlejší lidé,
# vpředu velcí a skoro černí. Vpravo nezakrývá pódium (okraj jde šikmo podél
# jeho přední hrany), vlevo končí u šikmé stěny pod schodištěm.
const BACK_Y = 600.0
const FRONT_Y = 1080.0
const LIGHT_COLORS = [
	Color(0.4, 0.7, 1.0), Color(1.0, 0.3, 0.8), Color(1.0, 0.85, 0.3),
	Color(0.5, 1.0, 0.6), Color(1.0, 0.35, 0.3), Color(0.8, 0.5, 1.0),
]

# Minihra
const PERFECT = 0.08        # okno pro „Perfektní!“ (± s)
const GOOD = 0.16           # okno pro „Dobrý“ (± s)
const NEAR = 0.35           # zmáčknutí dál než tohle od šipky se nepočítá (bez trestu)
const ARROW_FALL = 1.1      # jak dlouho šipka padá shora na terčík (s)
const ARROW_TOP = 110.0     # kde se šipka objeví
const TARGET_Y = 760.0      # výška terčíků (nad inventářem)
const ARROW_SIZE = 44.0
const LANES = 3
const LANE_X = [820.0, 960.0, 1100.0]           # ←, ↑, →
const LANE_ANGLE = [PI, -PI / 2.0, 0.0]         # natočení šipky (základní míří doprava)
const LANE_KEYS = [[KEY_LEFT, KEY_A], [KEY_UP, KEY_W], [KEY_RIGHT, KEY_D]]
const LANE_COLORS = [Color(0.0, 0.79, 0.8), Color(1.0, 0.85, 0.3), Color(1.0, 0.3, 0.8)]
const LANE_PITCH = [90.0, 120.0, 160.0]       # tóny trefy (dvojice znějí jako akord)

var _people: Array = []   # [sprite, výchozí pozice, fáze, rychlost, skok, kývání]
var _lights: Array = []   # [kužel, fáze, rychlost kývání]
var _t: float = 0.0
var _player: AudioStreamPlayer
var _ended: bool = false
var _playing: bool = false
var _song_index: int = 0

var _notes: Array = []    # [čas, dráha 0-2, stav (0 čeká, 1 trefa, 2 vedle)]
var _next_note: int = 0   # první nota, která ještě může čekat na vyhodnocení
var _beats: Array = []    # údery písničky (pulzování terčíků)
var _beat_i: int = 0
var _last_beat: float = -10.0
var _popups: Array = []   # [text, pozice, barva, zbývá, celkem]
var _bursts: Array = []   # efekty: [pozice, barva, zbývá, celkem, poloměr od, do, šířka]
var _judgement: Array = ["", Color.WHITE, 0.0]  # poslední hodnocení: [text, barva, zbývá]
var _lane_press: Array = [0.0, 0.0, 0.0]   # terčík po zmáčknutí krátce zmenšený
var _lane_glow: Array = [0.0, 0.0, 0.0]    # terčík po trefě krátce rozsvícený
var _combo: int = 0
var _points: float = 0.0
var _judged: int = 0
var _hype: float = 0.0    # 0..1, zvedá skoky davu
var _field: Node2D
var _font: Font
var _lane_snd: Array = []
var _miss_snd: AudioStreamPlayer
var _tick: AudioStreamPlayer
var _tick_index: int = 0


func _ready() -> void:
	randomize()
	_font = ThemeDB.fallback_font
	# Reflektory (z_index 1) svítí přes dav, minihra (z_index 100) je úplně nahoře.
	for origin in light_origins:
		_lights.append(_make_light(origin))
	if crowd_textures.is_empty():
		push_warning("concert_show: chybí siluety davu (crowd_textures)")
	else:
		for i in row_count:
			_spawn_row(i)
	_field = Node2D.new()
	_field.z_index = 100
	_field.draw.connect(_draw_field)
	add_child(_field)

	var timer := Timer.new()
	timer.wait_time = 0.35
	timer.autostart = true
	timer.timeout.connect(_flicker)
	add_child(timer)
	_flicker()

	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)
	_player.finished.connect(_next_song)

	# Zvuky: trefa měkký „ding“ (každá dráha jiný tón), netrefa tupé bum.
	for lane in LANES:
		_lane_snd.append(_make_player(_make_drum(LANE_PITCH[lane], 0.35, 0.11, 0.8)))
	_miss_snd = _make_player(_make_sound(300.0, 0.9, 0.08, 0.02, 0.2))
	if metronome and OS.is_debug_build():
		_tick = _make_player(_make_sound(1500.0, 0.0, 0.03, 0.006, 0.4))

	escoria.globals_manager.global_changed.connect(_on_global_changed)


func _exit_tree() -> void:
	if escoria.globals_manager.global_changed.is_connected(_on_global_changed):
		escoria.globals_manager.global_changed.disconnect(_on_global_changed)


# Hudba začne, až AIdam domluví (concert.esc nastaví concert_play).
# Escoria posílá signál před uložením hodnoty, proto new_value.
func _on_global_changed(global: String, _old, new_value) -> void:
	if global == "concert_play" and bool(new_value):
		_start.call_deferred()


func _start() -> void:
	if _playing or _ended:
		return
	_playing = true
	if songs.is_empty():
		push_warning("concert_show: chybí písničky, koncert hned skončí")
		_end()
		return
	_play(0)


func _play(index: int) -> void:
	_song_index = index
	_load_notes(index)
	_player.stream = songs[index]
	_player.play()
	_popup("Mačkej šipky do rytmu! (vlevo, nahoru, vpravo nebo A, W, D)",
			Vector2(960, 420), Color.WHITE, 3.5)


# Po dohrání (nebo přeskočení) písně další, po poslední konec koncertu.
func _next_song() -> void:
	if _ended:
		return
	if _song_index + 1 < songs.size():
		_play(_song_index + 1)
	else:
		_end()


func _end() -> void:
	if _ended:
		return
	_ended = true
	_playing = false
	_player.stop()
	escoria.globals_manager.set_global("concert_score", _accuracy())
	var room = escoria.main.current_scene
	escoria.event_manager.queue_event_from_esc(
		room.compiled_script, "concert_end", escoria.event_manager.CHANNEL_FRONT, false
	)


# Čas v písničce přesně podle toho, co je slyšet (i se zpožděním zvukovky).
func _song_time() -> float:
	return _player.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()


# Noty z JSON: časy z nahrávky, dráhy se dopočítají s pevným náhodným
# semínkem, takže každé hraní vypadá stejně (jako mapa v rytmických hrách).
func _load_notes(index: int) -> void:
	_notes.clear()
	_beats.clear()
	_next_note = 0
	_tick_index = 0
	_beat_i = 0
	_last_beat = -10.0
	if index >= note_files.size():
		push_warning("concert_show: k písničce %d chybí noty" % index)
		return
	var f := FileAccess.open(note_files[index], FileAccess.READ)
	if f == null:
		push_warning("concert_show: nejde otevřít %s" % note_files[index])
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("notes"):
		return
	_beats = data.get("beats", [])
	var times: Array = data["notes"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + index
	var lane: int = 1
	for k in times.size():
		var time: float = float(times[k])
		var gap_prev: float = time - (float(times[k - 1]) if k > 0 else -10.0)
		var gap_next: float = (float(times[k + 1]) if k + 1 < times.size() else 10.0) - time
		# Rychlé noty vždycky mění dráhu (nikdy dvakrát rychle stejná klávesa),
		# jinak většinou změna, občas stejná.
		if gap_prev < 0.3 or rng.randf() < 0.7:
			lane = (lane + rng.randi_range(1, LANES - 1)) % LANES
		_notes.append([time, lane, 0])
		# Dvojice (dvě šipky naráz) na každé osmé notě, jen když není moc nahusto.
		if k % 8 == 0 and gap_prev >= 0.3 and gap_next >= 0.3:
			var other: int = (lane + rng.randi_range(1, LANES - 1)) % LANES
			_notes.append([time, other, 0])


func _process(delta: float) -> void:
	_t += delta
	_hype = maxf(0.0, _hype - delta * 0.25)
	var jump_boost: float = 1.0 + _hype * 1.5
	for p in _people:
		var phase: float = _t * p[3] + p[2]
		p[0].position = p[1] + Vector2(sin(phase * 0.5) * p[5],
				-absf(sin(phase)) * p[4] * jump_boost)
		p[0].rotation = sin(phase * 0.5) * 0.04
	for l in _lights:
		l[0].rotation = sin(_t * l[2] + l[1]) * 0.35

	if _playing and _player.playing:
		var now: float = _song_time()
		# Noty, které už nejde trefit, jsou vedle.
		while _next_note < _notes.size() and _notes[_next_note][0] < now - GOOD:
			if _notes[_next_note][2] == 0:
				_judge(_notes[_next_note], false, false)
			_next_note += 1
		while _beat_i < _beats.size() and float(_beats[_beat_i]) <= now:
			_last_beat = float(_beats[_beat_i])
			_beat_i += 1
		if _tick:
			while _tick_index < _notes.size() and _notes[_tick_index][0] <= now:
				_tick.play()
				_tick_index += 1

	for p in _popups:
		p[3] -= delta
	_popups = _popups.filter(func(p): return p[3] > 0.0)
	for b in _bursts:
		b[2] -= delta
	_bursts = _bursts.filter(func(b): return b[2] > 0.0)
	for lane in LANES:
		_lane_press[lane] = maxf(0.0, _lane_press[lane] - delta)
		_lane_glow[lane] = maxf(0.0, _lane_glow[lane] - delta)
	_judgement[2] = maxf(0.0, _judgement[2] - delta)
	_field.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _playing or _ended:
		return
	# Myš se během koncertu nepoužívá (ať klik nepropadne do hry).
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Ctrl + šipky patří ladicím zkratkám (debug_tools).
	if event.ctrl_pressed:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_next_song()
		get_viewport().set_input_as_handled()
		return
	for lane in LANES:
		if event.keycode in LANE_KEYS[lane]:
			_hit_lane(lane)
			get_viewport().set_input_as_handled()
			return


# Nejbližší čekající šipka v dané dráze. Zmáčknutí daleko od jakékoli šipky
# se netrestá; zvuk netrefy jen když šipka je blízko, ale mimo rytmus.
func _hit_lane(lane: int) -> void:
	_lane_press[lane] = 0.1
	var now: float = _song_time()
	var near: bool = false
	for i in range(_next_note, _notes.size()):
		var n: Array = _notes[i]
		if n[0] - now > NEAR:
			break
		if n[2] != 0 or n[1] != lane:
			continue
		if absf(n[0] - now) <= GOOD:
			_judge(n, true, absf(n[0] - now) <= PERFECT)
			return
		near = true
	if near:
		_miss_snd.play()


func _judge(n: Array, hit: bool, perfect: bool) -> void:
	_judged += 1
	var lane: int = n[1]
	var pos := Vector2(LANE_X[lane], TARGET_Y)
	if hit:
		n[2] = 1
		_lane_snd[lane].play()
		_bursts.append([pos, LANE_COLORS[lane], 0.3, 0.3, ARROW_SIZE, ARROW_SIZE * 1.9, 6.0])
		_lane_glow[lane] = 0.2
		_combo += 1
		_points += 1.0 if perfect else 0.5
		_hype = minf(1.0, _hype + (0.12 if perfect else 0.06))
		if perfect:
			_judgement = ["Perfektní!", Color(1.0, 0.95, 0.5), 0.5]
			_flash(LANE_COLORS[lane], false)
		else:
			_judgement = ["Dobrý", Color(0.7, 0.9, 1.0), 0.5]
		if _combo in [25, 50, 100, 200, 300]:
			_popup("%d COMBO!" % _combo, Vector2(960, 300), Color.WHITE, 1.5)
			_flash(LANE_COLORS[lane], true)
	else:
		n[2] = 2
		_combo = 0
		_hype = maxf(0.0, _hype - 0.1)
		_judgement = ["Vedle", Color(1.0, 0.35, 0.35), 0.5]


func _accuracy() -> int:
	return int(round(100.0 * _points / maxf(1.0, _judged)))


func _popup(text: String, pos: Vector2, color: Color, time: float) -> void:
	_popups.append([text, pos, color, time, time])


func _lane_held(lane: int) -> bool:
	for key in LANE_KEYS[lane]:
		if Input.is_key_pressed(key):
			return true
	return false


func _draw_field() -> void:
	if not _playing:
		return
	var now: float = _song_time()
	var pulse: float = exp(-maxf(0.0, now - _last_beat) * 10.0)

	# Podklad drah, zvýraznění držené dráhy.
	var x0: float = LANE_X[0] - 80.0
	var w: float = LANE_X[LANES - 1] - LANE_X[0] + 160.0
	_field.draw_rect(Rect2(x0, ARROW_TOP - 50.0, w, TARGET_Y - ARROW_TOP + 120.0),
			Color(0, 0, 0, 0.35))
	for lane in LANES:
		if _lane_held(lane):
			_field.draw_rect(Rect2(LANE_X[lane] - 60.0, ARROW_TOP - 50.0, 120.0,
					TARGET_Y - ARROW_TOP + 120.0), Color(LANE_COLORS[lane], 0.12))

	# Terčíky: pulzují do rytmu, po zmáčknutí se zmenší, po trefě rozsvítí.
	for lane in LANES:
		var s: float = ARROW_SIZE * (1.0 + 0.08 * pulse - (0.12 if _lane_press[lane] > 0.0 else 0.0))
		var pts := _arrow_points(Vector2(LANE_X[lane], TARGET_Y), lane, s)
		if _lane_glow[lane] > 0.0:
			_field.draw_colored_polygon(pts, Color(LANE_COLORS[lane], clampf(_lane_glow[lane] * 4.0, 0.0, 0.9)))
		elif _lane_held(lane):
			_field.draw_colored_polygon(pts, Color(LANE_COLORS[lane], 0.3))
		_draw_outline(pts, Color(1, 1, 1, 0.9), 4.0)

	# Padající šipky (nejbližší navrchu).
	var shown: Array = []
	for i in range(_next_note, _notes.size()):
		var n: Array = _notes[i]
		if n[0] - now > ARROW_FALL:
			break
		if n[2] == 0:
			shown.append(n)
	for k in range(shown.size() - 1, -1, -1):
		var n: Array = shown[k]
		var left: float = n[0] - now
		var y: float = lerpf(TARGET_Y, ARROW_TOP, left / ARROW_FALL)
		var alpha: float = clampf((1.0 - left / ARROW_FALL) * 3.0, 0.0, 1.0)
		var pts := _arrow_points(Vector2(LANE_X[n[1]], y), n[1], ARROW_SIZE)
		_field.draw_colored_polygon(pts, Color(LANE_COLORS[n[1]], alpha))
		_draw_outline(pts, Color(1, 1, 1, alpha), 3.0)

	# Hodnocení a combo uprostřed nad drahami.
	if _judgement[2] > 0.0:
		var f: float = _judgement[2] / 0.5
		_field.draw_string(_font, Vector2(660, 500 - (1.0 - f) * 12.0), _judgement[0],
				HORIZONTAL_ALIGNMENT_CENTER, 600, 44, Color(_judgement[1], f))
	if _combo >= 5:
		_field.draw_string(_font, Vector2(660, 560), str(_combo),
				HORIZONTAL_ALIGNMENT_CENTER, 600, 36, Color(1, 1, 1, 0.8))
	_field.draw_string(_font, Vector2(40, 70), "Combo %d" % _combo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
	_field.draw_string(_font, Vector2(40, 112), "%d %%" % _accuracy(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.8, 0.9, 1.0))

	for p in _popups:
		var f: float = p[3] / p[4]
		_field.draw_string(_font, p[1] + Vector2(-500, -(1.0 - f) * 20.0),
				p[0], HORIZONTAL_ALIGNMENT_CENTER, 1000, 34, Color(p[2], minf(1.0, f * 2.0)))
	for b in _bursts:
		var f: float = 1.0 - b[2] / b[3]
		var r: float = lerpf(b[4], b[5], f)
		_field.draw_arc(b[0], r, 0.0, TAU, 40, Color(b[1], 1.0 - f), b[6], true)


# Šipka v dráze (← ↑ →) se středem v c a velikostí s.
func _arrow_points(c: Vector2, lane: int, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in [Vector2(s, 0), Vector2(0, -s), Vector2(0, -s * 0.45), Vector2(-s, -s * 0.45),
			Vector2(-s, s * 0.45), Vector2(0, s * 0.45), Vector2(0, s)]:
		pts.append(c + p.rotated(LANE_ANGLE[lane]))
	return pts


func _draw_outline(pts: PackedVector2Array, color: Color, width: float) -> void:
	var outline := pts.duplicate()
	outline.append(pts[0])
	_field.draw_polyline(outline, color, width, true)


func _spawn_row(i: int) -> void:
	var t: float = float(i) / maxf(1.0, row_count - 1.0)
	var bottom: float = lerpf(BACK_Y, FRONT_Y, t)
	var s: float = lerpf(0.3, 1.0, t)
	var shade: float = lerpf(0.35, 0.04, t)
	var color := Color(shade * 0.6, shade * 0.5, shade)
	# levý okraj: šikmá stěna pod schodištěm, pravý: přední hrana pódia
	var left: float = maxf(0.0, (770.0 - bottom) * 770.0 / 210.0)
	var right: float = minf(1920.0, 1100.0 + maxf(0.0, bottom - 640.0) * 1.4)
	var count: int = maxi(2, int((right - left) / (200.0 * s * 0.6)))
	for k in count:
		var tex: Texture2D = crowd_textures.pick_random()
		var p := Sprite2D.new()
		p.texture = tex
		p.centered = false
		p.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
		p.scale = Vector2(s, s)
		p.modulate = color
		p.flip_h = randf() < 0.5
		var base := Vector2(
				left + (k + 0.5) * (right - left) / count + randf_range(-20.0, 20.0) * s,
				bottom + 60.0 * s)
		p.position = base
		add_child(p)
		_people.append([p, base, randf() * TAU, randf_range(4.0, 7.0),
				lerpf(8.0, 24.0, t) * randf_range(0.6, 1.3), randf_range(3.0, 12.0) * s])


# Kužel světla (sčítá se s obrazem, nahoře jasný, dole průhledný).
func _make_light(origin: Vector2) -> Array:
	var cone := Polygon2D.new()
	cone.polygon = PackedVector2Array([
		Vector2(-10, 0), Vector2(10, 0), Vector2(260, 900), Vector2(-260, 900)
	])
	cone.position = origin
	cone.z_index = 1
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	cone.material = mat
	add_child(cone)
	return [cone, randf() * TAU, randf_range(0.5, 1.5)]


# Reflektory se náhodně zapínají, vypínají a mění barvu.
func _flicker() -> void:
	for l in _lights:
		var cone: Polygon2D = l[0]
		cone.visible = randf() < 0.65
		_set_cone_color(cone, LIGHT_COLORS.pick_random(), 0.55)


# Záblesk při trefě: jeden reflektor (nebo všechny při velkém combu).
func _flash(color: Color, all: bool) -> void:
	if _lights.is_empty():
		return
	var targets: Array = _lights if all else [_lights.pick_random()]
	for l in targets:
		l[0].visible = true
		_set_cone_color(l[0], color, 0.85)


func _set_cone_color(cone: Polygon2D, c: Color, a: float) -> void:
	cone.vertex_colors = PackedColorArray([
		Color(c, a), Color(c, a), Color(c, 0.0), Color(c, 0.0)
	])


# Měkký „ding“ (jako marimba): tón s tiššími vyššími harmonickými,
# krátký náběh (bez lupnutí) a plynulé doznění.
func _make_bell(freq: float, length: float, decay: float, vol: float) -> AudioStreamWAV:
	var rate: int = 22050
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	var count: int = int(length * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / rate
		var w: float = t * TAU * freq
		var v: float = (sin(w) + 0.45 * sin(2.0 * w) + 0.2 * sin(3.0 * w)) / 1.65
		v *= minf(1.0, t / 0.004) * exp(-t / decay) * vol
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav


# Krátký zvuk bez souboru: tón + šum, rychle doznívá.
# freq = výška (Hz), noise = podíl šumu (0..1), length = délka (s),
# decay = jak rychle doznívá (menší = ostřejší), vol = hlasitost (0..1).
func _make_sound(freq: float, noise: float, length: float, decay: float,
		vol: float) -> AudioStreamWAV:
	var rate: int = 22050
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	var count: int = int(length * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / rate
		var v: float = (sin(t * TAU * freq) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise) \
				* exp(-t / decay) * vol
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav

# Měkký buben (tom): tón začne o oktávu výš a rychle sjede na freq,
# k tomu krátké jemné ťuknutí na začátku. freq = výška (Hz), length = délka (s),
# decay = doznění (víc = delší), vol = hlasitost (0..1).
func _make_drum(freq: float, length: float, decay: float, vol: float) -> AudioStreamWAV:
	var rate: int = 22050
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	var count: int = int(length * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	for i in count:
		var t: float = float(i) / rate
		# Výška sjede z dvojnásobku na freq během ~40 ms.
		var f: float = freq * (1.0 + exp(-t / 0.04))
		phase += TAU * f / rate
		var body: float = sin(phase) * exp(-t / decay)
		var knock: float = randf_range(-1.0, 1.0) * exp(-t / 0.004) * 0.15
		var v: float = (body + knock) * minf(1.0, t / 0.002) * vol
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav

func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	add_child(p)
	return p
