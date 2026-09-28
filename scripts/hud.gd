class_name Hud
extends RefCounted
## HUD, menu i nakładki (pauza, koniec, ustawienia, pomoc) — Control budowany w kodzie.
## Stan gry czyta z `m` (main.gd), przyciski wołają akcje main i `m.controls`.
## Całość budowana od nowa przy zmianie rozmiaru interfejsu (`rebuild_ui`).

const ABILITY_KEY_NAMES: Array[String] = ["Q", "E", "R", "T"]

var mode_button: Button
var daily_label: Label  ## indeks rasy → ostatnio wybrany dowódca (w obrębie sesji)
var ui_layer: CanvasLayer
var screen := Cfg.VIEW  ## rozmiar HUD w jego własnych jednostkach (ekran / skala UI)
var game_ui: Control
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
var ability_slots: Array[Button] = []  ## pola paska umiejętności (Q/E/R/T)
var ability_buttons := {}  ## umiejętność → jej pole na pasku (odświeżane z `sim.ability_order`)
var portrait_button: Button
var upgrade_panel: PanelContainer  ## oferta awansu dowódcy (T14): 2 ulepszenia do wyboru
var upgrade_title: Label
var upgrade_buttons: Array[Button] = []
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
var commander_row: HBoxContainer
var commander_buttons := {}  ## id dowódcy → karta w menu
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

var m: Main


func _init(main: Main) -> void:
	m = main


