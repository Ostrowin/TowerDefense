extends Node2D
## Widok gry: rysuje stan Sim, zbiera input, prowadzi kamerę, HUD, menu i efekty.
## Logika gry siedzi w Sim (scripts/sim.gd) — tutaj wyłącznie prezentacja.
##
## Stany ekranu (nakładki „Ustawienia" i „Jak grać" leżą nad każdym z nich):
##
##   MENU ──(mapa + trudność)──▶ PLAY ◀──(Wznów)── PAUSED
##                                │  ──(Esc/P/II)──▶
##                                ▼ (sim.result != 0)
##                              OVER ──(Jeszcze raz)──▶ PLAY
##                                   ──(Menu)────────▶ MENU
##
## Wskaźnik (mysz albo jeden palec — dotyk jest emulowany jako mysz):
##
##   wciśnij ─┬─ tryb budowy/umiejętności ──▶ podgląd pod palcem ── puść ──▶ buduj / użyj
##            └─ inaczej ──┬─ ruch > TAP_SLOP ──▶ przesuwanie mapy
##                         └─ puść w miejscu ───▶ klik (złoże / zaznaczenie)
##   dwa palce = szczypanie (zoom) + przesuwanie; kółko myszy = zoom; WASD/strzałki = przesuwanie

enum State { MENU, PLAY, PAUSED, OVER }

## Krok symulacji: 30 razy na sekundę (połowa kosztu 60 Hz). Render interpoluje
## pozycje jednostek i pocisków między krokami (`render_alpha`), więc ruch jest płynny.
## Testy (bot_test) liczą balans na tym samym kroku.
const STEP := 1.0 / 30.0
## Maks. czas symulacji na klatkę (ms). Po przekroczeniu gra porzuca zaległe kroki.
const SIM_BUDGET_MS := 10.0
const TEAM_COLORS: Array[Color] = [Color(0.35, 0.62, 1.0), Color(1.0, 0.36, 0.3)]
## Kolory rozróżniające ścieżki (plakietki budynków, przyciski, podświetlenie).
const LANE_COLORS: Array[Color] = [Color(1.0, 0.78, 0.3), Color(0.55, 0.92, 0.5), Color(0.8, 0.6, 1.0)]
const GOLD_COLOR := Color(1.0, 0.84, 0.3)
const WARN_COLOR := Color(1.0, 0.25, 0.2)
const FROST_COLOR := Color(0.6, 0.85, 1.0)
## Kolor nawierzchni ścieżki. Podświetlenia ścieżek mieszają go z kolorem (bez przezroczystości —
## półprzezroczysta gruba linia nakłada się sama na siebie na ostrych zakrętach i robi kreski).
const PATH_COLOR := Color(0.45, 0.38, 0.27)
const HEAL_COLOR := Color(0.45, 1.0, 0.55)
const OVER_DELAY := 1.6
## Limity efektów — każda iskra i napis to osobne wywołania rysowania co klatkę.
const MAX_SPARKS := 250
const MAX_TEXTS := 24
const GOLD_TEXTS_MAX := 10  ## „+6 zł" pokazujemy tylko, gdy napisów jest mało
const HIT_FX_PER_FRAME := 6
const DEATH_FX_PER_FRAME := 8
## Powyżej tylu jednostek (przy widoku całej mapy) rysujemy je uproszczone.
const LOD_UNITS := 120
const TAP_SLOP := 12.0
const ZOOM_MAX := 2.0
const KEY_PAN_SPEED := 700.0
const HIT_NOTICE_GAP := 4.0
const ABILITY_KEYS := {KEY_Q: "arrows", KEY_E: "levy", KEY_R: "repair"}

## Samouczek: krok kończy się, gdy spełniony jest warunek `done` (sprawdzany co klatkę).
const TUTORIAL: Array[Dictionary] = [
	{"text": "Kliknij złote złoże (●), żeby postawić wydobywacz — to Twój dochód.", "done": "extractor"},
	{"text": "Postaw Koszary (przycisk na dole) — piechurzy sami ruszą na wroga.", "done": "production"},
	{"text": "Czerwony „!” pokazuje ścieżkę następnej fali. Postaw przy niej wieżę.", "done": "tower"},
	{"text": "Kliknij swoje koszary: wybierz ścieżkę natarcia albo ulepsz budynek.", "done": "select_production"},
	{"text": "Przeciągnij mapę albo przybliż ją kółkiem / dwoma palcami.", "done": "camera"},
	{"text": "Umiejętności są w prawym dolnym rogu — rzuć Deszcz strzał na grupę wrogów!", "done": "ability"},
	{"text": "Świetnie! Teraz zburz fortecę wroga po prawej. Powodzenia!", "done": "timer"},
]


class Spark:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var color: Color
	var size: float
	var ring := false
	var streak := false  ## spadająca strzała (Deszcz strzał)


class FloatText:
	var pos: Vector2
	var text: String
	var life: float
	var color: Color


var sim: Sim
var state := State.MENU
var overlay := ""  ## "" / "settings" / "help" — nakładka nad bieżącym stanem
var level_index := 0
var race_index := Races.first_playable()  ## rasa gracza (Races.ALL); przeciwnik = Races.rival
var difficulty := 1
var mode := ""  ## "" / klucz budynku z Cfg.BUILD_ORDER / "ab:<umiejętność>"
var selected: Sim.Building = null
var speed_mult := 1
var accum := 0.0
var time := 0.0
var over_delay := 0.0
## Licznik wydajności (F3): wygładzone czasy sekcji klatki w ms + kroki sima.
var perf := {"sim": 0.0, "events": 0.0, "hud": 0.0, "draw": 0.0, "steps": 0}
var perf_visible := false
var perf_log_at := 0.0  ## licznik trafia też co 5 s do logu (na telefonie: `adb logcat`)
## Ułamek kroku sima, który upłynął od ostatniego kroku (0..1) — do interpolacji renderu.
var render_alpha := 1.0
## Uproszczone rysowanie jednostek w dużej bitwie (ustawiane co klatkę w _draw).
var low_detail := false
## Wolne pola budowy — liczone tylko, gdy zmieni się układ budynków (`sim.layout_version`).
var _build_cells := PackedVector2Array()
var _build_cells_version := -1
var new_record := false

# samouczek
var tutorial_step := -1
var tutorial_timer := 0.0
var camera_used := false

# wskaźnik i gesty
var pointer_screen := Vector2.ZERO
var pointer_active := false
var press_button := -1  ## trzymany przycisk myszy (-1 = żaden)
var press_screen := Vector2.ZERO
var panning := false
var dragging := false  ## stawianie budynku / celowanie umiejętnością: podgląd pod palcem
var touches := {}  ## indeks palca → pozycja ekranowa
var gesture := false  ## dwa palce — emulowana mysz jest wtedy ignorowana

# kamera
var camera: Camera2D
var fit_zoom := 1.0
## Widoczny obszar w pikselach wirtualnych. Wysokość zawsze 720, szerokość zależy od proporcji
## ekranu (stretch „expand"): 1280 przy 16:9, ~1600 na telefonie 20:9.
var view_size := Cfg.VIEW

# efekty
var sparks: Array[Spark] = []
var texts: Array[FloatText] = []
var banner_text := ""
var banner_sub := ""
var banner_life := 0.0
var shake := 0.0
var base_flash: Array[float] = [0.0, 0.0]
var hit_notice := {}  ## id budynku → czas ostatniego „Atak!"

# teren bieżącej mapy (liczony przy zmianie mapy)
var lane_points: Array[PackedVector2Array] = []
var river_points := PackedVector2Array()
var bridge_planks := PackedVector2Array()  ## pary punktów dla draw_multiline
var bridge_rails := PackedVector2Array()
var grass: Array[Vector3] = []  ## x, y, rodzaj
var trees: Array[Vector3] = []  ## x, y, promień
## Świat rysowany co klatkę (_draw) — patrz Painter: wszystko jednym wywołaniem rysowania.
var pen := Painter.new()
var grass_batch := Painter.new()  ## trawa, kwiatki i kamienie (pod ścieżkami)
var tree_batch := Painter.new()  ## drzewa (nad ścieżkami)

var terrain: Node2D  ## warstwa statycznego terenu, przerysowywana przy zmianie mapy
var warn_lines: Array[Line2D] = []  ## podświetlenie ścieżki nadchodzącej fali (per ścieżka)
var pick_lines: Array[Line2D] = []  ## podświetlenie wybranej ścieżki produkcji (per ścieżka)
var sfx: Sfx
var font: Font

# HUD (odtwarzany w całości przy zmianie rozmiaru interfejsu)
var ui_layer: CanvasLayer
var screen := Cfg.VIEW  ## rozmiar HUD w jego własnych jednostkach (ekran / skala UI)
var hud: Control
var fx_canvas: Control
var minimap: Control
var gold_label: Label
var income_label: Label
var wave_label: Label
var perf_label: Label
var perf_button: Button
var stance_button: Button
var speed_button: Button
var mute_button: Button
var build_buttons := {}
var ability_buttons := {}
var sel_panel: PanelContainer
var sel_title: Label
var sel_body: Label
var lane_row: HBoxContainer
var lane_buttons: Array[Button] = []
var upgrade_button: Button
var sell_button: Button
var tutorial_panel: PanelContainer
var tutorial_label: Label
var menu_layer: Control
var race_buttons: Array[Button] = []
var race_desc: Label
var map_buttons: Array[Button] = []
var map_desc: Label
var diff_buttons: Array[Button] = []
var pause_layer: Control
var over_layer: Control
var over_title: Label
var over_stats: Label
var settings_layer: Control
var sfx_slider: HSlider
var music_slider: HSlider
var scale_button: Button
var help_layer: Control


func _ready() -> void:
	Settings.load_all()
	Settings.apply_audio()
	font = ThemeDB.fallback_font
	sfx = Sfx.new()
	add_child(sfx)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	terrain = Node2D.new()
	terrain.z_index = -1  # pod wszystkim, co rysuje main
	terrain.draw.connect(_draw_terrain)
	add_child(terrain)
	sim = Sim.new(difficulty, -1, level_index)
	_make_terrain()
	view_size = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_view_resized)
	_build_ui()
	_show_menu()
	_start_bench()


## Benchmark zamiast gracza: `-- --bench res://tests/perf_test.gd [argumenty]` (desktop, headless,
## a na telefonie wbudowane w APK przez `tools/android.ps1 -Bench`). Skrypt benchmarku to węzeł,
## który dostaje `main` i steruje grą co klatkę.
func _start_bench() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--bench")
	if i < 0 or i + 1 >= args.size():
		return
	var bench: Node = load(args[i + 1]).new()
	bench.set("main", self)
	add_child(bench)


# ================================================================ przebieg gry

func _start(d: int) -> void:
	difficulty = d
	sim = Sim.new(d, -1, level_index)
	_make_terrain()
	_clear_view_state()
	speed_mult = 1
	accum = 0.0
	state = State.PLAY
	overlay = ""
	tutorial_step = -1 if Progress.tutorial_done() else 0
	tutorial_timer = 0.0
	camera_used = false
	_banner("Przygotuj się!", "Pierwsza fala za %d s: %s" % [int(sim.wave_timer), sim.lane_names(sim.next_wave_lanes)])


