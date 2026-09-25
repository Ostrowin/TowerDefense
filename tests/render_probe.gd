extends Node
## Sonda renderu na telefonie: ta sama scena w kilku wariantach (bez terenu, bez HUD,
## bez świata, render w niższej rozdzielczości…), w każdym ~4 s pomiaru czasu klatki.
## Pokazuje, która warstwa kosztuje i czy ogranicza procesor, czy GPU.
##
##   tools/android.ps1 -Bench -BenchScript res://tests/render_probe.gd   (telefon, wynik w logu)
##   godot --path . -- --bench res://tests/render_probe.gd                 (desktop)
##
## Uruchamia go main.gd (`--bench`) jako węzeł-dziecko sceny gry; `main` ustawia main.gd.

const WARMUP := 1.0
const MEASURE := 4.0

var main: Node
var frame := 0
var phase := -1
var phase_t := 0.0
var last_us := 0
var samples: Array[float] = []

## [nazwa, teren, świat, HUD, render w rozdzielczości bazowej]
const PHASES := [
	["wszystko", true, true, true, false],
	["bez terenu", false, true, true, false],
	["bez HUD", true, true, false, false],
	["tylko HUD", false, false, true, false],
	["nic", false, false, false, false],
	["wszystko, render 1600x720", true, true, true, true],
	["wszystko (powtórka)", true, true, true, false],
]


func _ready() -> void:
	Progress.path = "user://probe_progress.cfg"
	Settings.path = "user://probe_settings.cfg"
	Progress.reset_cache()
	Progress.set_tutorial_done(true)


func _process(_delta: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	var dt := (now - last_us) / 1000.0
	last_us = now
	if frame == 3:
		main._start(1)
		var sim: Sim = main.sim
		sim.gold = 3000
		for i in sim.nodes.size():
			sim.build_extractor(i)
		for k in ["barracks", "range", "tower", "cannon", "frost", "barracks"]:
			var c := sim.free_cell_near(Vector2(250, 450), 400)
			if sim.build(k, c) and Cfg.is_production(k):
				sim.set_lane(sim.building_at(c, 0), sim.stats["units_made"] % 3)
		print("[probe] ekran %s, widok %s, %s" % [DisplayServer.screen_get_size(), main.view_size, RenderingServer.get_video_adapter_name()])
		_next_phase()
		return
	if phase < 0:
		return
	# stała scena: gra cały czas trwa, baza gracza nie do zdobycia
	main.sim.base_hp[0] = 1e9
	phase_t += dt / 1000.0
	if phase_t > WARMUP:
		samples.append(dt)
	if phase_t >= WARMUP + MEASURE:
		_report()
		if phase + 1 >= PHASES.size():
			for p in [Progress.path, Settings.path]:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			print("[bench] koniec")
			set_process(false)
			get_tree().quit()
			return
		_next_phase()


func _next_phase() -> void:
	phase += 1
	phase_t = 0.0
	samples.clear()
	var p: Array = PHASES[phase]
	main.terrain.visible = p[1]  # teren to dziecko main — ukryty świat chowa też teren
	main.visible = p[2]
	main.ui_layer.visible = p[3]
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if p[4] else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _report() -> void:
	var s := samples.duplicate()
	s.sort()
	var n := s.size()
	var avg := 0.0
	for v in s:
		avg += v
	avg /= maxf(n, 1)
	# sim / rys. / HUD = czas procesora w GDScript (licznik F3); reszta klatki to silnik i GPU
	var pf: Dictionary = main.perf
	print("[probe] %-26s %5.1f fps  klatka śr. %5.1f ms  p90 %5.1f ms  sim %4.1f  rys. %4.1f  HUD %4.1f ms  draw calls %d  prymitywy %d  jedn. %d" % [
		PHASES[phase][0], 1000.0 / avg, avg, s[int(n * 0.9)], pf["sim"], pf["draw"], pf["hud"],
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), main.sim.units.size()])
