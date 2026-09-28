extends Node
## Zrzuty ekranu prawdziwej sceny do oceny grafiki: partia z budynkami i walką na ścieżkach,
## zrzut całej mapy i zbliżenia. Okno musi się renderować (bez --headless):
##
##   godot --path . -- --bench res://tests/screenshot.gd [--out <folder>] [--map N] [--race hyena] [--rival gibbon]
##
## Pliki: <folder>/shot_full.png, shot_zoom.png, shot_zoom_enemy.png (domyślnie user://).

var main: Node
var frame := 0
var out := "user://"
var race := ""
var rival := ""
var map := 0


func _ready() -> void:
	Progress.path = "user://shot_progress.cfg"
	Settings.path = "user://shot_settings.cfg"
	Progress.reset_cache()
	Progress.set_tutorial_done(true)
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--out": out = args[i + 1]
			"--map": map = int(args[i + 1])
			"--race": race = args[i + 1]
			"--rival": rival = args[i + 1]


func _race_index(id: String) -> int:
	for i in Races.ALL.size():
		if Races.ALL[i]["id"] == id:
			return i
	return -1


func _process(_delta: float) -> void:
	frame += 1
	if frame == 3:
		main.level_index = map
		if race != "":
			main.race_index = _race_index(race)
			main.commander_id = ""
		main.start(1)
		if rival != "":
			main.rival_index = _race_index(rival)
		main.banner_life = 0.0
		var sim: Sim = main.sim
		sim.players[0].gold = 5000
		for i in sim.nodes.size():
			sim.build_extractor(i)
		var kinds := ["tower", "cannon", "frost", "barracks", "range", "workshop", "tower", "barracks"]
		for i in kinds.size():
			var c := sim.free_cell_near(Vector2(260, 450), 400)
			if sim.build(kinds[i], c) and Cfg.is_production(kinds[i]):
				sim.set_lane(sim.building_at(c, 0), i % sim.lanes.size())
		sim.wave_timer = 1.0
		Engine.time_scale = 3.0
	if frame == 3 + 60 * 14:  # ~40 s gry
		Engine.time_scale = 1.0
		main.banner_life = 0.0
	if frame == 3 + 60 * 14 + 20:
		main.reset_camera()
	if frame == 3 + 60 * 14 + 30:
		_shot("shot_full.png")
	if frame == 3 + 60 * 14 + 32:  # zrzut czeka na koniec klatki — kamerę ruszamy dopiero potem
		main.camera.zoom = Vector2.ONE * main.ZOOM_MAX
		main.camera.position = _front(0)
		main.clamp_camera()
	if frame == 3 + 60 * 14 + 40:
		_shot("shot_zoom.png")
	if frame == 3 + 60 * 14 + 42:
		main.camera.position = main.sim.e_base + Vector2(-160, 0)
		main.clamp_camera()
	if frame == 3 + 60 * 14 + 50:
		_shot("shot_zoom_enemy.png")
		get_tree().quit()


## Czoło armii gracza (najdalej wysunięta jednostka), inaczej środek mapy.
func _front(team: int) -> Vector2:
	var best := Vector2(800, 450)
	var far := -INF
	for u in main.sim.units:
		if u.team == team and not u.is_hero and u.pos.x > far:
			far = u.pos.x
			best = u.pos
	return best - Vector2(60, 0)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(file))
	print("[shot] ", out.path_join(file))