func _show_menu() -> void:
	state = State.MENU
	overlay = ""
	sim = Sim.new(difficulty, -1, level_index)
	_make_terrain()
	_clear_view_state()


func _select_level(i: int) -> void:
	level_index = i
	_show_menu()


func _select_race(i: int) -> void:
	if Races.ALL[i]["playable"]:
		race_index = i


func _clear_view_state() -> void:
	sparks.clear()
	texts.clear()
	hit_notice.clear()
	mode = ""
	selected = null
	dragging = false
	panning = false
	press_button = -1
	shake = 0.0
	banner_life = 0.0
	tutorial_step = -1
	_reset_camera()


func _set_paused(p: bool) -> void:
	if p and state == State.PLAY:
		state = State.PAUSED
		dragging = false
		press_button = -1
	elif not p and state == State.PAUSED:
		state = State.PLAY
		overlay = ""


func _notification(what: int) -> void:
	# Android: wyjście z aplikacji / telefon w tle = auto-pauza.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == State.PLAY:
			_set_paused(true)
	# Android: systemowe „Wstecz" działa jak Esc, a w menu głównym zamyka grę
	# (project.godot ma quit_on_go_back = false — inaczej silnik zamykałby grę od razu).
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not _back():
			get_tree().quit()


## Esc / „Wstecz": zamknij nakładkę → anuluj tryb/zaznaczenie → pauza ⇄ gra → z ekranu końca
## do menu. Zwraca false, gdy nie ma się już dokąd cofnąć (menu główne).
func _back() -> bool:
	if overlay != "":
		_close_overlay()
	elif state == State.PLAY and (mode != "" or selected != null):
		_cancel()
	elif state == State.PLAY or state == State.PAUSED:
		_set_paused(state == State.PLAY)
	elif state == State.OVER:
		_show_menu()
	else:
		return false
	return true


## Zmiana rozmiaru okna albo proporcji ekranu: nowy widoczny obszar, kamera i HUD od nowa.
func _on_view_resized() -> void:
	var size := get_viewport_rect().size
	if size == view_size:
		return
	var fitted := not _is_zoomed_in()
	view_size = size
	fit_zoom = minf(view_size.x / sim.size.x, view_size.y / sim.size.y)
	if fitted:
		_reset_camera()
	else:
		camera.zoom = Vector2.ONE * maxf(camera.zoom.x, fit_zoom)
		_clamp_camera()
	_rebuild_ui.call_deferred()


func _process(delta: float) -> void:
	time += delta
	if state == State.PLAY:
		accum += delta * speed_mult
		var t0 := Time.get_ticks_usec()
		var steps := 0
		while accum >= STEP:
			sim.step(STEP)
			accum -= STEP
			steps += 1
			if Time.get_ticks_usec() - t0 > SIM_BUDGET_MS * 1000.0:
				# Zadyszka: porzuć zaległe kroki. Gra chwilowo zwalnia, ale klatka ma
				# ograniczony czas — bez tego wolna klatka wymuszała jeszcze więcej kroków
				# w następnej i gra się „zawieszała" (spiral of death).
				accum = minf(accum, STEP)
				break
		_perf_sample("sim", t0)
		perf["steps"] = steps
		render_alpha = clampf(accum / STEP, 0.0, 1.0)
		t0 = Time.get_ticks_usec()
		_consume_events()
		if sim.result != 0:
			_on_game_end()
		_key_pan(delta)
		_update_tutorial(delta)
		_perf_sample("events", t0)
	if state == State.PLAY or state == State.OVER:
		_update_effects(delta)
	if state == State.OVER and over_delay > 0:
		over_delay -= delta
	var t_hud := Time.get_ticks_usec()
	_update_hud()
	_update_lane_fx()
	_perf_sample("hud", t_hud)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	queue_redraw()
	fx_canvas.queue_redraw()
	if minimap.visible:
		minimap.queue_redraw()