func build_ui() -> void:
	var s := Settings.ui_scale()
	screen = m.view_size / s
	ui_layer = CanvasLayer.new()
	ui_layer.scale = Vector2(s, s)
	m.add_child(ui_layer)
	var ui := Control.new()
	ui.size = screen
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = make_theme()
	ui_layer.add_child(ui)
	game_ui = Control.new()  # wszystko poza nakładkami — chowane w menu
	game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(game_ui)

	# baner fal i komunikatów — w przestrzeni ekranu, niezależny od kamery
	fx_canvas = Control.new()
	fx_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_canvas.draw.connect(draw_banner)
	game_ui.add_child(fx_canvas)

	# lewy górny róg: ekonomia i fale
	var info := VBoxContainer.new()
	info.position = Vector2(16, 8)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 0)
	game_ui.add_child(info)
	gold_label = label("", 30, info, Main.GOLD_COLOR)
	income_label = label("", 16, info)
	wave_label = label("", 16, info)
	daily_label = label("", 14, info, Main.GOLD_COLOR)
	perf_label = label("", 13, info, Color(0.7, 1.0, 0.7))

	# prawy górny róg: sterowanie grą
	var top := HBoxContainer.new()
	top.position = Vector2(screen.x - 16 - 526, 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	game_ui.add_child(top)
	stance_button = button("", Vector2(180, 52), m.controls.toggle_stance, top)
	speed_button = button("", Vector2(64, 52), m.controls.cycle_speed, top)
	mute_button = button("", Vector2(110, 52), m.controls.toggle_mute, top)
	button("Mapa", Vector2(84, 52), m.reset_camera, top)
	button("II", Vector2(56, 52), func() -> void: m.set_paused(true), top)

	# samouczek — pod górnym paskiem, na środku
	tutorial_panel = PanelContainer.new()
	tutorial_panel.custom_minimum_size = Vector2(520, 0)
	tutorial_panel.position = Vector2((screen.x - 520) / 2.0, 72)
	game_ui.add_child(tutorial_panel)
	var tut_box := HBoxContainer.new()
	tut_box.add_theme_constant_override("separation", 10)
	tutorial_panel.add_child(tut_box)
	tutorial_label = label("", 16, tut_box, Color(1, 0.95, 0.8))
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.custom_minimum_size = Vector2(390, 0)
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button("Pomiń", Vector2(90, 40), m.finish_tutorial, tut_box)

	# minimapa pod przyciskami — widoczna po przybliżeniu
	minimap = Control.new()
	minimap.position = Vector2(screen.x - 16 - 240, 76)
	minimap.size = Vector2(240, 240 * m.sim.size.y / m.sim.size.x)
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.draw.connect(draw_minimap)
	minimap.gui_input.connect(on_minimap_input)
	game_ui.add_child(minimap)

	# dół: budowa (6) i umiejętności (3 dowódcy + rasowa) — szerokość przycisków dopasowana do ekranu
	var w := minf(120.0, floorf((screen.x - 32 - 68) / 10.0))
	var bar := HBoxContainer.new()
	bar.position = Vector2(16, screen.y - 72)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	game_ui.add_child(bar)
	for key in Cfg.BUILD_ORDER:
		var b := button("", Vector2(w, 60), m.controls.select_mode.bind(key), bar)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 15)
		build_buttons[key] = b
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	for i in Controls.ABILITY_KEYS.size():
		var b := button("", Vector2(w, 60), m.controls.select_ability_slot.bind(i), bar)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 14)
		b.self_modulate = Color(0.85, 0.95, 1.0) if i < 3 else Color(1.0, 0.9, 0.75)
		ability_slots.append(b)

	# lewy dół, nad paskiem: portret dowódcy — wybiera go i centruje kamerę (R6)
	portrait_button = button("", Vector2(190, 56), m.controls.pick_hero.bind(true), game_ui)
	portrait_button.toggle_mode = true
	portrait_button.add_theme_font_size_override("font_size", 15)
	portrait_button.add_theme_color_override("font_color", Main.HERO_COLOR)
	portrait_button.add_theme_color_override("font_pressed_color", Main.HERO_COLOR)
	portrait_button.position = Vector2(16, screen.y - 72 - 64)

	# nad portretem: oferta awansu — gra się nie zatrzymuje, oferta czeka na wybór
	upgrade_panel = PanelContainer.new()
	game_ui.add_child(upgrade_panel)
	var up_box := VBoxContainer.new()
	up_box.add_theme_constant_override("separation", 6)
	upgrade_panel.add_child(up_box)
	upgrade_title = label("", 16, up_box, Main.HERO_COLOR)
	for i in 2:
		var ub := button("", Vector2(260, 46), m.controls.choose_upgrade.bind(i), up_box)
		ub.add_theme_font_size_override("font_size", 15)
		upgrade_buttons.append(ub)

	# prawy dół (nad paskiem): panel zaznaczonego budynku
	sel_panel = PanelContainer.new()
	sel_panel.custom_minimum_size = Vector2(320, 0)
	game_ui.add_child(sel_panel)
	var sel_box := VBoxContainer.new()
	sel_panel.add_child(sel_box)
	sel_title = label("", 20, sel_box)
	sel_body = label("", 14, sel_box, Color(1, 1, 1, 0.85))
	lane_row = HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 6)
	sel_box.add_child(lane_row)
	for i in m.sim.lanes.size():
		var lb := button(m.sim.lanes[i].name, Vector2(98, 42), m.controls.set_selected_lane.bind(i), lane_row)
		lb.toggle_mode = true
		lb.add_theme_color_override("font_pressed_color", Main.LANE_COLORS[i])
		lb.add_theme_color_override("font_hover_pressed_color", Main.LANE_COLORS[i])
		lane_buttons.append(lb)
	var sel_buttons := HBoxContainer.new()
	sel_buttons.add_theme_constant_override("separation", 8)
	sel_box.add_child(sel_buttons)
	upgrade_button = button("", Vector2(150, 48), m.controls.upgrade_selected, sel_buttons)
	sell_button = button("", Vector2(150, 48), m.controls.sell_selected, sel_buttons)

	build_menu(ui)
	build_pause(ui)
	build_over(ui)
	build_settings(ui)
	build_help(ui)


