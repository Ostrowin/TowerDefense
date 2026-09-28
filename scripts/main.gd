class_name Main
extends Node2D
## Scena gry: przebieg (menu → partia → koniec), pętla symulacji, zdarzenia sim → efekty i dźwięk,
## samouczek i kamera. Logika gry siedzi w Sim (scripts/sim.gd) — tutaj wyłącznie prezentacja.
## Reszta widoku w osobnych plikach: `view` (WorldView — render świata), `hud` (Hud — HUD, menu,
## nakładki), `controls` (Controls — input, dowódca, budowa i umiejętności).
##
## Stany ekranu (nakładki „Ustawienia" i „Jak grać" leżą nad każdym z nich):
##
##   MENU ──(mapa + trudność)──▶ PLAY ◀──(Wznów)── PAUSED
##                                │  ──(Esc/P/II)──▶
##                                ▼ (sim.result != 0)
##                              OVER ──(Jeszcze raz)──▶ PLAY
##                                   ──(Menu)────────▶ MENU

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
const HEAL_COLOR := Color(0.45, 1.0, 0.55)
const OVER_DELAY := 1.6
## Limity efektów — każda iskra i napis to osobne wywołania rysowania co klatkę.
const MAX_SPARKS := 250
const MAX_TEXTS := 24
const GOLD_TEXTS_MAX := 10  ## „+6 zł" pokazujemy tylko, gdy napisów jest mało
const HIT_FX_PER_FRAME := 6
const DEATH_FX_PER_FRAME := 8
const ZOOM_MAX := 2.0
const HIT_NOTICE_GAP := 4.0
const HERO_COLOR := Color(1.0, 0.85, 0.35)
const CURSE_COLOR := Color(0.72, 0.45, 1.0)  ## klątwy i wskrzeszenie

## Samouczek: krok kończy się, gdy spełniony jest warunek `done` (sprawdzany co klatkę).
const TUTORIAL: Array[Dictionary] = [
	{"text": "Kliknij złote złoże (●), żeby postawić wydobywacz — to Twój dochód.", "done": "extractor"},
	{"text": "Postaw Koszary (przycisk na dole) — piechurzy sami ruszą na wroga.", "done": "production"},
	{"text": "Czerwony „!” pokazuje ścieżkę następnej fali. Postaw przy niej wieżę.", "done": "tower"},
	{"text": "Kliknij swoje koszary: wybierz ścieżkę natarcia albo ulepsz budynek.", "done": "select_production"},
	{"text": "Przeciągnij mapę albo przybliż ją kółkiem / dwoma palcami.", "done": "camera"},
	{"text": "Stuknij swojego dowódcę (albo portret z lewej), potem miejsce na mapie — pójdzie tam i będzie walczył.", "done": "hero"},
	{"text": "Umiejętności dowódcy są na dole po prawej — rzuć jedną na grupę wrogów!", "done": "ability"},
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
## Gracz na tym telefonie (indeks w `sim.players`) — w grze solo 0; w sieci ustawia go lobby.
var me := 0
var state := State.MENU
var overlay := ""  ## "" / "settings" / "help" — nakładka nad bieżącym stanem
var level_index := 0
var race_index := Races.first_playable()  ## rasa gracza (Races.ALL)
var rival_index := -1  ## rasa przeciwnika — losowana przy starcie partii (-1 = jeszcze nie wybrana)
var difficulty := 1
var mode := ""  ## "" / klucz budynku z Cfg.BUILD_ORDER / "ab:<umiejętność>"
var selected: Sim.Building = null
## Tryb dowódcy (R6, D6): stuknięcie w pusty teren = rozkaz marszu, dowódca zostaje zaznaczony.
var hero_selected := false
var hero_ordered := false  ## samouczek: gracz wydał dowódcy rozkaz
## Dowódca gracza (id z Cfg.COMMANDERS) — wybór w menu po rasie; domyślnie pierwszy grywalny rasy.
var commander_id := ""
var commander_pick := {}
var game_mode := "battle"  ## "battle" / "survival" (T15) — przełącznik w menu
## Wyzwanie dnia (T16): zestaw z Cfg.daily (pusty = zwykła gra) i wybory z menu sprzed wyzwania,
## przywracane po powrocie do menu.
var daily := {}
var daily_prev := {}
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
var new_record := false

# samouczek
var tutorial_step := -1
var tutorial_timer := 0.0
var camera_used := false

# wskaźnik i gesty

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

var sfx: Sfx
var font: Font
var view: WorldView
var hud: Hud
var controls: Controls


func _ready() -> void:
	Settings.load_all()
	Settings.apply_audio()
	font = ThemeDB.fallback_font
	Art.load_all()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # sprite'y skalowane w dół
	sfx = Sfx.new()
	add_child(sfx)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	view = WorldView.new(self)
	controls = Controls.new(self)
	hud = Hud.new(self)
	sim = Sim.new(difficulty, -1, level_index)
	view.make_terrain()
	view_size = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_view_resized)
	hud.build_ui()
	show_menu()
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