func _perf_sample(key: String, t0: int) -> void:
	perf[key] = lerpf(perf[key], (Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _on_game_end() -> void:
	state = State.OVER
	over_delay = OVER_DELAY
	mode = ""
	selected = null
	dragging = false
	press_button = -1
	tutorial_step = -1
	var won := sim.result == 1
	var map_id: String = sim.level["id"]
	new_record = won and Progress.record_win(map_id, difficulty, sim.elapsed)
	var loser_base := sim.base_pos(1 if won else 0)
	for i in 5:
		_burst(loser_base + Vector2(randf_range(-40, 40), randf_range(-30, 30)), 18, Color(1, 0.6, 0.2), 200.0)
	_ring(loser_base, 120.0, Color(1, 0.8, 0.4))
	shake = 16.0
	sfx.play("explosion", 0.0)
	sfx.play("win" if won else "lose", 0.0)
	over_title.text = "WYGRANA!" if won else "PRZEGRANA"
	over_title.add_theme_color_override("font_color", GOLD_COLOR if won else TEAM_COLORS[1])
	var s := sim.stats
	var lines := PackedStringArray([
		"%s · %s · %s · czas %s · fala %d" % [Races.ALL[race_index]["name"], sim.level["name"], sim.difficulty["name"], _fmt_time(sim.elapsed), sim.wave],
		"Zabici wrogowie: %d · wyprodukowane jednostki: %d · umiejętności: %d" % [s["kills"], s["units_made"], s["abilities_used"]],
		"Zburzone wieże: %d · stracone budynki: %d · zarobione złoto: %d" % [s["towers_razed"], s["buildings_lost"], int(s["gold_earned"])],
	])
	if new_record:
		lines.append("Nowy rekord!  Gwiazdki mapy: %s" % _stars_text(Progress.stars(map_id)))
	over_stats.text = "\n".join(lines)


# ================================================================ zdarzenia sim → efekty i dźwięk

func _consume_events() -> void:
	# W dużej bitwie trafień i śmierci są setki na sekundę — efekty dla każdego
	# z nich kosztowały więcej niż cała symulacja. Limit na klatkę; reszta bez iskier.
	var hits_left := HIT_FX_PER_FRAME
	var deaths_left := DEATH_FX_PER_FRAME
	for e in sim.events:
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		match e["type"]:
			"shot":
				sfx.play(e["kind"], 0.07)
			"hit":
				if hits_left > 0:
					hits_left -= 1
					_burst(pos, 3, Color(1, 0.9, 0.6), 60.0, 0.25)
				sfx.play("hit", 0.06)
			"death":
				if deaths_left > 0 or e["kind"] == "warlord":
					deaths_left -= 1
					_burst(pos, 10, TEAM_COLORS[e["team"]], 110.0)
				sfx.play("death", 0.05)
				if e["kind"] == "warlord":
					shake = maxf(shake, 12.0)
					_banner("Wódz pokonany!", "")
			"gold":
				if texts.size() < GOLD_TEXTS_MAX:
					_float_text(pos, "+%d" % e["amount"], GOLD_COLOR)
				sfx.play("coin", 0.08)
			"explosion":
				_burst(pos, 14, Color(1, 0.62, 0.2), 150.0, 0.45)
				_ring(pos, e["radius"], Color(1, 0.8, 0.4))
				sfx.play("explosion", 0.1)
			"frost":
				_burst(pos, 10, FROST_COLOR, 90.0, 0.5)
				_ring(pos, e["radius"], FROST_COLOR)
			"volley":
				_arrow_rain(pos, e["radius"])
				sfx.play("volley", 0.1)
			"ability":
				match e["name"]:
					"arrows":
						_ring(pos, Cfg.ABILITIES["arrows"]["radius"], Color.WHITE)
					"levy":
						var tc := TEAM_COLORS[e.get("team", 0)]
						_burst(pos, 20, tc, 140.0, 0.6)
						_float_text(pos + Vector2(0, -20), "Pobór!", tc.lightened(0.3))
						sfx.play("levy", 0.0)
					"repair":
						for b in sim.buildings:
							if b.team == 0 and b.kind != "basegun":
								_burst(b.pos, 6, HEAL_COLOR, 60.0, 0.6)
						_burst(sim.p_base, 20, HEAL_COLOR, 90.0, 0.8)
						_float_text(sim.p_base + Vector2(0, -60), "Naprawa!", HEAL_COLOR)
						sfx.play("repair", 0.0)
			"base_hit":
				base_flash[e["team"]] = 0.15
				if e["team"] == 0:
					shake = maxf(shake, 4.0)
					sfx.play("base_hit", 0.3)
			"wave":
				var where := sim.lane_names(e["lanes"])
				if e["boss"]:
					_banner("Fala %d — %s" % [e["n"], where], "Nadciąga WÓDZ! (%d wrogów)" % e["count"])
					shake = maxf(shake, 8.0)
					sfx.play("boss", 0.0)
				elif e.get("fury", false):
					_banner("Fala %d — %s" % [e["n"], where], "Wróg wpada w furię — od teraz każda fala silniejsza!")
					shake = maxf(shake, 6.0)
					sfx.play("boss", 0.0)
				else:
					_banner("Fala %d — %s" % [e["n"], where], "%d wrogów" % e["count"])
					sfx.play("wave", 0.0)
			"enemy_build":
				_float_text(pos, "Wróg stawia wieżę!", TEAM_COLORS[1])
				_burst(pos, 12, Color(0.7, 0.6, 0.5), 80.0)
				sfx.play("build", 0.0)
			"build":
				_burst(pos, 12, Color(0.75, 0.65, 0.5), 90.0)
				sfx.play("build", 0.0)
			"upgrade":
				_burst(pos, 16, GOLD_COLOR, 120.0)
				_ring(pos, 40.0, GOLD_COLOR)
				sfx.play("upgrade", 0.0)
			"sell":
				_float_text(pos, "+%d" % e["amount"], GOLD_COLOR)
				_burst(pos, 10, Color(0.7, 0.7, 0.7), 80.0)
				sfx.play("sell", 0.0)
			"building_hit":
				if time - hit_notice.get(e["id"], -INF) > HIT_NOTICE_GAP:
					hit_notice[e["id"]] = time
					_float_text(pos + Vector2(0, -28), "Atak!", WARN_COLOR)
					sfx.play("alarm", 1.0)
			"building_destroyed":
				_burst(pos, 24, Color(1, 0.55, 0.2), 180.0, 0.7)
				_ring(pos, 60.0, Color(1, 0.7, 0.3))
				shake = maxf(shake, 7.0)
				sfx.play("explosion", 0.0)
				if e["team"] == 1:
					_float_text(pos + Vector2(0, -24), "Wieża zburzona!", Color.WHITE)
				else:
					_float_text(pos + Vector2(0, -24), "Zniszczono: %s" % Cfg.BUILDINGS[e["kind"]]["name"], WARN_COLOR)
	sim.events.clear()


func _burst(at: Vector2, n: int, color: Color, speed := 100.0, life := 0.5) -> void:
	for i in n:
		if sparks.size() >= MAX_SPARKS:
			return
		var s := Spark.new()
		s.pos = at
		s.vel = Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * speed
		s.max_life = life * randf_range(0.6, 1.2)
		s.life = s.max_life
		s.color = color
		s.size = randf_range(2.0, 4.0)
		sparks.append(s)


func _ring(at: Vector2, radius: float, color: Color) -> void:
	if sparks.size() >= MAX_SPARKS:
		return
	var s := Spark.new()
	s.pos = at
	s.ring = true
	s.size = radius
	s.max_life = 0.35
	s.life = s.max_life
	s.color = color
	sparks.append(s)


## Salwa Deszczu strzał: spadające kreski w promieniu celu.
func _arrow_rain(at: Vector2, radius: float) -> void:
	for i in 18:
		if sparks.size() >= MAX_SPARKS:
			return
		var s := Spark.new()
		s.pos = at + Vector2.from_angle(randf() * TAU) * randf() * radius + Vector2(-30, -90)
		s.vel = Vector2(120, 360)
		s.max_life = 0.25
		s.life = s.max_life
		s.color = Color(0.95, 0.9, 0.75)
		s.streak = true
		sparks.append(s)


func _float_text(at: Vector2, text: String, color: Color) -> void:
	if texts.size() >= MAX_TEXTS:
		texts.pop_front()  # ważne komunikaty wypierają najstarsze
	var f := FloatText.new()
	f.pos = at + Vector2(randf_range(-6, 6), -10)
	f.text = text
	f.life = 1.2
	f.color = color
	texts.append(f)


func _banner(text: String, sub: String) -> void:
	banner_text = text
	banner_sub = sub
	banner_life = 2.8


func _update_effects(delta: float) -> void:
	for s in sparks:
		s.life -= delta
		s.pos += s.vel * delta
		if not s.streak:
			s.vel *= 1.0 - 4.0 * delta
	sparks = sparks.filter(func(s: Spark) -> bool: return s.life > 0)
	for f in texts:
		f.life -= delta
		f.pos.y -= 28.0 * delta
	texts = texts.filter(func(f: FloatText) -> bool: return f.life > 0)
	banner_life = maxf(0.0, banner_life - delta)
	shake = maxf(0.0, shake - 30.0 * delta)
	for i in 2:
		base_flash[i] = maxf(0.0, base_flash[i] - delta)


# ================================================================ samouczek

func _update_tutorial(delta: float) -> void:
	if tutorial_step < 0:
		return
	tutorial_timer += delta
	var done := false
	match TUTORIAL[tutorial_step]["done"]:
		"extractor":
			done = _has_building(func(b: Sim.Building) -> bool: return b.kind == "extractor")
		"production":
			done = _has_building(func(b: Sim.Building) -> bool: return Cfg.is_production(b.kind))
		"tower":
			done = _has_building(func(b: Sim.Building) -> bool: return Cfg.is_tower(b.kind))
		"select_production":
			done = selected != null and selected.team == 0 and Cfg.is_production(selected.kind)
		"camera":
			done = camera_used
		"ability":
			done = sim.stats["abilities_used"] > 0
		"timer":
			done = tutorial_timer > 6.0
	if not done:
		return
	tutorial_step += 1
	tutorial_timer = 0.0
	if tutorial_step >= TUTORIAL.size():
		_finish_tutorial()
	else:
		sfx.play("coin", 0.0)


func _finish_tutorial() -> void:
	tutorial_step = -1
	Progress.set_tutorial_done(true)


func _reset_tutorial() -> void:
	Progress.set_tutorial_done(false)
	if state == State.PAUSED:
		tutorial_step = 0  # w trwającej grze rusza od razu po wznowieniu
		tutorial_timer = 0.0
	_banner("Samouczek włączony", "")


func _has_building(pred: Callable) -> bool:
	for b in sim.buildings:
		if b.team == 0 and pred.call(b):
			return true
	return false


# ================================================================ kamera

## Ekran (piksele wirtualne, `view_size`) → świat. Liczone wprost z kamery, bez czekania na klatkę.
func _to_world(screen_pos: Vector2) -> Vector2:
	return camera.position + (screen_pos - view_size / 2.0) / camera.zoom.x


func _to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - camera.position) * camera.zoom.x + view_size / 2.0


func _reset_camera() -> void:
	fit_zoom = minf(view_size.x / sim.size.x, view_size.y / sim.size.y)
	camera.zoom = Vector2.ONE * fit_zoom
	camera.position = sim.size / 2.0


func _is_zoomed_in() -> bool:
	return camera.zoom.x > fit_zoom * 1.02


## Przybliża/oddala tak, żeby punkt świata pod `screen_pt` został pod palcem/kursorem.
func _zoom_at(screen_pt: Vector2, factor: float) -> void:
	var anchor := _to_world(screen_pt)
	var z := clampf(camera.zoom.x * factor, fit_zoom, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.position = anchor - (screen_pt - view_size / 2.0) / z
	_clamp_camera()
	camera_used = true


## Przesuwa widok tak, jakby przeciągać mapę o `delta_screen` pikseli ekranu.
func _pan_screen(delta_screen: Vector2) -> void:
	camera.position -= delta_screen / camera.zoom.x
	_clamp_camera()
	camera_used = true


func _clamp_camera() -> void:
	var half := view_size / camera.zoom.x / 2.0
	var p := camera.position
	p.x = sim.size.x / 2.0 if half.x * 2.0 >= sim.size.x else clampf(p.x, half.x, sim.size.x - half.x)
	p.y = sim.size.y / 2.0 if half.y * 2.0 >= sim.size.y else clampf(p.y, half.y, sim.size.y - half.y)
	camera.position = p


func _key_pan(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		_pan_screen(-v * KEY_PAN_SPEED * delta)


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)
		return
	if state != State.PLAY or overlay != "":
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		_pan_screen(-event.delta * 12.0)
	elif gesture:
		return  # w trakcie gestu dwoma palcami ignoruj emulowaną mysz
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		touches[e.index] = e.position
	else:
		touches.erase(e.index)
	if touches.size() >= 2 and not gesture:
		gesture = true
		press_button = -1  # drugi palec anuluje rozpoczęty klik/stawianie/przesuwanie
		dragging = false
		panning = false
	elif touches.is_empty():
		gesture = false


## Dwa palce: zmiana odległości = zoom, ruch środka = przesuwanie.
func _on_touch_drag(e: InputEventScreenDrag) -> void:
	if not gesture or touches.size() < 2 or not touches.has(e.index):
		touches[e.index] = e.position
		return
	var ids := touches.keys()
	var a0: Vector2 = touches[ids[0]]
	var b0: Vector2 = touches[ids[1]]
	touches[e.index] = e.position
	var a1: Vector2 = touches[ids[0]]
	var b1: Vector2 = touches[ids[1]]
	var d0 := a0.distance_to(b0)
	if d0 > 1.0:
		_zoom_at((a1 + b1) / 2.0, a1.distance_to(b1) / d0)
	_pan_screen((a1 + b1) / 2.0 - (a0 + b0) / 2.0)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	pointer_screen = e.position
	var p := _to_world(e.position)
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, 1.12)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / 1.12)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				press_button = e.button_index
				press_screen = e.position
				panning = false
				var left := e.button_index == MOUSE_BUTTON_LEFT
				dragging = left and (_ability_mode() != "" or (_is_build_mode() and _is_free_spot(p)))
			elif e.button_index == press_button:
				press_button = -1
				if dragging:
					dragging = false
					if DisplayServer.is_touchscreen_available():
						pointer_active = false  # na dotyku podgląd znika razem z palcem
					if _ability_mode() != "":
						_use_targeted(p)
					else:
						_place(p)
				elif not panning:
					if e.button_index == MOUSE_BUTTON_LEFT:
						_tap(p)
					elif e.button_index == MOUSE_BUTTON_RIGHT:
						_cancel()
				panning = false


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	pointer_screen = e.position
	pointer_active = true
	if press_button == -1 or dragging:
		return
	if not panning and e.position.distance_to(press_screen) > TAP_SLOP:
		panning = true
	if panning:
		_pan_screen(e.relative)


func _is_build_mode() -> bool:
	return mode != "" and not mode.begins_with("ab:")


## Nazwa umiejętności, którą właśnie celujemy ("" = żadna).
func _ability_mode() -> String:
	return mode.substr(3) if mode.begins_with("ab:") else ""


## Czy w tym miejscu wciśnięcie w trybie budowy zaczyna stawianie (a nie klik w coś).
func _is_free_spot(p: Vector2) -> bool:
	return sim.node_at(p) < 0 and sim.building_at(p, 0) == null


func _on_key(key: int) -> void:
	match key:
		KEY_ESCAPE:
			_back()
		KEY_P:
			if overlay == "":
				_set_paused(state == State.PLAY)
		KEY_F3:
			_toggle_perf()
	if state != State.PLAY or overlay != "":
		return
	if ABILITY_KEYS.has(key):
		_select_ability(ABILITY_KEYS[key])
		return
	match key:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_select_mode(Cfg.BUILD_ORDER[key - KEY_1])
		KEY_SPACE:
			_toggle_stance()
		KEY_U:
			_upgrade_selected()
		KEY_DELETE, KEY_X:
			_sell_selected()
		KEY_TAB:
			if selected != null and Cfg.is_production(selected.kind):
				_set_selected_lane((selected.lane + 1) % sim.lanes.size())
		KEY_F:
			_cycle_speed()
		KEY_M:
			_toggle_mute()
		KEY_C, KEY_HOME:
			_reset_camera()
		KEY_EQUAL, KEY_KP_ADD:
			_zoom_at(view_size / 2.0, 1.2)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(view_size / 2.0, 1.0 / 1.2)


## Klik bez przeciągania: złoże → wydobywacz / zaznacz; budynek → zaznacz.
func _tap(p: Vector2) -> void:
	if _ability_mode() != "":
		_use_targeted(p)
		return
	var node := sim.node_at(p)
	if node >= 0:
		var ex := sim.extractor_on(node)
		if ex != null:
			selected = ex
			mode = ""
		elif not sim.build_extractor(node):
			_deny(p)
		return
	var own := sim.building_at(p, 0)
	if own != null:
		mode = ""  # klik we własny budynek w trybie budowy = zaznacz go
		selected = own
		return
	if mode != "":
		return
	selected = null
	var enemy := sim.building_at(p, 1)
	if enemy != null and Cfg.is_tower(enemy.kind):
		selected = enemy


func _place(p: Vector2) -> void:
	var cell := Cfg.snap(p)
	if not sim.can_place(cell):
		sfx.play("error", 0.1)
		return
	if not sim.build(mode, cell):
		_deny(cell)
		return
	if sim.gold < Cfg.BUILDINGS[mode]["cost"]:
		mode = ""


func _select_ability(ability: String) -> void:
	if not sim.ability_ready(ability):
		sfx.play("error", 0.1)
		return
	if not Cfg.ABILITIES[ability]["target"]:
		sim.use_ability(ability)
		mode = ""
		return
	mode = "" if mode == "ab:" + ability else "ab:" + ability
	selected = null


func _use_targeted(p: Vector2) -> void:
	var ability := _ability_mode()
	if sim.use_ability(ability, p):
		mode = ""
	else:
		var why := "Jeszcze nie"
		if ability == "levy":
			why = "Limit armii" if sim.team_count[0] >= Cfg.MAX_ARMY else "Tylko przy ścieżce, na Twojej połowie"
		_float_text(p, why, WARN_COLOR)
		sfx.play("error", 0.1)