func build_menu(ui: Control) -> void:
	menu_layer = overlay(ui, 0.55)
	var box: VBoxContainer = menu_layer.get_child(0).get_child(0)
	label("TOWER DEFENSE", 52, box, Main.GOLD_COLOR)
	label("Rozbuduj ekonomię. Wyślij armię. Zburz fortecę wroga.", 18, box)
	# rasy: wszystkie z Races.ALL, grywalne z ramką w kolorze rasy, reszta „Wkrótce"
	var races := GridContainer.new()
	races.columns = 6
	races.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	races.add_theme_constant_override("h_separation", 8)
	races.add_theme_constant_override("v_separation", 8)
	box.add_child(races)
	for i in Races.ALL.size():
		var r: Dictionary = Races.ALL[i]
		var b := button(r["name"] if r["playable"] else "%s\nWkrótce" % r["name"], Vector2(140, 50), m.select_race.bind(i), races)
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
	race_desc = label("", 15, box, Color(1, 1, 1, 0.8))
	# dowódcy wybranej rasy — karty budowane od nowa przy zmianie rasy
	commander_row = HBoxContainer.new()
	commander_row.alignment = BoxContainer.ALIGNMENT_CENTER
	commander_row.add_theme_constant_override("separation", 10)
	box.add_child(commander_row)
	fill_commander_row()
	var maps := HBoxContainer.new()
	maps.alignment = BoxContainer.ALIGNMENT_CENTER
	maps.add_theme_constant_override("separation", 10)
	box.add_child(maps)
	for i in Levels.ALL.size():
		var b := button("", Vector2(230, 62), m.select_level.bind(i), maps)
		b.toggle_mode = true
		map_buttons.append(b)
	map_desc = label("", 15, box, Color(1, 1, 1, 0.8))
	var diffs := HBoxContainer.new()
	diffs.alignment = BoxContainer.ALIGNMENT_CENTER
	diffs.add_theme_constant_override("separation", 10)
	box.add_child(diffs)
	for d in Cfg.DIFFICULTIES.size():
		diff_buttons.append(button("", Vector2(210, 62), m.start.bind(d), diffs))
	var extra := HBoxContainer.new()
	extra.alignment = BoxContainer.ALIGNMENT_CENTER
	extra.add_theme_constant_override("separation", 10)
	box.add_child(extra)
	mode_button = button("", Vector2(250, 46), m.toggle_mode, extra)
	var daily_button := button("Wyzwanie dnia", Vector2(200, 46), m.start_daily, extra)
	daily_button.add_theme_color_override("font_color", Main.GOLD_COLOR)
	button("Jak grać", Vector2(160, 46), m.open_overlay.bind("help"), extra)
	button("Ustawienia", Vector2(160, 46), m.open_overlay.bind("settings"), extra)


## Karty dowódców rasy: nazwa, rola, umiejętności (Q/E/R); niegotowi — „Wkrótce”.
func fill_commander_row() -> void:
	if commander_row == null:
		return
	for child in commander_row.get_children():
		child.queue_free()
	commander_buttons.clear()
	if m.commander_id == "":
		m.commander_id = m.default_commander(m.race_index)
	var ids := Races.commanders(m.race_index)
	# karty mieszczą się w szerokości ekranu (4 karty przy dużym interfejsie na 16:9)
	var w := minf(290.0, floorf((screen.x - 40.0 - 10.0 * (ids.size() - 1)) / ids.size()))
	for id in ids:
		var c: Dictionary = Cfg.COMMANDERS[id]
		var ready := Cfg.commander_ready(id)
		var names := PackedStringArray()
		for a in c["abilities"]:
			names.append(Cfg.ABILITIES[a]["short"])
		var text := "%s\n%s\n%s" % [c["name"], c["role"] if ready else "Wkrótce", " · ".join(names)]
		var b := button(text, Vector2(w, 78), m.select_commander.bind(id), commander_row)
		b.toggle_mode = true
		b.disabled = not ready
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = "%s — %s" % [c["name"], c["role"]]
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_pressed_color", Main.HERO_COLOR)
		b.add_theme_color_override("font_hover_pressed_color", Main.HERO_COLOR)
		commander_buttons[id] = b