func start(d: int) -> void:
	difficulty = d
	if commander_id == "" or not Races.commanders(race_index).has(commander_id):
		commander_id = default_commander(race_index)
	var rnd := RandomNumberGenerator.new()
	rnd.randomize()  # własny los — nie ruszamy rng sima
	rival_index = Races.random_rival(race_index, rnd)
	var rival_id: String = Races.ALL[rival_index]["id"]
	if daily.is_empty():
		sim = Sim.new(d, -1, level_index, commander_id, game_mode, [], rival_id)
	else:
		sim = Sim.new(d, daily["seed"], level_index, commander_id, game_mode, daily["mods"], rival_id)
	hero_ordered = false
	view.make_terrain()
	_clear_view_state()
	speed_mult = 1
	accum = 0.0
	state = State.PLAY
	overlay = ""
	tutorial_step = -1 if Progress.tutorial_done() else 0
	tutorial_timer = 0.0
	camera_used = false
	var rival_name: String = Races.ALL[rival_index]["name"]
	if sim.players[1].commander != "":
		rival_name += " (dowódca: %s)" % Cfg.COMMANDERS[sim.players[1].commander]["name"]
	banner("Przygotuj się!", "Przeciwnik: %s · pierwsza fala za %d s: %s" % [
		rival_name, int(sim.wave_timer), sim.lane_names(sim.next_wave_lanes)])
	if not daily.is_empty():
		banner("Wyzwanie dnia — %s" % daily["date"], "%s — %s · %s · %s · %s" % [Races.ALL[race_index]["name"],
			Cfg.COMMANDERS[commander_id]["name"], sim.level["name"], "Przetrwanie" if game_mode == "survival" else "Bitwa",
			mods_text(daily["mods"])])
		banner_life = 5.0


func show_menu() -> void:
	state = State.MENU
	overlay = ""
	rival_index = -1
	if not daily.is_empty():  # po wyzwaniu dnia wracają wybory gracza z menu
		level_index = daily_prev["level"]
		race_index = daily_prev["race"]
		commander_id = daily_prev["commander"]
		game_mode = daily_prev["mode"]
		daily = {}
		hud.fill_commander_row()
	sim = Sim.new(difficulty, -1, level_index)
	view.make_terrain()
	_clear_view_state()


func select_level(i: int) -> void:
	level_index = i
	show_menu()


## Domyślny dowódca rasy: ostatnio wybrany w tej sesji, inaczej pierwszy grywalny.
func default_commander(race_i: int) -> String:
	var picked: String = commander_pick.get(race_i, "")
	if picked != "" and Cfg.commander_ready(picked):
		return picked
	for c in Races.commanders(race_i):
		if Cfg.commander_ready(c):
			return c
	return ""


func select_race(i: int) -> void:
	if Races.ALL[i]["playable"]:
		race_index = i
		commander_id = default_commander(i)
		hud.fill_commander_row()


## Wyzwanie dnia: zestaw z dzisiejszej daty (lokalnej), start od razu.
func start_daily() -> void:
	daily_prev = {"level": level_index, "race": race_index, "commander": commander_id, "mode": game_mode}
	daily = Cfg.daily(Time.get_date_string_from_system())
	level_index = daily["map"]
	race_index = daily["race"]
	commander_id = daily["commander"]
	game_mode = daily["mode"]
	start(daily["difficulty"])


func mods_text(ids: Array) -> String:
	var parts := PackedStringArray()
	for id in ids:
		var m: Dictionary = Cfg.DAILY_MODS[id]
		parts.append("%s %s (%s)" % ["+" if m["good"] else "−", m["name"], m["desc"]])
	return " · ".join(parts)