func _deny(at: Vector2) -> void:
	_float_text(at, "Brak złota", TEAM_COLORS[1])
	sfx.play("error", 0.1)


func _cancel() -> void:
	mode = ""
	selected = null
	dragging = false


func _select_mode(key: String) -> void:
	mode = "" if mode == key else key
	selected = null


func _toggle_stance() -> void:
	sim.set_stance("defend" if sim.stance == "attack" else "attack")
	_banner("Atak!" if sim.stance == "attack" else "Obrona", "")
	banner_life = 1.2


func _cycle_speed() -> void:
	speed_mult = speed_mult % 3 + 1


func _toggle_mute() -> void:
	sfx.muted = not sfx.muted


func _upgrade_selected() -> void:
	if selected == null or selected.team != 0:
		return
	if not sim.upgrade(selected) and sim.upgrade_cost(selected) > 0:
		_deny(selected.pos)


func _sell_selected() -> void:
	if selected != null and selected.team == 0 and sim.sell(selected):
		selected = null


func _set_selected_lane(lane: int) -> void:
	if selected != null and sim.set_lane(selected, lane):
		_float_text(selected.pos + Vector2(0, -26), "→ %s" % sim.lanes[lane].name, LANE_COLORS[lane])


func _open_overlay(which: String) -> void:
	overlay = which
	if which == "settings":
		sfx_slider.set_value_no_signal(Settings.sfx_volume)
		music_slider.set_value_no_signal(Settings.music_volume)


func _close_overlay() -> void:
	if overlay == "settings":
		Settings.save_all()
	overlay = ""


func _toggle_perf() -> void:
	Settings.show_perf = not Settings.show_perf
	Settings.save_all()


func _cycle_ui_scale() -> void:
	Settings.ui_scale_index = (Settings.ui_scale_index + 1) % Settings.UI_SCALES.size()
	Settings.save_all()
	_rebuild_ui.call_deferred()  # nie usuwaj przycisku w trakcie obsługi jego sygnału


# ================================================================ HUD

func _build_ui() -> void:
	var s := Settings.ui_scale()
	screen = view_size / s
	ui_layer = CanvasLayer.new()
	ui_layer.scale = Vector2(s, s)
	add_child(ui_layer)
	var ui := Control.new()
	ui.size = screen
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	ui_layer.add_child(ui)
	hud = Control.new()  # wszystko poza nakładkami — chowane w menu
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)

	# baner fal i komunikatów — w przestrzeni ekranu, niezależny od kamery
	fx_canvas = Control.new()
	fx_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_canvas.draw.connect(_draw_banner)
	hud.add_child(fx_canvas)

	# lewy górny róg: ekonomia i fale
	var info := VBoxContainer.new()
	info.position = Vector2(16, 8)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 0)
	hud.add_child(info)
	gold_label = _label("", 30, info, GOLD_COLOR)
	income_label = _label("", 16, info)
	wave_label = _label("", 16, info)
	perf_label = _label("", 13, info, Color(0.7, 1.0, 0.7))

	# prawy górny róg: sterowanie grą
	var top := HBoxContainer.new()
	top.position = Vector2(screen.x - 16 - 526, 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	hud.add_child(top)
	stance_button = _button("", Vector2(180, 52), _toggle_stance, top)
	speed_button = _button("", Vector2(64, 52), _cycle_speed, top)
	mute_button = _button("", Vector2(110, 52), _toggle_mute, top)
	_button("Mapa", Vector2(84, 52), _reset_camera, top)
	_button("II", Vector2(56, 52), func() -> void: _set_paused(true), top)

	# samouczek — pod górnym paskiem, na środku
	tutorial_panel = PanelContainer.new()
	tutorial_panel.custom_minimum_size = Vector2(520, 0)
	tutorial_panel.position = Vector2((screen.x - 520) / 2.0, 72)
	hud.add_child(tutorial_panel)
	var tut_box := HBoxContainer.new()
	tut_box.add_theme_constant_override("separation", 10)
	tutorial_panel.add_child(tut_box)
	tutorial_label = _label("", 16, tut_box, Color(1, 0.95, 0.8))
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.custom_minimum_size = Vector2(390, 0)
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button("Pomiń", Vector2(90, 40), _finish_tutorial, tut_box)

	# minimapa pod przyciskami — widoczna po przybliżeniu
	minimap = Control.new()
	minimap.position = Vector2(screen.x - 16 - 240, 76)
	minimap.size = Vector2(240, 240 * sim.size.y / sim.size.x)
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.draw.connect(_draw_minimap)
	minimap.gui_input.connect(_on_minimap_input)
	hud.add_child(minimap)

	# dół: budowa (6) i umiejętności (3) — szerokość przycisków dopasowana do ekranu
	var w := minf(120.0, floorf((screen.x - 32 - 62) / 9.0))
	var bar := HBoxContainer.new()
	bar.position = Vector2(16, screen.y - 72)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	hud.add_child(bar)
	for key in Cfg.BUILD_ORDER:
		var b := _button("", Vector2(w, 60), _select_mode.bind(key), bar)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 15)
		build_buttons[key] = b
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	for a in Cfg.ABILITY_ORDER:
		var b := _button("", Vector2(w, 60), _select_ability.bind(a), bar)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 15)
		b.self_modulate = Color(0.85, 0.95, 1.0)
		ability_buttons[a] = b

	# prawy dół (nad paskiem): panel zaznaczonego budynku
	sel_panel = PanelContainer.new()
	sel_panel.custom_minimum_size = Vector2(320, 0)
	hud.add_child(sel_panel)
	var sel_box := VBoxContainer.new()
	sel_panel.add_child(sel_box)
	sel_title = _label("", 20, sel_box)
	sel_body = _label("", 14, sel_box, Color(1, 1, 1, 0.85))
	lane_row = HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 6)
	sel_box.add_child(lane_row)
	for i in sim.lanes.size():
		var lb := _button(sim.lanes[i].name, Vector2(98, 42), _set_selected_lane.bind(i), lane_row)
		lb.toggle_mode = true
		lb.add_theme_color_override("font_pressed_color", LANE_COLORS[i])
		lb.add_theme_color_override("font_hover_pressed_color", LANE_COLORS[i])
		lane_buttons.append(lb)
	var sel_buttons := HBoxContainer.new()
	sel_buttons.add_theme_constant_override("separation", 8)
	sel_box.add_child(sel_buttons)
	upgrade_button = _button("", Vector2(150, 48), _upgrade_selected, sel_buttons)
	sell_button = _button("", Vector2(150, 48), _sell_selected, sel_buttons)

	_build_menu(ui)
	_build_pause(ui)
	_build_over(ui)
	_build_settings(ui)
	_build_help(ui)


