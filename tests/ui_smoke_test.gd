extends SceneTree
## Smoke test widoku: odpala prawdziwą scenę i steruje nią prawdziwymi zdarzeniami
## wejścia (klik, przeciąganie, kółko, klawisze): wybór mapy, samouczek, budowa,
## zaznaczanie, ścieżka produkcji, umiejętności, kamera, minimapa, ustawienia (skala UI),
## pauza — po czym gra na x3 aż do końca partii albo limitu klatek. Łapie błędy
## skryptu w renderze/HUD/inpucie, których testy Sim nie widzą.
##
##   godot --headless --path . --fixed-fps 60 --script res://tests/ui_smoke_test.gd
##
## Szukaj w wyjściu „SCRIPT ERROR" — test sam nie przechwyci błędów silnika.
## Zdarzenia idą przez root.push_input(e, true): okno headless ma 64×64, a `true`
## mówi, że pozycje są już w wirtualnych 1280×720.
## Ostrzeżenie „ObjectDB instances were leaked" przy wyjściu jest niegroźne: to
## playbacki AudioStreamWAV, których sterownik audio „dummy" (headless) nie zwalnia.

const MAX_FRAMES := 60 * 150  # 2,5 min klatek = 7,5 min gry na x3

var main: Node
var frame := 0
var failures := 0
var cell := Vector2.INF
var cam_before := Vector2.ZERO