func toggle_mode() -> void:
	game_mode = "survival" if game_mode == "battle" else "battle"


func select_commander(id: String) -> void:
	if Cfg.commander_ready(id):
		commander_id = id
		commander_pick[race_index] = id


func _clear_view_state() -> void:
	sparks.clear()
	texts.clear()
	hit_notice.clear()
	mode = ""
	selected = null
	hero_selected = false
	controls.dragging = false
	controls.panning = false
	controls.press_button = -1
	shake = 0.0
	banner_life = 0.0
	tutorial_step = -1
	reset_camera()


## Rozkaz gracza z tego telefonu jako komenda Sim (multiplayer T2) — widok nie woła rozkazów Sim wprost.
## Solo: wykonuje się od razu (między krokami). W sieci pójdzie przez NetSession (T4).
func send(cmd: Dictionary) -> bool:
	cmd["player"] = me
	return sim.apply(cmd)


func set_paused(p: bool) -> void:
	if p and state == State.PLAY:
		state = State.PAUSED
		controls.dragging = false
		controls.press_button = -1
	elif not p and state == State.PAUSED:
		state = State.PLAY
		overlay = ""


func _notification(what: int) -> void:
	# Android: wyjście z aplikacji / telefon w tle = auto-pauza.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == State.PLAY:
			set_paused(true)
	# Android: systemowe „Wstecz" działa jak Esc, a w menu głównym zamyka grę
	# (project.godot ma quit_on_go_back = false — inaczej silnik zamykałby grę od razu).
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not back():
			get_tree().quit()


## Esc / „Wstecz": zamknij nakładkę → anuluj tryb/zaznaczenie → pauza ⇄ gra → z ekranu końca
## do menu. Zwraca false, gdy nie ma się już dokąd cofnąć (menu główne).
func back() -> bool:
	if overlay != "":
		close_overlay()
	elif state == State.PLAY and (mode != "" or selected != null or hero_selected):
		controls.cancel()
	elif state == State.PLAY or state == State.PAUSED:
		set_paused(state == State.PLAY)
	elif state == State.OVER:
		show_menu()
	else:
		return false
	return true


## Zmiana rozmiaru okna albo proporcji ekranu: nowy widoczny obszar, kamera i HUD od nowa.
func _on_view_resized() -> void:
	var size := get_viewport_rect().size
	if size == view_size:
		return
	var fitted := not is_zoomed_in()
	view_size = size
	fit_zoom = minf(view_size.x / sim.size.x, view_size.y / sim.size.y)
	if fitted:
		reset_camera()
	else:
		camera.zoom = Vector2.ONE * maxf(camera.zoom.x, fit_zoom)
		clamp_camera()
	hud.rebuild_ui.call_deferred()


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
		perf_sample("sim", t0)
		perf["steps"] = steps
		render_alpha = clampf(accum / STEP, 0.0, 1.0)
		t0 = Time.get_ticks_usec()
		_consume_events()
		if sim.result != 0:
			_on_game_end()
		controls.key_pan(delta)
		_update_tutorial(delta)
		perf_sample("events", t0)
	if state == State.PLAY or state == State.OVER:
		_update_effects(delta)
	if state == State.OVER and over_delay > 0:
		over_delay -= delta
	var t_hud := Time.get_ticks_usec()
	hud.update_hud()
	view.update_lane_fx()
	perf_sample("hud", t_hud)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	queue_redraw()
	hud.fx_canvas.queue_redraw()
	if hud.minimap.visible:
		hud.minimap.queue_redraw()