func _build_menu(ui: Control) -> void:
	menu_layer = _overlay(ui, 0.55)
	var box: VBoxContainer = menu_layer.get_child(0).get_child(0)
	_label("TOWER DEFENSE", 52, box, GOLD_COLOR)
	_label("Rozbuduj ekonomię. Wyślij armię. Zburz fortecę wroga.", 18, box)
	# rasy: wszystkie z Races.ALL, grywalne z ramką w kolorze rasy, reszta „Wkrótce"
	var races := GridContainer.new()
	races.columns = 6
	races.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	races.add_theme_constant_override("h_separation", 8)
	races.add_theme_constant_override("v_separation", 8)
	box.add_child(races)
	for i in Races.ALL.size():
		var r: Dictionary = Races.ALL[i]
		var b := _button(r["name"] if r["playable"] else "%s\nWkrótce" % r["name"], Vector2(140, 50), _select_race.bind(i), races)
		b.toggle_mode = true
		b.disabled = not r["playable"]
		b.add_theme_font_size_override("font_size", 15)
		if r["playable"]:
			for look in ["normal", "hover"]:
				var sb := (ui.theme.get_stylebox(look, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
				sb.border_color = (r["color"] as Color).lightened(0.25)
				sb.border_width_bottom = 5
				b.add_theme_stylebox_override(look, sb)
		race_buttons.append(b)
	race_desc = _label("", 15, box, Color(1, 1, 1, 0.8))
	var maps := HBoxContainer.new()
	maps.alignment = BoxContainer.ALIGNMENT_CENTER
	maps.add_theme_constant_override("separation", 10)
	box.add_child(maps)
	for i in Levels.ALL.size():
		var b := _button("", Vector2(230, 62), _select_level.bind(i), maps)
		b.toggle_mode = true
		map_buttons.append(b)
	map_desc = _label("", 15, box, Color(1, 1, 1, 0.8))
	var diffs := HBoxContainer.new()
	diffs.alignment = BoxContainer.ALIGNMENT_CENTER
	diffs.add_theme_constant_override("separation", 10)
	box.add_child(diffs)
	for d in Cfg.DIFFICULTIES.size():
		diff_buttons.append(_button("", Vector2(210, 62), _start.bind(d), diffs))
	var extra := HBoxContainer.new()
	extra.alignment = BoxContainer.ALIGNMENT_CENTER
	extra.add_theme_constant_override("separation", 10)
	box.add_child(extra)
	_button("Jak grać", Vector2(180, 46), _open_overlay.bind("help"), extra)
	_button("Ustawienia", Vector2(180, 46), _open_overlay.bind("settings"), extra)


func _build_pause(ui: Control) -> void:
	pause_layer = _overlay(ui)
	var box: VBoxContainer = pause_layer.get_child(0).get_child(0)
	_label("Pauza", 52, box)
	for entry in [["Wznów", func() -> void: _set_paused(false)],
			["Zacznij od nowa", func() -> void: _start(difficulty)],
			["Ustawienia", _open_overlay.bind("settings")],
			["Menu główne", _show_menu]]:
		var b := _button(entry[0], Vector2(300, 54), entry[1], box)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _build_over(ui: Control) -> void:
	over_layer = _overlay(ui)
	var box: VBoxContainer = over_layer.get_child(0).get_child(0)
	over_title = _label("", 64, box)
	over_stats = _label("", 18, box, Color(1, 1, 1, 0.85))
	for entry in [["Jeszcze raz", func() -> void: _start(difficulty)], ["Menu główne", _show_menu]]:
		var b := _button(entry[0], Vector2(300, 58), entry[1], box)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _build_settings(ui: Control) -> void:
	settings_layer = _overlay(ui)
	var box: VBoxContainer = settings_layer.get_child(0).get_child(0)
	_label("Ustawienia", 44, box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	_label("Efekty", 18, grid)
	sfx_slider = _slider(grid, func(v: float) -> void:
		Settings.sfx_volume = v
		Settings.apply_audio()
		sfx.play("coin", 0.1))
	_label("Muzyka", 18, grid)
	music_slider = _slider(grid, func(v: float) -> void:
		Settings.music_volume = v
		Settings.apply_audio())
	_label("Interfejs", 18, grid)
	scale_button = _button("", Vector2(300, 48), _cycle_ui_scale, grid)
	_label("Licznik FPS (F3)", 18, grid)
	perf_button = _button("", Vector2(300, 48), _toggle_perf, grid)
	for entry in [["Pokaż samouczek ponownie", _reset_tutorial], ["Wróć", _close_overlay]]:
		var b := _button(entry[0], Vector2(320, 50), entry[1], box)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _build_help(ui: Control) -> void:
	help_layer = _overlay(ui, 0.9)
	var box: VBoxContainer = help_layer.get_child(0).get_child(0)
	_label("Jak grać", 44, box)
	var help := _label(
		"Trzy ścieżki prowadzą do fortecy wroga. Klik w złoże (●) stawia wydobywacz; sporne złoża\n"
		+ "przy ścieżkach wroga dają więcej, ale przechodzące fale je atakują.\n"
		+ "Koszary, strzelnice i warsztaty same produkują jednostki — w panelu budynku wybierasz ścieżkę.\n"
		+ "Wieże strzelają też w nietoperze, armaty biją obszarowo, mróz spowalnia, katapulty burzą wieże.\n"
		+ "Tarczownicy blokują większość strzał — na nich armaty i piechota. Wróg chętniej atakuje\n"
		+ "słabo bronione ścieżki. Postawa „Obrona” zbiera armię przed bazą — „Atak” rusza całością.\n"
		+ "Umiejętności: Deszcz strzał (obszar), Pobór (posiłki przy ścieżce), Naprawa (budynki i baza).\n\n"
		+ "Mapę przesuwasz przeciągając, przybliżasz kółkiem albo dwoma palcami.\n"
		+ "Skróty: 1–6 budowa · Q/E/R umiejętności · Spacja postawa · U ulepsz · Del sprzedaj\n"
		+ "Tab ścieżka · F prędkość · WASD przesuwanie · C cała mapa · M dźwięk · Esc pauza",
		15, box, Color(1, 1, 1, 0.85))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var b := _button("Wróć", Vector2(300, 50), _close_overlay, box)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _rebuild_ui() -> void:
	ui_layer.free()
	build_buttons.clear()
	ability_buttons.clear()
	lane_buttons.clear()
	race_buttons.clear()
	map_buttons.clear()
	diff_buttons.clear()
	_build_ui()


func _update_hud() -> void:
	hud.visible = state != State.MENU
	menu_layer.visible = state == State.MENU and overlay == ""
	pause_layer.visible = state == State.PAUSED and overlay == ""
	over_layer.visible = state == State.OVER and over_delay <= 0 and overlay == ""
	settings_layer.visible = overlay == "settings"
	help_layer.visible = overlay == "help"
	if state == State.MENU:
		_update_menu()
	if settings_layer.visible:
		scale_button.text = Settings.UI_SCALE_NAMES[Settings.ui_scale_index]
		perf_button.text = "wł." if Settings.show_perf else "wył."

	gold_label.text = "%d zł" % int(sim.gold)
	income_label.text = "+%.1f zł/s · armia %d/%d" % [sim.income(), sim.army_size(0), Cfg.MAX_ARMY]
	perf_label.visible = Settings.show_perf
	if perf_label.visible:
		perf_label.text = "FPS %d · sim %.1f ms (%d kr.) · rys. %.1f ms · HUD %.1f ms · jedn. %d · efekty %d" % [
			Engine.get_frames_per_second(), perf["sim"], perf["steps"], perf["draw"], perf["hud"],
			sim.units.size(), sparks.size() + texts.size()]
		if state == State.PLAY and time >= perf_log_at:
			perf_log_at = time + 5.0
			print("[perf] %ds · %s" % [sim.elapsed, perf_label.text])
	if not sim.spawn_queue.is_empty():
		wave_label.text = "Fala %d nadciąga! (zostało %d)" % [sim.wave, sim.spawn_queue.size()]
	else:
		wave_label.text = "Fala %d za %d s → %s" % [sim.wave + 1, ceili(sim.wave_timer), sim.lane_names(sim.next_wave_lanes)]

	stance_button.text = "Postawa: Atak" if sim.stance == "attack" else "Postawa: Obrona"
	stance_button.self_modulate = Color(1, 0.75, 0.7) if sim.stance == "attack" else Color(0.7, 0.85, 1)
	speed_button.text = "x%d" % speed_mult
	mute_button.text = "Dźwięk" if not sfx.muted else "Cisza"
	minimap.visible = _is_zoomed_in() and (state == State.PLAY or state == State.PAUSED)

	for key in build_buttons:
		var b: Button = build_buttons[key]
		var cfg: Dictionary = Cfg.BUILDINGS[key]
		b.text = "%s\n%d" % [cfg["name"], cfg["cost"]]
		b.button_pressed = mode == key
		b.disabled = sim.gold < cfg["cost"] and mode != key
	for a in ability_buttons:
		var b: Button = ability_buttons[a]
		var cd: float = sim.ability_cd[0][a]
		b.text = "%s\n%s" % [Cfg.ABILITIES[a]["short"], "gotowe" if cd <= 0 else "%d s" % ceili(cd)]
		b.button_pressed = mode == "ab:" + a
		b.disabled = cd > 0

	tutorial_panel.visible = tutorial_step >= 0 and state == State.PLAY
	if tutorial_panel.visible:
		tutorial_label.text = "%d/%d  %s" % [tutorial_step + 1, TUTORIAL.size(), TUTORIAL[tutorial_step]["text"]]

	if selected != null and not sim.is_alive(selected):
		selected = null
	sel_panel.visible = selected != null and state == State.PLAY
	if sel_panel.visible:
		_fill_selection_panel(selected)
		sel_panel.reset_size()
		sel_panel.position = Vector2(screen.x - 16 - sel_panel.size.x, screen.y - 84 - sel_panel.size.y)


func _update_menu() -> void:
	for i in race_buttons.size():
		race_buttons[i].button_pressed = i == race_index
	var race: Dictionary = Races.ALL[race_index]
	race_desc.text = "%s — %s  Przeciwnik: %s" % [race["name"], race["blurb"], Races.ALL[Races.rival(race_index)]["name"]]
	for i in map_buttons.size():
		var lv: Dictionary = Levels.ALL[i]
		map_buttons[i].text = "%s\n%s" % [lv["name"], _stars_text(Progress.stars(lv["id"]))]
		map_buttons[i].button_pressed = i == level_index
	var cur: Dictionary = Levels.ALL[level_index]
	map_desc.text = cur["desc"]
	for d in diff_buttons.size():
		var best := Progress.best(cur["id"], d)
		diff_buttons[d].text = "%s\n%s" % [Cfg.DIFFICULTIES[d]["name"], "rekord %s" % _fmt_time(best) if best >= 0 else "—"]


func _fill_selection_panel(b: Sim.Building) -> void:
	var cfg: Dictionary = Cfg.BUILDINGS[b.kind]
	var lines := PackedStringArray()
	var next_level := b.level + 1
	var has_next := b.level < Cfg.MAX_LEVEL
	if Cfg.is_tower(b.kind):
		var s := sim.tower_stats(b.kind, b.level)
		lines.append("Obrażenia %d · zasięg %d · co %.1f s" % [s["dmg"], s["range"], s["cd"]])
		if s["slow"] > 0:
			lines.append("Spowalnia o %d%% na %.1f s (obszar %d)" % [s["slow"] * 100, s["slow_time"], s["splash"]])
		elif s["splash"] > 0:
			lines.append("Obrażenia obszarowe (promień %d)" % s["splash"])
		lines.append("Trafia latające" if Cfg.ANTI_AIR.has(s["projectile"]) else "Nie trafia latających")
		if has_next and b.team == 0:
			var n := sim.tower_stats(b.kind, next_level)
			lines.append("Poz. %d: obr. %d · zasięg %d" % [next_level, n["dmg"], n["range"]])
	elif Cfg.is_production(b.kind):
		var unit: String = cfg["unit"]
		lines.append("%s poz. %d co %.1f s → %s" % [Cfg.UNITS[unit]["name"], b.level,
			sim.production_period(b.kind, b.level), sim.lanes[b.lane].name])
		lines.append("Jednostka: HP %d · obr. %d" % [sim.unit_hp(unit, b.level), sim.unit_dmg(unit, b.level)])
		if sim.team_count[0] >= Cfg.MAX_ARMY:
			lines.append("Limit armii (%d) — produkcja czeka na miejsce" % Cfg.MAX_ARMY)
		if has_next:
			lines.append("Poz. %d: co %.1f s · HP %d · obr. %d" % [next_level, sim.production_period(b.kind, next_level),
				sim.unit_hp(unit, next_level), sim.unit_dmg(unit, next_level)])
	elif b.kind == "extractor":
		var rich := sim.richness[b.node_index] > 1.0
		lines.append("Wydobycie +%.1f zł/s%s" % [sim.extractor_income(b.node_index, b.level), " (bogate złoże)" if rich else ""])
		if has_next:
			lines.append("Poz. %d: +%.1f zł/s" % [next_level, sim.extractor_income(b.node_index, next_level)])
	if b.hp < b.max_hp:
		lines.append("Wytrzymałość %d / %d" % [b.hp, b.max_hp])

	if b.team == 1:
		sel_title.text = "%s wroga — poz. %d" % [cfg["name"], b.level]
		lines.append("Zburzysz ją katapultą albo szturmem.")
	else:
		sel_title.text = "%s — poz. %d/%d" % [cfg["name"], b.level, Cfg.MAX_LEVEL]
	sel_body.text = "\n".join(lines)

	lane_row.visible = b.team == 0 and Cfg.is_production(b.kind)
	for i in lane_buttons.size():
		lane_buttons[i].button_pressed = b.lane == i
	upgrade_button.get_parent().visible = b.team == 0
	var up := sim.upgrade_cost(b)
	upgrade_button.text = "Maks. poziom" if up < 0 else "Ulepsz  %d" % up
	upgrade_button.disabled = up < 0 or sim.gold < up
	sell_button.text = "Sprzedaj  +%d" % sim.sell_value(b)


func _on_minimap_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var held: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if clicked or held:
		camera.position = event.position * (sim.size.x / minimap.size.x)
		_clamp_camera()
		camera_used = true
		minimap.accept_event()


static func _fmt_time(t: float) -> String:
	return "%d:%02d" % [floori(t / 60.0), int(t) % 60]


static func _stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(Cfg.DIFFICULTIES.size() - n)


func _label(text: String, size: int, parent: Control, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if parent is VBoxContainer and parent.get_parent() is CenterContainer else HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4 if size >= 16 else 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(text: String, min_size: Vector2, on_press: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE  # inaczej Spacja „klika" ostatni przycisk
	b.pressed.connect(func() -> void:
		sfx.play("click", 0.0)
		on_press.call())
	parent.add_child(b)
	return b


func _slider(parent: Control, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(300, 40)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	parent.add_child(s)
	return s


## Pełnoekranowa, przyciemniona nakładka z wyśrodkowaną kolumną (menu, pauza, koniec…).
func _overlay(ui: Control, dim := 0.8) -> Control:
	var root := ColorRect.new()
	root.color = Color(0.03, 0.05, 0.04, dim)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	ui.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	return root


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 18
	var looks := {
		"normal": Color(0.13, 0.17, 0.2, 0.92),
		"hover": Color(0.2, 0.26, 0.3, 0.95),
		"pressed": Color(0.55, 0.42, 0.12, 0.95),
		"hover_pressed": Color(0.62, 0.48, 0.15, 0.95),
		"disabled": Color(0.1, 0.12, 0.14, 0.7),
	}
	for look in looks:
		var sb := StyleBoxFlat.new()
		sb.bg_color = looks[look]
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.12) if look != "pressed" and look != "hover_pressed" else GOLD_COLOR
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		th.set_stylebox(look, "Button", sb)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.1, 0.12, 0.92)
	panel.set_corner_radius_all(12)
	panel.set_border_width_all(2)
	panel.border_color = Color(1, 1, 1, 0.15)
	panel.set_content_margin_all(12)
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


# ================================================================ teren (liczony przy zmianie mapy)

func _make_terrain() -> void:
	lane_points.clear()
	river_points = PackedVector2Array()
	bridge_planks = PackedVector2Array()
	bridge_rails = PackedVector2Array()
	grass.clear()
	trees.clear()
	for lane in sim.lanes:
		lane_points.append(lane.curve.get_baked_points())
	if sim.river != null:
		river_points = sim.river.get_baked_points()

	# mosty (odcinki ścieżek nad rzeką liczy Sim): deski w poprzek, poręcze wzdłuż
	for br in sim.bridges:
		var lane := sim.lanes[br["lane"]]
		var prev_l := Vector2.ZERO
		var prev_r := Vector2.ZERO
		var s: float = br["s0"]
		while s <= br["s1"] + 0.01:
			var p := lane.point_at(s)
			var n := lane.normal_at(s)
			var l := p + n * (Cfg.PATH_HALF + 5.0)
			var r := p - n * (Cfg.PATH_HALF + 5.0)
			bridge_planks.append(l)
			bridge_planks.append(r)
			if s > br["s0"]:
				for q in [prev_l, l, prev_r, r]:
					bridge_rails.append(q)
			prev_l = l
			prev_r = r
			s += Sim.BRIDGE_STEP

	# trawa i kwiatki tam, gdzie nie ma ścieżek; drzewa poza strefą budowy i ścieżkami
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 7 + sim.level_index
	while grass.size() < 260:
		var p := Vector2(rnd.randf_range(10, sim.size.x - 10), rnd.randf_range(10, sim.size.y - 10))
		if _clear_of_paths(p, Cfg.PATH_HALF + 6.0):
			grass.append(Vector3(p.x, p.y, rnd.randi_range(0, 5)))
	var slots: Array[Vector2] = []
	for i in sim.enemy_slot_count():
		slots.append(sim.enemy_slot_pos(i))
	var zone := sim.build_rect.grow(30.0)
	var tries := 0
	while trees.size() < 70 and tries < 5000:
		tries += 1
		var p := Vector2(rnd.randf_range(0, sim.size.x), rnd.randf_range(0, sim.size.y))
		if zone.has_point(p) or not _clear_of_paths(p, Cfg.PATH_HALF + 26.0):
			continue
		if p.distance_to(sim.e_base) < 110 or _near_any(p, sim.nodes, 50.0) or _near_any(p, slots, 50.0):
			continue
		trees.append(Vector3(p.x, p.y, rnd.randf_range(12, 22)))

	grass_batch.clear()
	for g in grass:
		var p := Vector2(g.x, g.y)
		match int(g.z):
			0, 1, 2:
				grass_batch.line(p, p + Vector2(-2, -6), Color(0.22, 0.32, 0.19), 2.0)
				grass_batch.line(p, p + Vector2(2, -7), Color(0.22, 0.32, 0.19), 2.0)
			3:
				grass_batch.circle(p, 2.5, Color(0.9, 0.85, 0.5, 0.6))
			4:
				grass_batch.circle(p, 2.5, Color(0.85, 0.6, 0.8, 0.6))
			5:
				grass_batch.circle(p, 5.0, Color(0.3, 0.33, 0.3))
	tree_batch.clear()
	for t in trees:
		var p := Vector2(t.x, t.y)
		tree_batch.circle(p + Vector2(4, 6), t.z, Color(0, 0, 0, 0.22))
		tree_batch.circle(p, t.z, Color(0.12, 0.26, 0.13))
		tree_batch.circle(p + Vector2(-t.z * 0.3, -t.z * 0.3), t.z * 0.65, Color(0.17, 0.34, 0.17))
	terrain.queue_redraw()

	# podświetlenia ścieżek (ostrzeżenie fali, wybrana ścieżka produkcji) jako Line2D —
	# geometria liczona raz tutaj; co klatkę zmieniamy tylko widoczność i jasność
	for line in warn_lines + pick_lines:
		line.queue_free()
	warn_lines.clear()
	pick_lines.clear()
	for i in lane_points.size():
		warn_lines.append(_lane_line(lane_points[i], PATH_COLOR.lerp(WARN_COLOR, 0.3)))
	for i in lane_points.size():
		pick_lines.append(_lane_line(lane_points[i], PATH_COLOR.lerp(LANE_COLORS[i], 0.35)))


func _lane_line(points: PackedVector2Array, color: Color) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = Cfg.PATH_HALF * 2
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = -1  # nad terenem (dodana później), pod wszystkim z main._draw
	line.visible = false
	add_child(line)
	return line


func _update_lane_fx() -> void:
	var warn := _warn_lanes()
	var pulse := 0.85 + 0.15 * sin(time * 6.0)
	var pick := -1
	if selected != null and selected.team == 0 and Cfg.is_production(selected.kind) and sim.is_alive(selected):
		pick = selected.lane
	elif _is_build_mode() and Cfg.is_production(mode) and (pointer_active or dragging) and state == State.PLAY:
		pick = sim.nearest_lane(Cfg.snap(_to_world(pointer_screen)))
	for i in warn_lines.size():
		warn_lines[i].visible = warn.has(i)
		warn_lines[i].modulate = Color(pulse, pulse, pulse)
		pick_lines[i].visible = i == pick


func _clear_of_paths(p: Vector2, margin: float) -> bool:
	for lane in sim.lanes:
		if lane.distance_to(p) < margin:
			return false
	return sim.river_distance(p) > Cfg.RIVER_HALF + 6.0


func _near_any(p: Vector2, points: Array[Vector2], dist: float) -> bool:
	for q in points:
		if p.distance_to(q) < dist:
			return true
	return false


# ================================================================ render świata

## Rysowane co klatkę: wszystko, co się rusza. Statyczny teren ma własną warstwę
## (`terrain`, z_index -1), przerysowywaną tylko przy zmianie mapy. Obiekty poza
## kadrem są pomijane.
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	pen.clear()
	var view := Rect2(_to_world(Vector2.ZERO), view_size / camera.zoom.x).grow(60.0)
	low_detail = sim.units.size() > LOD_UNITS and not _is_zoomed_in()
	_draw_overlays()
	for n in sim.nodes:
		_draw_resource_node(n)
	for team in 2:
		_draw_base(team)
	for b in sim.buildings:
		if b.kind != "basegun" and view.has_point(b.pos):
			_draw_building(b)
	for u in sim.units:
		if not u.flying and view.has_point(u.pos):
			_draw_unit(u)
	for s in sim.shots:
		if view.has_point(s.pos):
			_draw_shot(s)
	for u in sim.units:
		if u.flying and view.has_point(u.pos):
			_draw_unit(u)  # latające nad resztą
	for st in sim.strikes:
		var r: float = st["cfg"]["radius"]
		pen.arc(st["pos"], r, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	for s in sparks:
		if not view.has_point(s.pos):
			continue
		var a := s.life / s.max_life
		if s.ring:
			pen.arc(s.pos, s.size * (1.0 - a * 0.6), 0, TAU, 40, Color(s.color, a * 0.8), 3.0)
		elif s.streak:
			pen.line(s.pos, s.pos - s.vel.normalized() * 14.0, Color(s.color, a), 2.0)
		else:
			pen.circle(s.pos, s.size * (0.4 + 0.6 * a), Color(s.color, a))
	for f in texts:
		var alpha := clampf(f.life * 2.0, 0.0, 1.0)
		pen.text_outline(font, f.pos - Vector2(100, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, 4, Color(0, 0, 0, alpha * 0.8))
		pen.text(font, f.pos - Vector2(100, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color(f.color, alpha))
	_draw_selection()
	_draw_ghost()
	pen.draw_on(self)  # cały świat jednym wywołaniem rysowania + napisy na wierzchu
	_perf_sample("draw", t0)


## Statyczny teren bieżącej mapy — rysowany na warstwie `terrain` tylko przy zmianie mapy.
func _draw_terrain() -> void:
	var c := terrain
	var size := sim.size
	c.draw_rect(Rect2(-400, -400, size.x + 800, size.y + 800), Color(0.1, 0.14, 0.1))
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.23, 0.15))
	grass_batch.draw_on(c)

	# rzeka
	if not river_points.is_empty():
		c.draw_polyline(river_points, Color(0.2, 0.3, 0.25), Cfg.RIVER_HALF * 2 + 10, true)
		c.draw_polyline(river_points, Color(0.2, 0.42, 0.62), Cfg.RIVER_HALF * 2, true)
		c.draw_polyline(river_points, Color(0.32, 0.55, 0.75, 0.6), Cfg.RIVER_HALF * 0.8, true)

	# ścieżki: najpierw wszystkie obrzeża, potem wypełnienia — przy bazach się zlewają
	for pts in lane_points:
		c.draw_polyline(pts, Color(0.33, 0.28, 0.2), Cfg.PATH_HALF * 2 + 6, true)
	for pts in lane_points:
		c.draw_polyline(pts, PATH_COLOR, Cfg.PATH_HALF * 2, true)
	if not bridge_planks.is_empty():  # mapa bez rzeki nie ma mostów (pusta tablica = błąd silnika)
		c.draw_multiline(bridge_planks, Color(0.55, 0.4, 0.25), 5.0)
	if not bridge_rails.is_empty():
		c.draw_multiline(bridge_rails, Color(0.35, 0.24, 0.14), 3.0)

	# nazwy ścieżek przy bazie gracza
	for i in sim.lanes.size():
		var lane := sim.lanes[i]
		var at := lane.slot_at(180.0, -(Cfg.PATH_HALF + 16.0))
		c.draw_string_outline(font, at - Vector2(50, -5), lane.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, 4, Color(0, 0, 0, 0.6))
		c.draw_string(font, at - Vector2(50, -5), lane.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, LANE_COLORS[i])

	tree_batch.draw_on(c)


## Zmienne nakładki na terenie: ostrzeżenia fal, wybrana ścieżka, strefa budowy, zbiórka.
func _draw_overlays() -> void:
	# ostrzeżenie: ścieżka nadchodzącej fali — samo podświetlenie to Line2D (_update_lane_fx)
	var pulse := 0.5 + 0.5 * sin(time * 6.0)
	for i in _warn_lanes():
		var lane := sim.lanes[i]
		var mark := lane.point_at(lane.length - 150.0)
		pen.circle(mark, 16 + 3 * pulse, Color(WARN_COLOR, 0.9))
		pen.text(font, mark + Vector2(-20, 9), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 26, Color.WHITE)

	# linia od zaznaczonego budynku produkcyjnego do jego ścieżki
	if selected != null and selected.team == 0 and Cfg.is_production(selected.kind) and sim.is_alive(selected):
		var lane := sim.lanes[selected.lane]
		var entry := lane.point_at(lane.offset_of(selected.pos))
		pen.dashed_line(selected.pos, entry, Color(LANE_COLORS[selected.lane], 0.9), 3.0, 8.0)

	# podświetlenia ścieżek są nieprzezroczyste — mosty dorysowane jeszcze raz na wierzch
	if not bridge_planks.is_empty():
		pen.multiline(bridge_planks, Color(0.55, 0.4, 0.25), 5.0)
	if not bridge_rails.is_empty():
		pen.multiline(bridge_rails, Color(0.35, 0.24, 0.14), 3.0)

	# strefa budowy: w trybie budowy podświetlone wolne pola (liczone tylko po zmianie budynków)
	if _is_build_mode():
		if _build_cells_version != sim.layout_version:
			_build_cells_version = sim.layout_version
			_build_cells.clear()
			var y := Cfg.GRID / 2
			while y <= sim.build_rect.end.y:
				var x := Cfg.GRID / 2
				while x <= sim.build_rect.end.x:
					if sim.can_place(Vector2(x, y)):
						_build_cells.append(Vector2(x, y))
					x += Cfg.GRID
				y += Cfg.GRID
		for c in _build_cells:
			pen.rect(Rect2(c - Vector2(18, 18), Vector2(36, 36)), Color(1, 1, 1, 0.07))

	# linie zbiórki — po jednej na każdej ścieżce
	if sim.stance == "defend" and state != State.MENU:
		for lane in sim.lanes:
			var s := sim.rally_s + 14.0
			var n := lane.normal_at(s)
			var p := lane.point_at(s)
			pen.dashed_line(p - n * Cfg.PATH_HALF, p + n * Cfg.PATH_HALF, Color(0.7, 0.85, 1, 0.8), 2.0, 5.0)
			var pole := p + n * Cfg.PATH_HALF
			pen.line(pole, pole + Vector2(0, -24), Color(0.85, 0.85, 0.85), 2.0)
			pen.polygon(PackedVector2Array([pole + Vector2(0, -24), pole + Vector2(15, -19), pole + Vector2(0, -14)]), TEAM_COLORS[0])


## Ścieżki, którymi właśnie idzie fala albo przyjdzie następna (w ciągu WAVE_WARNING s).
func _warn_lanes() -> Array[int]:
	var out: Array[int] = []
	if state == State.MENU:
		return out
	if not sim.spawn_queue.is_empty():
		for e in sim.spawn_queue:
			if not out.has(e["lane"]):
				out.append(e["lane"])
	elif sim.wave_timer <= Cfg.WAVE_WARNING:
		out = sim.next_wave_lanes.duplicate()
	return out


func _draw_resource_node(n: Vector2) -> void:
	var idx := sim.nodes.find(n)
	var rich := sim.richness[idx] > 1.0
	pen.circle(n + Vector2(0, 4), 20, Color(0, 0, 0, 0.2))
	pen.circle(n + Vector2(-7, 3), 10, Color(0.75, 0.6, 0.15))
	pen.circle(n + Vector2(7, 4), 9, Color(0.85, 0.68, 0.18))
	pen.circle(n + Vector2(0, -5), 11, Color(0.98, 0.83, 0.25) if not rich else Color(1.0, 0.92, 0.45))
	pen.circle(n + Vector2(-3, -8), 3, Color(1, 1, 0.8, 0.8))
	if rich:
		for i in 3:
			var a := time * 1.5 + TAU * i / 3.0
			pen.circle(n + Vector2.from_angle(a) * 22.0, 2.0, Color(1, 1, 0.8, 0.8))
	if sim.extractor_on(idx) == null and state == State.PLAY:
		var pulse := 0.3 + 0.2 * sin(time * 3.0)
		pen.arc(n, 26, 0, TAU, 32, Color(1, 1, 1, pulse), 2.0)
		if sim.gold >= Cfg.BUILDINGS["extractor"]["cost"]:
			pen.text(font, n + Vector2(-40, 44), "%d zł" % Cfg.BUILDINGS["extractor"]["cost"],
				HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(1, 1, 1, 0.6))


func _draw_base(team: int) -> void:
	var p := sim.base_pos(team)
	var c := TEAM_COLORS[team]
	var r := Cfg.BASE_R
	var body := Rect2(p - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.8))
	pen.rect(Rect2(body.position + Vector2(4, 6), body.size), Color(0, 0, 0, 0.25))
	pen.rect(body, c.darkened(0.45))
	for i in 4:
		pen.rect(Rect2(body.position + Vector2(i * r * 0.62, -10), Vector2(r * 0.4, 12)), c.darkened(0.45))
	pen.rect(body, c.darkened(0.1), false, 3.0)
	pen.rect(Rect2(p + Vector2(-10, r * 0.2), Vector2(20, r * 0.8)), Color(0.12, 0.08, 0.05))
	var pole := p + Vector2(0, -r * 0.8 - 10)
	pen.line(pole, pole + Vector2(0, -30), Color(0.85, 0.85, 0.85), 2.0)
	var flutter := sin(time * 4.0 + team) * 3.0
	pen.polygon(PackedVector2Array([pole + Vector2(0, -30), pole + Vector2(22 * (1 - 2 * team), -24 + flutter), pole + Vector2(0, -18)]), c)
	var race: String = Races.ALL[race_index if team == 0 else Races.rival(race_index)]["name"]
	pen.text_outline(font, pole + Vector2(-70, -40), race, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, 5, Color(0, 0, 0, 0.7))
	pen.text(font, pole + Vector2(-70, -40), race, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, c.lightened(0.35))
	if base_flash[team] > 0:
		pen.rect(body, Color(1, 1, 1, base_flash[team] * 4.0))
	var frac := sim.base_hp[team] / Cfg.BASE_HP[team]
	_hp_bar(p + Vector2(0, r + 18), 100, frac, 8)
	pen.text(font, p + Vector2(-50, r + 42), "%d" % int(sim.base_hp[team]), HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color(1, 1, 1, 0.8))


func _draw_building(b: Sim.Building) -> void:
	var c := TEAM_COLORS[b.team]
	_draw_building_shape(b.kind, b.pos, c, b.aim, 1.0)
	if b.flash > 0:
		pen.circle(b.pos, 18, Color(1, 1, 1, b.flash * 4.0))
	if Cfg.is_production(b.kind):
		_progress(b.pos + Vector2(0, 24), b.timer / sim.production_period(b.kind, b.level))
		# plakietka ścieżki, którą idą jednostki
		pen.circle(b.pos + Vector2(16, -16), 6.0, Color(0, 0, 0, 0.6))
		pen.circle(b.pos + Vector2(16, -16), 4.5, LANE_COLORS[b.lane])
	if b.hp < b.max_hp:
		_hp_bar(b.pos + Vector2(0, -26), 36, b.hp / b.max_hp, 5)
	for i in b.level - 1:
		pen.circle(b.pos + Vector2(-5 + i * 10, 32 if Cfg.is_production(b.kind) else 24), 3.0, GOLD_COLOR)


func _draw_building_shape(kind: String, p: Vector2, c: Color, aim: float, alpha: float) -> void:
	var dark := Color(c.darkened(0.35), alpha)
	var light := Color(c.lightened(0.2), alpha)
	var shadow := Color(0, 0, 0, 0.25 * alpha)
	match kind:
		"tower":
			pen.circle(p + Vector2(3, 4), 17, shadow)
			pen.circle(p, 17, dark)
			pen.arc(p, 17, 0, TAU, 24, light, 2.0)
			pen.circle(p, 8, light)
			pen.line(p, p + Vector2.from_angle(aim) * 14, Color(1, 1, 1, alpha), 3.0)
		"cannon":
			pen.rect(Rect2(p - Vector2(15, 15) + Vector2(3, 4), Vector2(30, 30)), shadow)
			pen.rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), Color(0.25, 0.25, 0.28, alpha))
			pen.rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), light, false, 2.0)
			pen.line(p, p + Vector2.from_angle(aim) * 22, Color(0.1, 0.1, 0.1, alpha), 8.0)
			pen.circle(p, 8, Color(0.4, 0.4, 0.45, alpha))
		"frost":
			var diamond := PackedVector2Array([p + Vector2(0, -19), p + Vector2(16, 0), p + Vector2(0, 19), p + Vector2(-16, 0)])
			pen.polygon(PackedVector2Array([p + Vector2(3, -15), p + Vector2(19, 4), p + Vector2(3, 23), p + Vector2(-13, 4)]), shadow)
			pen.polygon(diamond, Color(0.2, 0.35, 0.5, alpha))
			diamond.append(diamond[0])
			pen.polyline(diamond, light, 2.0)
			var glow := 0.6 + 0.4 * sin(time * 3.0)
			pen.circle(p, 7, Color(FROST_COLOR, alpha * glow))
		"barracks":
			pen.rect(Rect2(p - Vector2(17, 10) + Vector2(3, 4), Vector2(34, 27)), shadow)
			pen.rect(Rect2(p - Vector2(17, 10), Vector2(34, 27)), dark)
			pen.polygon(PackedVector2Array([p + Vector2(-20, -10), p + Vector2(0, -24), p + Vector2(20, -10)]), light)
			pen.rect(Rect2(p + Vector2(-5, 4), Vector2(10, 13)), Color(0.1, 0.07, 0.05, alpha))
		"range":
			pen.polygon(PackedVector2Array([p + Vector2(3, -15), p + Vector2(21, 19), p + Vector2(-15, 19)]), shadow)
			pen.polygon(PackedVector2Array([p + Vector2(0, -19), p + Vector2(18, 15), p + Vector2(-18, 15)]), dark)
			pen.circle(p + Vector2(0, 3), 7, Color(1, 1, 1, alpha))
			pen.circle(p + Vector2(0, 3), 4, Color(0.9, 0.2, 0.2, alpha))
		"workshop":
			var pts := PackedVector2Array()
			for i in 6:
				pts.append(p + Vector2.from_angle(TAU * i / 6.0) * 18)
			pen.polygon(pts, Color(0.45, 0.32, 0.2, alpha))
			pts.append(pts[0])
			pen.polyline(pts, light, 2.0)
			for i in 4:
				var a := time * 1.5 + TAU * i / 4.0
				pen.line(p, p + Vector2.from_angle(a) * 10, Color(0.8, 0.8, 0.8, alpha), 3.0)
			pen.circle(p, 4, Color(0.3, 0.3, 0.3, alpha))
		"extractor":
			pen.rect(Rect2(p - Vector2(14, 14), Vector2(28, 28)), Color(0.3, 0.3, 0.34, alpha))
			pen.rect(Rect2(p - Vector2(14, 14), Vector2(28, 28)), light, false, 3.0)
			for i in 4:
				var a := time * 3.0 + TAU * i / 4.0
				pen.line(p, p + Vector2.from_angle(a) * 11, Color(0.95, 0.8, 0.3, alpha), 3.0)
			pen.circle(p, 4, Color(0.2, 0.2, 0.2, alpha))