func _initialize() -> void:
	# osobne pliki zapisu, żeby test nie ruszał postępu i ustawień gracza
	Progress.path = "user://test_progress.cfg"
	Settings.path = "user://test_settings.cfg"
	for p in [Progress.path, Settings.path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progress.reset_cache()
	main = load("res://main.tscn").instantiate()
	if not main.has_method("_start"):
		print("BŁĄD: skrypt sceny się nie załadował (błąd parsowania?)")
		quit(1)
		return
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var sim: Sim = main.sim
	match frame:
		2:
			_check(main.state == main.State.MENU, "start w menu")
			_check(main.menu_layer.visible, "menu widoczne")
			var playable: Array = main.race_buttons.filter(func(b: Button) -> bool: return not b.disabled)
			_check(main.race_buttons.size() == 12 and playable.size() == 2, "12 ras w menu, grywalne dwie")
			main.race_buttons[0].emit_signal("pressed")  # niedźwiedzie — „Wkrótce"
			_check(Races.ALL[main.race_index]["id"] == "mole", "zablokowanej rasy nie da się wybrać")
			main.race_buttons[Races.ALL.find_custom(func(r: Dictionary) -> bool: return r["id"] == "gibbon")].emit_signal("pressed")
			main.map_buttons[2].emit_signal("pressed")
		3:
			_check(Races.ALL[main.race_index]["id"] == "gibbon", "wybór rasy w menu")
			_check(main.race_desc.text.contains("Przeciwnik: Krety"), "menu pokazuje przeciwnika")
			_check(main.level_index == 2 and sim.level["id"] == "serpentyna", "wybór mapy w menu")
			main.diff_buttons[1].emit_signal("pressed")
		4:
			_check(main.state == main.State.PLAY and sim.difficulty["name"] == "Normalny", "trudność startuje grę")
			_check(main.tutorial_step == 0 and main.tutorial_panel.visible, "samouczek przy pierwszej grze")
			main.speed_mult = 3
			sim.gold = 5000
			_click(main._to_screen(sim.nodes[1]))
		6:
			_check(sim.extractor_on(1) != null, "klik w złoże stawia wydobywacz")
			_check(main.tutorial_step == 1, "samouczek: krok za wydobywacz zaliczony")
			main.build_buttons["barracks"].emit_signal("pressed")
			cell = sim.free_cell_near(Vector2(170, 330))
			_click(main._to_screen(cell))
		8:
			_check(sim.building_at(cell, 0) != null, "klik w trybie budowy stawia koszary")
			_check(main.tutorial_step == 2, "samouczek: krok za produkcję zaliczony")
			_click(main._to_screen(cell))
		10:
			_check(main.selected != null and main.selected.kind == "barracks", "klik w budynek go zaznacza")
			_check(main.sel_panel.visible and main.lane_row.visible, "panel pokazuje wybór ścieżki")
			main.lane_buttons[2].emit_signal("pressed")
		12:
			_check(main.selected.lane == 2, "przycisk ścieżki kieruje produkcję")
			main.tutorial_panel.get_child(0).get_child(1).emit_signal("pressed")  # „Pomiń"
			for i in 4:
				_wheel(Vector2(640, 360), MOUSE_BUTTON_WHEEL_UP)
		14:
			_check(main.tutorial_step == -1 and Progress.tutorial_done(), "Pomiń kończy samouczek na stałe")
			_check(main._is_zoomed_in() and main.minimap.visible, "kółko przybliża, minimapa widoczna")
			cam_before = main.camera.position
			var sel_before: Object = main.selected
			_drag(Vector2(640, 400), Vector2(480, 330))
			_check(main.selected == sel_before, "przeciąganie nie jest klikiem")
		16:
			_check(main.camera.position.x > cam_before.x, "przeciąganie przesuwa mapę")
			var mm: Control = main.minimap
			_click((mm.global_position + mm.size * Vector2(0.1, 0.5)) * Settings.ui_scale())
		18:
			_check(main.camera.position.x < cam_before.x, "klik w minimapę przenosi kamerę")
			_key(KEY_C)
			_key(KEY_Q)
		20:
			_check(not main._is_zoomed_in(), "C wraca do widoku całej mapy")
			_check(main.mode == "ab:arrows", "Q wybiera Deszcz strzał")
			_click(main._to_screen(sim.lanes[1].point_at(900)))
		22:
			_check(sim.ability_cd["arrows"] > 0 and main.mode == "", "klik na mapie rzuca Deszcz strzał")
			_key(KEY_R)
			main.ability_buttons["levy"].emit_signal("pressed")
		24:
			_check(sim.ability_cd["repair"] > 0, "R rzuca Naprawę od razu")
			_check(main.mode == "ab:levy", "przycisk wybiera Pobór")
			var before := sim.army_size(0)
			_click(main._to_screen(sim.lanes[1].point_at(350)))
			_check(sim.army_size(0) > before, "Pobór wystawia posiłki przy ścieżce")
			_key(KEY_3)
			cell = sim.free_cell_near(sim.lanes[1].slot_at(420, 70))
			_click(main._to_screen(cell))
		26:
			_check(sim.building_at(cell, 0) != null and sim.building_at(cell, 0).kind == "frost", "3 stawia wieżę mrozu")
			_click(main._to_screen(cell))
		28:
			main._sell_selected()
			_check(sim.building_at(cell, 0) == null, "sprzedaż z panelu")
			_key(KEY_P)
		30:
			_check(main.state == main.State.PAUSED and main.pause_layer.visible, "P pauzuje")
			main._open_overlay("settings")
		31:
			_check(main.settings_layer.visible and not main.pause_layer.visible, "ustawienia nad pauzą")
			main.music_slider.value = 0.2
			main._cycle_ui_scale()
		33:
			_check(Settings.ui_scale_index == 1 and main.screen.x < main.view_size.x, "większy interfejs przebudowuje HUD")
			_check(main.settings_layer.visible, "po przebudowie ustawienia zostają otwarte")
			_key(KEY_ESCAPE)
		35:
			_check(not main.settings_layer.visible and main.pause_layer.visible, "Esc zamyka ustawienia")
			var saved := ConfigFile.new()
			_check(saved.load(Settings.path) == OK and is_equal_approx(saved.get_value("audio", "music"), 0.2), "ustawienia zapisane")
			_key(KEY_P)
		37:
			_check(main.state == main.State.PLAY, "P wznawia")
			_key(KEY_SPACE)
			main._cancel()
			main.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		38:
			_check(main.state == main.State.PAUSED, "Wstecz (Android) pauzuje")
			main.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			# okno headless jest kwadratowe, więc „expand" daje widok 1280×1280 — przejście na
			# „keep" (1280×720) sprawdza, że zmiana proporcji ekranu przelicza widok i HUD
			_check(main.view_size == root.get_visible_rect().size, "widok = widoczny obszar okna")
			root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		40:
			_check(main.state == main.State.PLAY, "drugie Wstecz wznawia")
			_check(main.view_size == Cfg.VIEW and is_equal_approx(main.screen.y, Cfg.VIEW.y / Settings.ui_scale()),
				"zmiana proporcji ekranu przebudowuje HUD")
			_check(not main._is_zoomed_in(), "po zmianie proporcji kamera dalej pokazuje całą mapę")
		1200:
			# dokładamy gospodarkę i armię, żeby dojść do końca partii
			sim.gold += 8000
			for kind in ["range", "workshop", "tower", "cannon", "barracks", "workshop", "frost", "barracks"]:
				var c := sim.free_cell_near(Vector2(250, 450), 400)
				if sim.build(kind, c) and Cfg.is_production(kind):
					sim.set_lane(sim.building_at(c, 0), 1)
			for i in sim.nodes.size():
				sim.build_extractor(i)
	if main.state == main.State.OVER and main.over_layer.visible:
		var won: bool = sim.result == 1
		print("koniec partii: %s po %d s gry, fala %d" % ["wygrana" if won else "przegrana", sim.elapsed, sim.wave])
		if won:
			_check(Progress.best("serpentyna", 1) > 0, "wygrana zapisuje rekord")
			_check(main.over_stats.text.contains("Nowy rekord"), "ekran końca ogłasza rekord")
		return _finish()
	if frame >= MAX_FRAMES:
		print("limit klatek: %d s gry, fala %d, wynik %d" % [sim.elapsed, sim.wave, sim.result])
		return _finish()
	return false


# ---------------------------------------------------------------- zdarzenia wejścia

func _click(at: Vector2) -> void:
	_button(at, MOUSE_BUTTON_LEFT, true)
	_button(at, MOUSE_BUTTON_LEFT, false)


func _wheel(at: Vector2, button: MouseButton) -> void:
	_button(at, button, true)
	_button(at, button, false)


func _drag(from: Vector2, to: Vector2) -> void:
	_button(from, MOUSE_BUTTON_LEFT, true)
	var steps := 5
	for i in steps:
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, float(i + 1) / steps)
		m.global_position = m.position
		m.relative = (to - from) / steps
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m, true)
	_button(to, MOUSE_BUTTON_LEFT, false)


func _button(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = button
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	root.push_input(e, true)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = key
		e.physical_keycode = key
		e.pressed = pressed
		root.push_input(e, true)


func _finish() -> bool:
	for p in [Progress.path, Settings.path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("OK" if failures == 0 else "BŁĘDY: %d" % failures)
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)
		print("  FAIL: ", what)