func perf_sample(key: String, t0: int) -> void:
	perf[key] = lerpf(perf[key], (Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _on_game_end() -> void:
	state = State.OVER
	over_delay = OVER_DELAY
	mode = ""
	selected = null
	hero_selected = false
	controls.dragging = false
	controls.press_button = -1
	tutorial_step = -1
	var won := sim.result == 1
	var map_id: String = sim.level["id"]
	var survival := sim.mode == "survival"
	if not daily.is_empty():  # modyfikatory zmieniają grę — tylko rekord dnia, zwykłe zostają
		new_record = (survival or won) and Progress.record_daily(daily["date"], sim.mode, sim.wave if survival else sim.elapsed)
	elif survival:
		new_record = Progress.record_survival(map_id, difficulty, sim.players[me].commander, sim.wave)
	else:
		new_record = won and Progress.record_win(map_id, difficulty, sim.elapsed)
	var loser_base := sim.base_pos(1 if won else 0)
	for i in 5:
		burst(loser_base + Vector2(randf_range(-40, 40), randf_range(-30, 30)), 18, Color(1, 0.6, 0.2), 200.0)
	ring(loser_base, 120.0, Color(1, 0.8, 0.4))
	shake = 16.0
	sfx.play("explosion", 0.0)
	sfx.play("win" if won else "lose", 0.0)
	hud.over_title.text = "WYGRANA!" if won else "PRZEGRANA"
	hud.over_title.add_theme_color_override("font_color", GOLD_COLOR if won else TEAM_COLORS[1])
	if survival:
		hud.over_title.text = "PRZETRWAŁEŚ %d FAL" % sim.wave
		hud.over_title.add_theme_color_override("font_color", GOLD_COLOR if new_record else Color.WHITE)
	var s := sim.stats
	var lines := PackedStringArray([
		"%s%s · przeciwnik: %s · %s · %s · czas %s · fala %d" % [Races.ALL[race_index]["name"],
			" (%s)" % Cfg.COMMANDERS[commander_id]["name"] if commander_id != "" else "", Races.ALL[rival_index]["name"], sim.level["name"], sim.difficulty["name"], hud.fmt_time(sim.elapsed), sim.wave],
		"Zabici wrogowie: %d · wyprodukowane jednostki: %d · umiejętności: %d" % [s["kills"], s["units_made"], s["abilities_used"]],
		"Zburzone wieże: %d · stracone budynki: %d · zarobione złoto: %d" % [s["towers_razed"], s["buildings_lost"], int(s["gold_earned"])],
	])
	if not daily.is_empty():
		var best := Progress.best_daily(daily["date"])
		var best_text := "—" if best < 0 else ("%d fal" % best if survival else hud.fmt_time(best))
		lines.append("Wyzwanie dnia %s · %s" % [daily["date"], "NOWY REKORD DNIA!" if new_record else "rekord dnia: " + best_text])
	elif survival:
		lines.append("Nowy rekord przetrwania!" if new_record else "Rekord: %d fal" % Progress.best_survival(map_id, difficulty, sim.players[me].commander))
	elif new_record:
		lines.append("Nowy rekord!  Gwiazdki mapy: %s" % hud.stars_text(Progress.stars(map_id)))
	hud.over_stats.text = "\n".join(lines)


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
					burst(pos, 3, Color(1, 0.9, 0.6), 60.0, 0.25)
				sfx.play("hit", 0.06)
			"death":
				if deaths_left > 0 or e["kind"] == "warlord":
					deaths_left -= 1
					burst(pos, 10, TEAM_COLORS[e["team"]], 110.0)
				sfx.play("death", 0.05)
				if e["kind"] == "warlord":
					shake = maxf(shake, 12.0)
					banner("Wódz pokonany!", "")
			"gold":
				if texts.size() < GOLD_TEXTS_MAX:
					float_text(pos, "+%d" % e["amount"], GOLD_COLOR)
				sfx.play("coin", 0.08)
			"explosion":
				burst(pos, 14, Color(1, 0.62, 0.2), 150.0, 0.45)
				ring(pos, e["radius"], Color(1, 0.8, 0.4))
				sfx.play("explosion", 0.1)
			"frost":
				burst(pos, 10, FROST_COLOR, 90.0, 0.5)
				ring(pos, e["radius"], FROST_COLOR)
			"volley":
				_arrow_rain(pos, e["radius"])
				sfx.play("volley", 0.1)
			"ability":
				match e["name"]:
					"arrows":
						ring(pos, Cfg.ABILITIES["arrows"]["radius"], Color.WHITE)
					"levy":
						var tc := TEAM_COLORS[e.get("team", 0)]
						burst(pos, 20, tc, 140.0, 0.6)
						float_text(pos + Vector2(0, -20), "Pobór!", tc.lightened(0.3))
						sfx.play("levy", 0.0)
					"repair":
						for b in sim.buildings:
							if b.team == 0 and b.kind != "basegun":
								burst(b.pos, 6, HEAL_COLOR, 60.0, 0.6)
						burst(sim.p_base, 20, HEAL_COLOR, 90.0, 0.8)
						float_text(sim.p_base + Vector2(0, -60), "Naprawa!", HEAL_COLOR)
						sfx.play("repair", 0.0)
			"base_hit":
				base_flash[e["team"]] = 0.15
				if e["team"] == 0:
					shake = maxf(shake, 4.0)
					sfx.play("base_hit", 0.3)
			"wave":
				var where := sim.lane_names(e["lanes"])
				if e["boss"]:
					banner("Fala %d — %s" % [e["n"], where], "Nadciąga WÓDZ! (%d wrogów)" % e["count"])
					shake = maxf(shake, 8.0)
					sfx.play("boss", 0.0)
				elif e.get("fury", false):
					banner("Fala %d — %s" % [e["n"], where], "Wróg wpada w furię — od teraz każda fala silniejsza!")
					shake = maxf(shake, 6.0)
					sfx.play("boss", 0.0)
				else:
					banner("Fala %d — %s" % [e["n"], where], "%d wrogów" % e["count"])
					sfx.play("wave", 0.0)
			"enemy_build":
				float_text(pos, "Wróg stawia wieżę!", TEAM_COLORS[1])
				burst(pos, 12, Color(0.7, 0.6, 0.5), 80.0)
				sfx.play("build", 0.0)
			"build":
				burst(pos, 12, Color(0.75, 0.65, 0.5), 90.0)
				sfx.play("build", 0.0)
			"upgrade":
				burst(pos, 16, GOLD_COLOR, 120.0)
				ring(pos, 40.0, GOLD_COLOR)
				sfx.play("upgrade", 0.0)
			"sell":
				float_text(pos, "+%d" % e["amount"], GOLD_COLOR)
				burst(pos, 10, Color(0.7, 0.7, 0.7), 80.0)
				sfx.play("sell", 0.0)
			"building_hit":
				if time - hit_notice.get(e["id"], -INF) > HIT_NOTICE_GAP:
					hit_notice[e["id"]] = time
					float_text(pos + Vector2(0, -28), "Atak!", WARN_COLOR)
					sfx.play("alarm", 1.0)
			"building_destroyed":
				burst(pos, 24, Color(1, 0.55, 0.2), 180.0, 0.7)
				ring(pos, 60.0, Color(1, 0.7, 0.3))
				shake = maxf(shake, 7.0)
				sfx.play("explosion", 0.0)
				if e["team"] == 1:
					float_text(pos + Vector2(0, -24), "Wieża zburzona!", Color.WHITE)
				else:
					float_text(pos + Vector2(0, -24), "Zniszczono: %s" % Cfg.building(e["kind"])["name"], WARN_COLOR)
			"hero_level":
				if e["team"] == 0:
					banner("Awans dowódcy — poziom %d!" % e["level"], "Silniejszy dowódca · wybierz ulepszenie umiejętności (z lewej)")
					burst(pos, 30, HERO_COLOR, 160.0, 0.8)
					ring(pos, 70.0, HERO_COLOR)
					sfx.play("win", 0.0)
			"hero_upgrade":
				if e["team"] == 0:
					float_text(pos + Vector2(0, -34), e["label"], HERO_COLOR)
			"hero_order":
				if e["team"] == 0:
					ring(pos, 18.0, HERO_COLOR)
			"hero_died":
				burst(pos, 26, HERO_COLOR, 150.0, 0.8)
				if e["team"] == 0:
					banner("Dowódca poległ!", "Wróci do bazy za %d s — umiejętności dowódcy czekają" % ceili(e["respawn"]))
					hero_selected = false
					sfx.play("lose", 0.0)
				else:
					banner("Dowódca wroga poległ!", "+%d zł · wróci za %d s" % [Cfg.COMMANDER_KILL_BOUNTY, ceili(e["respawn"])])
					float_text(pos + Vector2(0, -30), "+%d" % Cfg.COMMANDER_KILL_BOUNTY, GOLD_COLOR)
					sfx.play("win", 0.0)
			"hero_respawn":
				if e["team"] == 0:
					burst(pos, 18, HERO_COLOR, 110.0, 0.6)
					float_text(pos + Vector2(0, -30), "Dowódca wraca!", HERO_COLOR)
					sfx.play("levy", 0.0)
			"summon":
				burst(pos, 14, TEAM_COLORS[e["team"]].lightened(0.3), 100.0, 0.5)
				sfx.play("build", 0.0)
			"summon_expired":
				burst(pos, 10, Color(0.7, 0.7, 0.7), 70.0, 0.5)
			"heal":
				var tc := HEAL_COLOR if e["team"] == 0 else TEAM_COLORS[1].lightened(0.3)
				if e["radius"] > 0.0:
					ring(pos, e["radius"], tc)
					burst(pos, 16, tc, 90.0, 0.7)
				else:  # cała armia — iskry przy każdej jednostce byłyby za drogie, jeden napis przy bazie
					var at := sim.base_pos(e["team"]) + Vector2(0, -60)
					burst(at, 20, tc, 90.0, 0.8)
					float_text(at, "Przypływ! (%d)" % e["count"], tc)
				sfx.play("repair", 0.0)
			"pulse":
				ring(pos, e["radius"], HEAL_COLOR if e["team"] == 0 else TEAM_COLORS[1])
			"buff":
				ring(pos, 60.0, GOLD_COLOR)
				burst(pos, 12, GOLD_COLOR, 90.0, 0.6)
			"line":
				var a: Vector2 = e["from"]
				var b: Vector2 = e["to"]
				for i in 8:
					burst(a.lerp(b, (i + 0.5) / 8.0), 2, Color(1, 0.95, 0.8), 50.0, 0.35)
				sfx.play("volley", 0.0)
			"burrow":
				var lane: Sim.Lane = sim.lanes[e["lane"]]
				for i in 6:
					burst(lane.point_at(lane.offset_of(pos) + (i - 2.5) * 40.0), 4, Color(0.5, 0.38, 0.24), 70.0, 0.5)
				if e["team"] == 0:
					float_text(pos + Vector2(0, -24), "Podkop! (%d)" % e["count"], Color(0.85, 0.7, 0.5))
				sfx.play("build", 0.0)
			"weaken":
				ring(pos, e["radius"], CURSE_COLOR)
				burst(pos, 14, CURSE_COLOR, 90.0, 0.6)
				sfx.play("frost", 0.1)
			"leap":
				burst(e["from"], 8, Color(0.7, 0.6, 0.45), 60.0, 0.4)
				burst(pos, 18, Color(0.8, 0.65, 0.45), 140.0, 0.5)
				ring(pos, e["radius"], HERO_COLOR)
				shake = maxf(shake, 4.0)
				sfx.play("explosion", 0.1)
			"raise_zone":
				ring(pos, e["radius"], CURSE_COLOR)
				sfx.play("boss", 0.0)
			"raised":
				burst(pos, 10, CURSE_COLOR, 80.0, 0.6)
				sfx.play("levy", 0.15)
			"pull":
				var a: Vector2 = e["from"]
				var b: Vector2 = e["to"]
				for i in 6:
					burst(a.lerp(b, (i + 0.5) / 6.0), 2, HERO_COLOR, 40.0, 0.4)
				sfx.play("hit", 0.0)
			"taunt":
				ring(pos, e["radius"], WARN_COLOR)
				float_text(pos + Vector2(0, -34), "Do mnie!", WARN_COLOR)
				sfx.play("boss", 0.0)
			"quake":
				burst(pos, 8, Color(0.55, 0.42, 0.28), 110.0, 0.5)
				ring(pos, e["radius"], Color(0.8, 0.65, 0.45))
				sfx.play("explosion", 0.15)
			"execute":
				burst(pos, 16, WARN_COLOR, 130.0, 0.5)
				ring(pos, 30.0, WARN_COLOR)
				sfx.play("hit", 0.0)
	sim.events.clear()


func burst(at: Vector2, n: int, color: Color, speed := 100.0, life := 0.5) -> void:
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


func ring(at: Vector2, radius: float, color: Color) -> void:
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


func float_text(at: Vector2, text: String, color: Color) -> void:
	if texts.size() >= MAX_TEXTS:
		texts.pop_front()  # ważne komunikaty wypierają najstarsze
	var f := FloatText.new()
	f.pos = at + Vector2(randf_range(-6, 6), -10)
	f.text = text
	f.life = 1.2
	f.color = color
	texts.append(f)


func banner(text: String, sub: String) -> void:
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
		"hero":
			done = hero_ordered or sim.hero(me) == null
		"ability":
			done = sim.stats["abilities_used"] > 0
		"timer":
			done = tutorial_timer > 6.0
	if not done:
		return
	tutorial_step += 1
	tutorial_timer = 0.0
	if tutorial_step >= TUTORIAL.size():
		finish_tutorial()
	else:
		sfx.play("coin", 0.0)


func finish_tutorial() -> void:
	tutorial_step = -1
	Progress.set_tutorial_done(true)


func reset_tutorial() -> void:
	Progress.set_tutorial_done(false)
	if state == State.PAUSED:
		tutorial_step = 0  # w trwającej grze rusza od razu po wznowieniu
		tutorial_timer = 0.0
	banner("Samouczek włączony", "")


func _has_building(pred: Callable) -> bool:
	for b in sim.buildings:
		if b.team == 0 and pred.call(b):
			return true
	return false


# ================================================================ kamera

## Ekran (piksele wirtualne, `view_size`) → świat. Liczone wprost z kamery, bez czekania na klatkę.
func to_world(screen_pos: Vector2) -> Vector2:
	return camera.position + (screen_pos - view_size / 2.0) / camera.zoom.x


func to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - camera.position) * camera.zoom.x + view_size / 2.0


func reset_camera() -> void:
	fit_zoom = minf(view_size.x / sim.size.x, view_size.y / sim.size.y)
	camera.zoom = Vector2.ONE * fit_zoom
	camera.position = sim.size / 2.0


func is_zoomed_in() -> bool:
	return camera.zoom.x > fit_zoom * 1.02


## Przybliża/oddala tak, żeby punkt świata pod `screen_pt` został pod palcem/kursorem.
func zoom_at(screen_pt: Vector2, factor: float) -> void:
	var anchor := to_world(screen_pt)
	var z := clampf(camera.zoom.x * factor, fit_zoom, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.position = anchor - (screen_pt - view_size / 2.0) / z
	clamp_camera()
	camera_used = true


## Przesuwa widok tak, jakby przeciągać mapę o `delta_screen` pikseli ekranu.
func pan_screen(delta_screen: Vector2) -> void:
	camera.position -= delta_screen / camera.zoom.x
	clamp_camera()
	camera_used = true


func clamp_camera() -> void:
	var half := view_size / camera.zoom.x / 2.0
	var p := camera.position
	p.x = sim.size.x / 2.0 if half.x * 2.0 >= sim.size.x else clampf(p.x, half.x, sim.size.x - half.x)
	p.y = sim.size.y / 2.0 if half.y * 2.0 >= sim.size.y else clampf(p.y, half.y, sim.size.y - half.y)
	camera.position = p


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		controls.on_key(event.keycode)
		return
	if state != State.PLAY or overlay != "":
		return
	if event is InputEventScreenTouch:
		controls.on_touch(event)
	elif event is InputEventScreenDrag:
		controls.on_touch_drag(event)
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		pan_screen(-event.delta * 12.0)
	elif controls.gesture:
		return  # w trakcie gestu dwoma palcami ignoruj emulowaną mysz
	elif event is InputEventMouseButton:
		controls.on_mouse_button(event)
	elif event is InputEventMouseMotion:
		controls.on_mouse_motion(event)


func open_overlay(which: String) -> void:
	overlay = which
	if which == "settings":
		hud.sfx_slider.set_value_no_signal(Settings.sfx_volume)
		hud.music_slider.set_value_no_signal(Settings.music_volume)


func close_overlay() -> void:
	if overlay == "settings":
		Settings.save_all()
	overlay = ""


func toggle_perf() -> void:
	Settings.show_perf = not Settings.show_perf
	Settings.save_all()


func cycle_ui_scale() -> void:
	Settings.ui_scale_index = (Settings.ui_scale_index + 1) % Settings.UI_SCALES.size()
	Settings.save_all()
	hud.rebuild_ui.call_deferred()  # nie usuwaj przycisku w trakcie obsługi jego sygnału


## Świat rysuje WorldView na płótnie main (jedno wywołanie rysowania — patrz Painter).
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	view.draw()
	perf_sample("draw", t0)