## `low_detail`: w dużej bitwie (widok całej mapy) bez cienia, obrysu, podskoku
## i pasków HP zdrowych jednostek — to połowa wywołań rysowania na jednostkę.
func _draw_unit(u: Sim.Unit) -> void:
	var r := u.radius
	var dir := 1.0 if u.team == 0 else -1.0
	var at := u.prev_pos.lerp(u.pos, render_alpha)  # interpolacja między krokami sima
	var p := at if low_detail else at + Vector2(0, sin(time * 12.0 + u.id) * 1.2)
	var c := TEAM_COLORS[u.team]
	if u.flying:
		pen.circle(at + Vector2(8, 18), r * 0.7, Color(0, 0, 0, 0.18))  # cień daleko = wysoko
	elif not low_detail:
		pen.circle(at + Vector2(2, r * 0.7), r * 0.9, Color(0, 0, 0, 0.2))
		pen.circle(p, r + 1.5, Color(0, 0, 0, 0.35))  # obrys (koło jest tańsze niż łuk)
	match u.kind:
		"soldier":
			pen.circle(p, r, c)
			pen.line(p + Vector2(dir * r * 0.4, 0), p + Vector2(dir * r * 1.5, -r * 0.6), Color(0.9, 0.9, 0.95), 2.0)
		"archer":
			pen.circle(p, r, c.lightened(0.15))
			pen.arc(p + Vector2(dir * r * 0.5, 0), r * 0.9, -PI / 2 if dir > 0 else PI / 2, PI / 2 if dir > 0 else 3 * PI / 2, 8, Color(0.6, 0.4, 0.2), 2.0)
		"catapult":
			pen.rect(Rect2(p - Vector2(r, r * 0.5), Vector2(r * 2, r)), Color(0.5, 0.35, 0.2))
			pen.circle(p + Vector2(-r * 0.6, r * 0.5), 4, Color(0.2, 0.15, 0.1))
			pen.circle(p + Vector2(r * 0.6, r * 0.5), 4, Color(0.2, 0.15, 0.1))
			var swing := clampf(u.cd_left / u.cooldown, 0.0, 1.0)
			pen.line(p, p + Vector2.from_angle(-PI / 2 - dir * (0.3 + swing)) * r * 1.4, Color(0.65, 0.5, 0.3), 3.0)
			pen.rect(Rect2(p - Vector2(r, r * 0.5), Vector2(r * 2, r)), c, false, 2.0)
		"grunt":
			pen.circle(p, r, c)
			pen.line(p + Vector2(-4, -r + 2), p + Vector2(-6, -r - 4), Color(0.9, 0.85, 0.7), 2.0)
			pen.line(p + Vector2(4, -r + 2), p + Vector2(6, -r - 4), Color(0.9, 0.85, 0.7), 2.0)
		"runner":
			pen.line(p + Vector2(r, -3), p + Vector2(r + 8, -3), Color(1, 0.7, 0.3, 0.5), 2.0)
			pen.line(p + Vector2(r, 3), p + Vector2(r + 10, 3), Color(1, 0.7, 0.3, 0.5), 2.0)
			pen.circle(p, r, Color(1.0, 0.6, 0.25))
		"shield":
			pen.circle(p, r, c.darkened(0.15))
			pen.rect(Rect2(p + Vector2(dir * r * 0.5 - 3, -r * 0.9), Vector2(6, r * 1.8)), Color(0.72, 0.72, 0.78))
			pen.rect(Rect2(p + Vector2(dir * r * 0.5 - 3, -r * 0.9), Vector2(6, r * 1.8)), Color(0.3, 0.3, 0.35), false, 1.5)
		"bat":
			var flap := sin(time * 22.0 + u.id) * 5.0
			var wing := Color(0.35, 0.15, 0.4)
			pen.polygon(PackedVector2Array([p, p + Vector2(-r * 1.9, -4 + flap), p + Vector2(-r * 0.8, 4)]), wing)
			pen.polygon(PackedVector2Array([p, p + Vector2(r * 1.9, -4 + flap), p + Vector2(r * 0.8, 4)]), wing)
			pen.circle(p, r * 0.7, Color(0.5, 0.2, 0.55))
			pen.circle(p + Vector2(-2, -1), 1.3, WARN_COLOR)
			pen.circle(p + Vector2(2, -1), 1.3, WARN_COLOR)
		"brute":
			pen.circle(p, r, c.darkened(0.3))
			pen.arc(p, r, 0, TAU, 24, c.lightened(0.2), 3.0)
		"warlord":
			pen.circle(p, r, Color(0.55, 0.2, 0.6))
			pen.arc(p, r, 0, TAU, 32, GOLD_COLOR, 3.0)
			for i in 3:
				var cx := p + Vector2(-8 + i * 8, -r - 2)
				pen.polygon(PackedVector2Array([cx + Vector2(-4, 0), cx + Vector2(0, -8), cx + Vector2(4, 0)]), GOLD_COLOR)
	if u.slow_timer > 0:
		pen.arc(p, r + 3, 0, TAU, 12 if low_detail else 20, Color(FROST_COLOR, 0.9), 2.0)
	if u.flash > 0:
		pen.circle(p, r, Color(1, 1, 1, u.flash * 5.0))
	if low_detail:
		if u.hp < u.max_hp * 0.6:
			_hp_bar(p + Vector2(0, -r - 5), maxf(r * 2.4, 18.0), u.hp / u.max_hp, 4)
		return
	for i in u.level - 1:
		pen.circle(p + Vector2(-3 + i * 6, -r - 10), 2.0, GOLD_COLOR)
	if u.hp < u.max_hp:
		_hp_bar(p + Vector2(0, -r - 5), maxf(r * 2.4, 18.0), u.hp / u.max_hp, 4)