func build_pause(ui: Control) -> void:
	pause_layer = overlay(ui)
	var box: VBoxContainer = pause_layer.get_child(0).get_child(0)
	label("Pauza", 52, box)
	for entry in [["Wznów", func() -> void: m.set_paused(false)],
			["Zacznij od nowa", func() -> void: m.start(m.difficulty)],
			["Ustawienia", m.open_overlay.bind("settings")],
			["Menu główne", m.show_menu]]:
		var b := button(entry[0], Vector2(300, 54), entry[1], box)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func build_over(ui: Control) -> void:
	over_layer = overlay(ui)
	var box: VBoxContainer = over_layer.get_child(0).get_child(0)
	over_title = label("", 64, box)
	over_stats = label("", 18, box, Color(1, 1, 1, 0.85))
	for entry in [["Jeszcze raz", func() -> void: m.start(m.difficulty)], ["Menu główne", m.show_menu]]:
		var b := button(entry[0], Vector2(300, 58), entry[1], box)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func build_settings(ui: Control) -> void:
	settings_layer = overlay(ui)
	var box: VBoxContainer = settings_layer.get_child(0).get_child(0)
	label("Ustawienia", 44, box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	label("Efekty", 18, grid)
	sfx_slider = slider(grid, func(v: float) -> void:
		Settings.sfx_volume = v
		Settings.apply_audio()
		m.sfx.play("coin", 0.1))
	label("Muzyka", 18, grid)
	music_slider = slider(grid, func(v: float) -> void:
		Settings.music_volume = v
		Settings.apply_audio())
	label("Interfejs", 18, grid)
	scale_button = button("", Vector2(300, 48), m.cycle_ui_scale, grid)
	label("Licznik FPS (F3)", 18, grid)
	perf_button = button("", Vector2(300, 48), m.toggle_perf, grid)
	for entry in [["Pokaż samouczek ponownie", m.reset_tutorial], ["Wróć", m.close_overlay]]:
		var b := button(entry[0], Vector2(320, 50), entry[1], box)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func build_help(ui: Control) -> void:
	help_layer = overlay(ui, 0.9)
	var box: VBoxContainer = help_layer.get_child(0).get_child(0)
	label("Jak grać", 44, box)
	var help := label(
		"Trzy ścieżki prowadzą do fortecy wroga. Klik w złoże (●) stawia wydobywacz; sporne złoża\n"
		+ "przy ścieżkach wroga dają więcej, ale przechodzące fale je atakują.\n"
		+ "Koszary, strzelnice i warsztaty same produkują jednostki — w panelu budynku wybierasz ścieżkę.\n"
		+ "Wieże strzelają też w nietoperze, armaty biją obszarowo, mróz spowalnia, katapulty burzą wieże.\n"
		+ "Tarczownicy blokują większość strzał — na nich armaty i piechota. Wróg chętniej atakuje\n"
		+ "słabo bronione ścieżki. Postawa „Obrona” zbiera armię przed bazą — „Atak” rusza całością.\n"
		+ "Dowódca to jedyna postać, którą sterujesz: stuknij go (albo portret z lewej), potem miejsce\n"
		+ "na mapie — pójdzie tam (rzekę przechodzi mostem), sam walczy i wraca na swój punkt. Stuknięcie\n"
		+ "w budynek albo złoże zdejmuje zaznaczenie. Po śmierci wraca do bazy po chwili.\n"
		+ "Umiejętności dowódcy (Q/E/R) rzucasz w zasięgu od niego — okrąg pokazuje, dokąd sięga;\n"
		+ "gdy dowódca nie żyje, czekają. Umiejętność rasy (T) działa zawsze.\n"
		+ "Tryb Przetrwanie (przycisk w menu): forteca wroga nie pada — liczy się, ile fal wytrzymasz.\n"
		+ "Wyzwanie dnia: codziennie inna mapa, tryb, rasa i dowódca oraz dwa modyfikatory — taki sam dzień dla wszystkich.\n\n"
		+ "Mapę przesuwasz przeciągając, przybliżasz kółkiem albo dwoma palcami.\n"
		+ "Skróty: 1–6 budowa · Q/E/R/T umiejętności · H dowódca · Spacja postawa · U ulepsz · Del sprzedaj\n"
		+ "Tab ścieżka · F prędkość · WASD przesuwanie · C cała mapa · M dźwięk · Esc pauza",
		15, box, Color(1, 1, 1, 0.85))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var b := button("Wróć", Vector2(300, 50), m.close_overlay, box)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func rebuild_ui() -> void:
	ui_layer.free()
	build_buttons.clear()
	ability_slots.clear()
	ability_buttons.clear()
	upgrade_buttons.clear()
	lane_buttons.clear()
	race_buttons.clear()
	commander_buttons.clear()
	map_buttons.clear()
	diff_buttons.clear()
	build_ui()


func update_hud() -> void:
	game_ui.visible = m.state != Main.State.MENU
	menu_layer.visible = m.state == Main.State.MENU and m.overlay == ""
	pause_layer.visible = m.state == Main.State.PAUSED and m.overlay == ""
	over_layer.visible = m.state == Main.State.OVER and m.over_delay <= 0 and m.overlay == ""
	settings_layer.visible = m.overlay == "settings"
	help_layer.visible = m.overlay == "help"
	if m.state == Main.State.MENU:
		update_menu()
	if settings_layer.visible:
		scale_button.text = Settings.UI_SCALE_NAMES[Settings.ui_scale_index]
		perf_button.text = "wł." if Settings.show_perf else "wył."

	var me := m.sim.players[m.me]
	gold_label.text = "%d zł" % int(me.gold)
	income_label.text = "+%.1f zł/s · armia %d/%d" % [m.sim.income(m.me), m.sim.army_size(0), Cfg.MAX_ARMY]
	if m.sim.elapsed < me.bounty_until:
		income_label.text += " · łupy ×%.1f (%d s)" % [me.bounty_mult, ceili(me.bounty_until - m.sim.elapsed)]
	perf_label.visible = Settings.show_perf
	if perf_label.visible:
		perf_label.text = "FPS %d · sim %.1f ms (%d kr.) · rys. %.1f ms · HUD %.1f ms · jedn. %d · efekty %d" % [
			Engine.get_frames_per_second(), m.perf["sim"], m.perf["steps"], m.perf["draw"], m.perf["hud"],
			m.sim.units.size(), m.sparks.size() + m.texts.size()]
		if m.state == Main.State.PLAY and m.time >= m.perf_log_at:
			m.perf_log_at = m.time + 5.0
			print("[perf] %ds · %s" % [m.sim.elapsed, perf_label.text])
	if not m.sim.spawn_queue.is_empty():
		wave_label.text = "Fala %d nadciąga! (zostało %d)" % [m.sim.wave, m.sim.spawn_queue.size()]
	else:
		wave_label.text = "Fala %d za %d s → %s" % [m.sim.wave + 1, ceili(m.sim.wave_timer), m.sim.lane_names(m.sim.next_wave_lanes)]
	if m.sim.mode == "survival":
		wave_label.text = "Przetrwanie · " + wave_label.text
	daily_label.visible = not m.sim.mods.is_empty()
	if daily_label.visible:
		daily_label.text = "Wyzwanie dnia: " + m.mods_text(m.sim.mods)

	stance_button.text = "Postawa: Atak" if me.stance == "attack" else "Postawa: Obrona"
	stance_button.self_modulate = Color(1, 0.75, 0.7) if me.stance == "attack" else Color(0.7, 0.85, 1)
	speed_button.text = "x%d" % m.speed_mult
	mute_button.text = "Dźwięk" if not m.sfx.muted else "Cisza"
	minimap.visible = m.is_zoomed_in() and (m.state == Main.State.PLAY or m.state == Main.State.PAUSED)

	for key in build_buttons:
		var b: Button = build_buttons[key]
		var cost := m.sim.build_cost(key)  # z modyfikatorem dnia („Tanie wieże”)
		b.text = "%s\n%d" % [Cfg.BUILDINGS[key]["name"], cost]
		b.button_pressed = m.mode == key
		b.disabled = me.gold < cost and m.mode != key
	var order: Array = me.ability_order
	ability_buttons.clear()
	for i in ability_slots.size():
		var b := ability_slots[i]
		b.visible = i < order.size()
		if not b.visible:
			continue
		var a: String = order[i]
		ability_buttons[a] = b
		var cd: float = me.ability_cd[a]
		var status := "gotowe" if cd <= 0 else "%d s" % ceili(cd)
		if cd <= 0 and not m.sim.ability_ready(a, m.me):
			status = "poległ"
		b.text = "%s %s\n%s" % [ABILITY_KEY_NAMES[i], Cfg.ABILITIES[a]["short"], status]
		b.button_pressed = m.mode == "ab:" + a
		b.disabled = not m.sim.ability_ready(a, m.me)
	var h := m.sim.hero(m.me)
	portrait_button.visible = h != null and m.state == Main.State.PLAY
	if portrait_button.visible:
		var hero_name: String = "%s  poz. %d" % [Cfg.COMMANDERS[h.commander]["name"], h.hero_level]
		var xp := "max" if h.hero_level >= Cfg.HERO_MAX_LEVEL else "XP %d/%d" % [int(h.xp), int(Cfg.HERO_XP[h.hero_level - 1])]
		if m.sim.hero_alive(m.me):
			portrait_button.text = "%s  (H)\nHP %d/%d · %s" % [hero_name, ceili(h.hp), int(h.max_hp), xp]
		else:
			portrait_button.text = "%s\npowrót za %d s · %s" % [hero_name, ceili(h.respawn), xp]
		portrait_button.button_pressed = m.hero_selected
		portrait_button.disabled = not m.sim.hero_alive(m.me)
	var offers: Array = me.hero_offers
	upgrade_panel.visible = not offers.is_empty() and m.state == Main.State.PLAY
	if upgrade_panel.visible:
		upgrade_title.text = "Awans! Wybierz ulepszenie%s" % (" (+%d)" % (offers.size() - 1) if offers.size() > 1 else "")
		for i in 2:
			upgrade_buttons[i].text = offers[0][i]["label"]
		upgrade_panel.reset_size()
		upgrade_panel.position = Vector2(16, portrait_button.position.y - 8 - upgrade_panel.size.y)

	tutorial_panel.visible = m.tutorial_step >= 0 and m.state == Main.State.PLAY
	if tutorial_panel.visible:
		tutorial_label.text = "%d/%d  %s" % [m.tutorial_step + 1, Main.TUTORIAL.size(), Main.TUTORIAL[m.tutorial_step]["text"]]

	if m.selected != null and not m.sim.is_alive(m.selected):
		m.selected = null
	sel_panel.visible = m.selected != null and m.state == Main.State.PLAY
	if sel_panel.visible:
		fill_selection_panel(m.selected)
		sel_panel.reset_size()
		sel_panel.position = Vector2(screen.x - 16 - sel_panel.size.x, screen.y - 84 - sel_panel.size.y)


func update_menu() -> void:
	for i in race_buttons.size():
		race_buttons[i].button_pressed = i == m.race_index
	var race: Dictionary = Races.ALL[m.race_index]
	var racial := Races.racial(m.race_index)
	race_desc.text = "%s — %s  %sPrzeciwnik: losowy" % [race["name"], race["blurb"],
		"Umiejętność rasy: %s · " % Cfg.ABILITIES[racial]["name"] if racial != "" else ""]
	for id in commander_buttons:
		commander_buttons[id].button_pressed = id == m.commander_id
	for i in map_buttons.size():
		var lv: Dictionary = Levels.ALL[i]
		map_buttons[i].text = "%s\n%s" % [lv["name"], stars_text(Progress.stars(lv["id"]))]
		map_buttons[i].button_pressed = i == m.level_index
	var cur: Dictionary = Levels.ALL[m.level_index]
	map_desc.text = cur["desc"]
	for d in diff_buttons.size():
		var record := "—"
		if m.game_mode == "survival":
			var waves := Progress.best_survival(cur["id"], d, m.commander_id)
			record = "rekord: %d fal" % waves if waves > 0 else "—"
		else:
			var best := Progress.best(cur["id"], d)
			record = "rekord %s" % fmt_time(best) if best >= 0 else "—"
		diff_buttons[d].text = "%s\n%s" % [Cfg.DIFFICULTIES[d]["name"], record]
	mode_button.text = "Tryb: Bitwa" if m.game_mode == "battle" else "Tryb: Przetrwanie"


func fill_selection_panel(b: Sim.Building) -> void:
	var cfg: Dictionary = Cfg.BUILDINGS[b.kind]
	var lines := PackedStringArray()
	var next_level := b.level + 1
	var has_next := b.level < Cfg.MAX_LEVEL
	if Cfg.is_tower(b.kind):
		var s := m.sim.tower_stats(b.kind, b.level)
		lines.append("Obrażenia %d · zasięg %d · co %.1f s" % [s["dmg"], s["range"], s["cd"]])
		if s["slow"] > 0:
			lines.append("Spowalnia o %d%% na %.1f s (obszar %d)" % [s["slow"] * 100, s["slow_time"], s["splash"]])
		elif s["splash"] > 0:
			lines.append("Obrażenia obszarowe (promień %d)" % s["splash"])
		lines.append("Trafia latające" if Cfg.ANTI_AIR.has(s["projectile"]) else "Nie trafia latających")
		if has_next and b.team == 0:
			var n := m.sim.tower_stats(b.kind, next_level)
			lines.append("Poz. %d: obr. %d · zasięg %d" % [next_level, n["dmg"], n["range"]])
	elif Cfg.is_production(b.kind):
		var unit: String = cfg["unit"]
		lines.append("%s poz. %d co %.1f s → %s" % [Cfg.UNITS[unit]["name"], b.level,
			m.sim.production_period(b.kind, b.level), m.sim.lanes[b.lane].name])
		lines.append("Jednostka: HP %d · obr. %d" % [m.sim.unit_hp(unit, b.level), m.sim.unit_dmg(unit, b.level)])
		if m.sim.team_count[0] >= Cfg.MAX_ARMY:
			lines.append("Limit armii (%d) — produkcja czeka na miejsce" % Cfg.MAX_ARMY)
		if has_next:
			lines.append("Poz. %d: co %.1f s · HP %d · obr. %d" % [next_level, m.sim.production_period(b.kind, next_level),
				m.sim.unit_hp(unit, next_level), m.sim.unit_dmg(unit, next_level)])
	elif b.kind == "extractor":
		var rich := m.sim.richness[b.node_index] > 1.0
		lines.append("Wydobycie +%.1f zł/s%s" % [m.sim.extractor_income(b.node_index, b.level), " (bogate złoże)" if rich else ""])
		if has_next:
			lines.append("Poz. %d: +%.1f zł/s" % [next_level, m.sim.extractor_income(b.node_index, next_level)])
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
	var up := m.sim.upgrade_cost(b)
	upgrade_button.text = "Maks. poziom" if up < 0 else "Ulepsz  %d" % up
	upgrade_button.disabled = up < 0 or m.sim.players[m.me].gold < up
	sell_button.text = "Sprzedaj  +%d" % m.sim.sell_value(b)


func on_minimap_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var held: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if clicked or held:
		m.camera.position = event.position * (m.sim.size.x / minimap.size.x)
		m.clamp_camera()
		m.camera_used = true
		minimap.accept_event()


static func fmt_time(t: float) -> String:
	return "%d:%02d" % [floori(t / 60.0), int(t) % 60]


static func stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(Cfg.DIFFICULTIES.size() - n)


func label(text: String, size: int, parent: Control, color := Color.WHITE) -> Label:
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


func button(text: String, min_size: Vector2, on_press: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE  # inaczej Spacja „klika" ostatni przycisk
	b.pressed.connect(func() -> void:
		m.sfx.play("click", 0.0)
		on_press.call())
	parent.add_child(b)
	return b


func slider(parent: Control, on_change: Callable) -> HSlider:
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
func overlay(ui: Control, dim := 0.8) -> Control:
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


func make_theme() -> Theme:
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
		sb.border_color = Color(1, 1, 1, 0.12) if look != "pressed" and look != "hover_pressed" else Main.GOLD_COLOR
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


func draw_banner() -> void:
	if m.banner_life <= 0:
		return
	var c := fx_canvas
	var a := clampf(m.banner_life, 0.0, 1.0)
	var y := 190.0
	c.draw_string_outline(m.font, Vector2(0, y), m.banner_text, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 48, 8, Color(0, 0, 0, a * 0.7))
	c.draw_string(m.font, Vector2(0, y), m.banner_text, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 48, Color(1, 1, 1, a))
	if m.banner_sub != "":
		c.draw_string_outline(m.font, Vector2(0, y + 34), m.banner_sub, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 22, 6, Color(0, 0, 0, a * 0.7))
		c.draw_string(m.font, Vector2(0, y + 34), m.banner_sub, HORIZONTAL_ALIGNMENT_CENTER, screen.x, 22, Color(1, 0.9, 0.7, a))


func draw_minimap() -> void:
	var c := minimap
	var k := c.size.x / m.sim.size.x
	var xf := Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.1, 0.16, 0.1, 0.92))
	if not m.view.river_points.is_empty():
		c.draw_polyline(xf * m.view.river_points, Color(0.2, 0.42, 0.62), 3.0)
	for i in m.view.lane_points.size():
		c.draw_polyline(xf * m.view.lane_points[i], Color(0.55, 0.47, 0.34), 3.0)
	for i in m.view.warn_lanes():
		c.draw_polyline(xf * m.view.lane_points[i], Color(Main.WARN_COLOR, 0.7), 3.0)
	for team in 2:
		c.draw_rect(Rect2(m.sim.base_pos(team) * k - Vector2(5, 5), Vector2(10, 10)), Main.TEAM_COLORS[team])
	for b in m.sim.buildings:
		if b.kind != "basegun":
			c.draw_rect(Rect2(b.pos * k - Vector2(2, 2), Vector2(4, 4)), Main.TEAM_COLORS[b.team].lightened(0.3))
	for u in m.sim.units:
		c.draw_rect(Rect2(u.pos * k - Vector2(1, 1), Vector2(2, 2)), Main.TEAM_COLORS[u.team])
	if m.sim.hero_alive(m.me):
		c.draw_circle(m.sim.hero(m.me).pos * k, 4.0, Main.HERO_COLOR)
	if m.sim.hero_alive(1):
		c.draw_circle(m.sim.hero(1).pos * k, 4.0, Main.TEAM_COLORS[1].lightened(0.4))
	var view := Rect2(m.to_world(Vector2.ZERO) * k, m.view_size / m.camera.zoom.x * k)
	c.draw_rect(view, Color(1, 1, 1, 0.9), false, 1.5)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.3), false, 1.0)