func _draw_shot(s: Sim.Shot) -> void:
	var at := s.prev_pos.lerp(s.pos, render_alpha)
	match s.kind:
		"arrow":
			var d := (s.target_pos - at).normalized()
			pen.line(at - d * 9.0, at, Color(0.95, 0.9, 0.75), 2.0)
		"frost":
			pen.circle(at, 6.0, Color(FROST_COLOR, 0.35))
			pen.circle(at, 3.0, Color(0.9, 0.97, 1.0))
		_:
			var total := s.start.distance_to(s.target_pos)
			var f := 1.0 - at.distance_to(s.target_pos) / maxf(total, 1.0)
			var h := sin(PI * clampf(f, 0.0, 1.0)) * minf(70.0, total * 0.35)
			var size := 4.0 if s.kind == "cannonball" else 5.0
			pen.circle(at, size * 0.8, Color(0, 0, 0, 0.3))
			pen.circle(at - Vector2(0, h), size, Color(0.15, 0.15, 0.15) if s.kind == "cannonball" else Color(0.55, 0.5, 0.45))


func _draw_selection() -> void:
	if selected == null or not sim.is_alive(selected):
		return
	var pulse := 0.6 + 0.4 * sin(time * 6.0)
	pen.arc(selected.pos, 24, 0, TAU, 32, Color(1, 1, 1, pulse), 2.0)
	if Cfg.is_tower(selected.kind):
		var rng_: float = sim.tower_stats(selected.kind, selected.level)["range"]
		pen.circle(selected.pos, rng_, Color(1, 1, 1, 0.05))
		pen.arc(selected.pos, rng_, 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0)


func _draw_ghost() -> void:
	if mode == "" or state != State.PLAY or not (pointer_active or dragging):
		return
	var world := _to_world(pointer_screen)
	var ability := _ability_mode()
	if ability != "":
		var ok := sim.ability_target_ok(ability, world)
		var tint := Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3)
		var r: float = Cfg.ABILITIES[ability].get("radius", 40.0)
		pen.circle(world, r, Color(tint, 0.12))
		pen.arc(world, r, 0, TAU, 48, Color(tint, 0.8), 2.0)
		return
	var cell := Cfg.snap(world)
	var ok := sim.can_place(cell)
	var tint := Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3)
	pen.rect(Rect2(cell - Vector2(Cfg.GRID, Cfg.GRID) / 2, Vector2(Cfg.GRID, Cfg.GRID)), Color(tint, 0.25))
	pen.rect(Rect2(cell - Vector2(Cfg.GRID, Cfg.GRID) / 2, Vector2(Cfg.GRID, Cfg.GRID)), Color(tint, 0.7), false, 2.0)
	_draw_building_shape(mode, cell, TEAM_COLORS[0], 0.0, 0.55)
	if Cfg.is_tower(mode):
		pen.arc(cell, sim.tower_stats(mode, 1)["range"], 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0)


func _hp_bar(center: Vector2, width: float, frac: float, height := 5.0) -> void:
	var tl := center - Vector2(width / 2, height / 2)
	pen.rect(Rect2(tl - Vector2(1, 1), Vector2(width + 2, height + 2)), Color(0, 0, 0, 0.6))
	var col := Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.25, 0.2), 1.0 - clampf(frac, 0, 1))
	pen.rect(Rect2(tl, Vector2(width * clampf(frac, 0, 1), height)), col)


func _progress(center: Vector2, frac: float) -> void:
	var tl := center - Vector2(17, 2)
	pen.rect(Rect2(tl, Vector2(34, 4)), Color(0, 0, 0, 0.5))
	pen.rect(Rect2(tl, Vector2(34 * clampf(frac, 0, 1), 4)), Color(1, 1, 1, 0.8))


# ================================================================ render ekranu (HUD)

func _draw_banner() -> void:
	if banner_life <= 0:
		return
	var c := fx_canvas
	var a := clampf(banner_life, 0.0, 1.0)
	var y := 190.0
	c.draw_string_outline(font, Vector2(0, y), banner_text, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 48, 8, Color(0, 0, 0, a * 0.7))
	c.draw_string(font, Vector2(0, y), banner_text, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 48, Color(1, 1, 1, a))
	if banner_sub != "":
		c.draw_string_outline(font, Vector2(0, y + 34), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 22, 6, Color(0, 0, 0, a * 0.7))
		c.draw_string(font, Vector2(0, y + 34), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 22, Color(1, 0.9, 0.7, a))


func _draw_minimap() -> void:
	var c := minimap
	var k := c.size.x / sim.size.x
	var xf := Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.1, 0.16, 0.1, 0.92))
	if not river_points.is_empty():
		c.draw_polyline(xf * river_points, Color(0.2, 0.42, 0.62), 3.0)
	for i in lane_points.size():
		c.draw_polyline(xf * lane_points[i], Color(0.55, 0.47, 0.34), 3.0)
	for i in _warn_lanes():
		c.draw_polyline(xf * lane_points[i], Color(WARN_COLOR, 0.7), 3.0)
	for team in 2:
		c.draw_rect(Rect2(sim.base_pos(team) * k - Vector2(5, 5), Vector2(10, 10)), TEAM_COLORS[team])
	for b in sim.buildings:
		if b.kind != "basegun":
			c.draw_rect(Rect2(b.pos * k - Vector2(2, 2), Vector2(4, 4)), TEAM_COLORS[b.team].lightened(0.3))
	for u in sim.units:
		c.draw_rect(Rect2(u.pos * k - Vector2(1, 1), Vector2(2, 2)), TEAM_COLORS[u.team])
	var view := Rect2(_to_world(Vector2.ZERO) * k, view_size / camera.zoom.x * k)
	c.draw_rect(view, Color(1, 1, 1, 0.9), false, 1.5)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.3), false, 1.0)
