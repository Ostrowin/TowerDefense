extends Node
## Benchmark wydajności: prawdziwa scena gry, bot gra długą partię na Trudnym na x3
## w czasie rzeczywistym (bez --fixed-fps — liczy się prawdziwy czas klatki).
## Co ~5 s gry wypisuje: czas klatki (śr./maks.), kroki sima na klatkę, liczbę
## jednostek/pocisków/efektów, obiekty i pamięć — widać, co rośnie pod koniec partii.
##
##   godot --headless --path . -- --bench res://tests/perf_test.gd [--map 2 --minutes 12]
##       [--commander magma] [--stress]   — dowódca gracza; --stress: rzuca każdą gotową umiejętność
##                                          (scenariusz z kryteriów sukcesu: strefy, budowle, wzmocnienia)
##   tools/android.ps1 -Bench                       (na telefonie, z prawdziwym GPU)
##   tools/android.ps1 -Bench -BenchArgs '--map','2','--minutes','10','--commander','magma','--stress'
##
## Uruchamia go main.gd (`--bench`) jako węzeł-dziecko sceny gry; `main` ustawia main.gd.
## Headless nie rysuje na GPU, ale cały koszt GDScript (_draw, HUD, sim) jest mierzony.

const BOT_THINK := 0.5

var main: Node
var frame := 0
var minutes := 12.0
var map_index := 2
var commander := ""
var stress := false
var think := 0.0
var plan_i := 0
var last_us := 0
var window_frames := 0
var window_us := 0
var window_max := 0
var window_steps := 0
var next_log := 5.0
var worst_frame_ms := 0.0
var frame_times: Array[float] = []

## Plan jak w bot_test („balanced"), żeby partia doszła do późnej fazy z dużą armią.
const PLAN := [
	["barracks", Vector2(170, 330)], ["tower", Vector3(1, 330, 70)], ["range", Vector2(170, 580)],
	["tower", Vector3(0, 330, -70)], ["tower", Vector3(2, 330, 70)], ["cannon", Vector3(1, 460, -70)],
	["workshop", Vector2(330, 330)], ["frost", Vector3(1, 400, 70)], ["barracks", Vector2(330, 580)],
	["cannon", Vector3(0, 460, 70)], ["cannon", Vector3(2, 460, -70)], ["range", Vector2(120, 250)],
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == "--map":
			map_index = int(args[i + 1])
		elif args[i] == "--minutes":
			minutes = float(args[i + 1])
		elif args[i] == "--commander":
			commander = args[i + 1]
	stress = args.has("--stress")
	Progress.path = "user://perf_progress.cfg"
	Settings.path = "user://perf_settings.cfg"
	Progress.reset_cache()
	Progress.set_tutorial_done(true)


func _process(_delta: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame == 3:
		main.level_index = map_index
		if commander != "":
			main.race_index = Races.ALL.find_custom(func(r: Dictionary) -> bool: return r["id"] == Cfg.COMMANDERS[commander]["race"])
			main.commander_id = commander
		main._start(2)
		main.speed_mult = 3
		# baza gracza nie do zdobycia — mierzymy późną grę, nie przegraną
		main.sim.base_hp[0] = 1e9
		print("mapa %s, Trudny, x3, %d min gry, dowódca: %s%s" % [main.sim.level["name"], minutes,
			main.sim.commander if main.sim.commander != "" else "brak", " (stress)" if stress else ""])
		print("%6s %5s %6s %6s %6s %6s %8s %8s %6s %6s %6s %6s %6s %7s" % ["gra", "fala", "jedn.", "pocis.", "iskry", "napisy",
			"klatka", "maks", "sim", "kroki", "zdarz", "hud", "rys.", "pamięć"])
	if frame > 3:
		var sim: Sim = main.sim
		var ms := (now - last_us)
		window_frames += 1
		window_us += ms
		window_max = maxi(window_max, ms)
		frame_times.append(ms / 1000.0)
		_bot(sim)
		if sim.elapsed >= next_log:
			next_log += 5.0
			var p: Dictionary = main.perf
			print("%5ds %5d %6d %6d %6d %6d %6.1fms %6.1fms %6.1f %6d %6.1f %6.1f %6.1f %5dMB" % [
				sim.elapsed, sim.wave, sim.units.size(), sim.shots.size(), main.sparks.size(), main.texts.size(),
				window_us / 1000.0 / window_frames, window_max / 1000.0,
				p["sim"], p["steps"], p["events"], p["hud"], p["draw"], OS.get_static_memory_usage() / 1048576])
			window_frames = 0
			window_us = 0
			window_max = 0
		if sim.elapsed >= minutes * 60.0 or sim.result != 0:
			frame_times.sort()
			var n := frame_times.size()
			print("klatki: %d, mediana %.1f ms, p95 %.1f ms, p99 %.1f ms, maks %.1f ms, wynik %d" % [
				n, frame_times[n / 2], frame_times[int(n * 0.95)], frame_times[int(n * 0.99)], frame_times[n - 1], sim.result])
			print("obiekty: %d, węzły: %d" % [Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
			var steps: int = sim.prof_data.get("kroki", 0)
			if steps > 0:
				print("sim przy >150 jednostkach (%d kroków), średnio na krok:" % steps)
				for k in sim.prof_data:
					if k != "kroki":
						var v: float = sim.prof_data[k] / float(steps)
						print("  %-12s %s" % [k, "%.0f" % v if k == "zdarzenia" else "%.2f ms" % (v / 1000.0)])
			for p in [Progress.path, Settings.path]:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			print("[bench] koniec")
			set_process(false)
			get_tree().quit()
			return
	last_us = now


func _bot(sim: Sim) -> void:
	think -= 1.0 / 60.0 * main.speed_mult
	if think > 0:
		return
	think = BOT_THINK
	for i in sim.nodes.size():
		sim.build_extractor(i)
	if plan_i < PLAN.size():
		var a: Variant = PLAN[plan_i][1]
		var p: Vector2 = a if a is Vector2 else sim.lanes[int(a.x)].slot_at(a.y, a.z)
		var cell := sim.free_cell_near(p, 120.0)
		if cell == Vector2.INF or sim.build(PLAN[plan_i][0], cell):
			if cell != Vector2.INF:
				sim.set_lane(sim.building_at(cell, 0), plan_i % 3)
			plan_i += 1
		return
	for b in sim.buildings:
		if b.team == 0 and b.kind != "basegun" and sim.upgrade_cost(b) > 0 and sim.upgrade(b):
			return
	var kinds := ["workshop", "barracks", "range"]
	var kind: String = kinds[sim.stats["units_made"] % 3]
	if sim.gold > Cfg.BUILDINGS[kind]["cost"] + 100:
		var cell := sim.free_cell_near(sim.p_base + Vector2(200, 0), 500.0)
		if cell != Vector2.INF and sim.build(kind, cell):
			sim.set_lane(sim.building_at(cell, 0), sim.stats["units_made"] % 3)
	# bez Naprawy — przycina HP bazy do maksimum i test przestałby trzymać bazę przy życiu
	for ab in ["arrows", "levy"]:
		if sim.ability_ready(ab):
			sim.use_ability(ab, sim.lanes[1].point_at(400))
	# profil faz kroku zbieramy dopiero w dużej bitwie
	if not sim.profile and sim.units.size() > 150:
		sim.profile = true
		sim.prof_data.clear()


## Dowódca: idzie za czołem własnej armii; przy --stress rzuca każdą gotową umiejętność
## w najbliższego wroga (albo przy sobie), żeby strefy, budowle i wzmocnienia się kumulowały.
func _hero(sim: Sim) -> void:
	var h := sim.hero()
	if not sim.hero_alive():
		return
	var front := sim.rally_s
	for u in sim.units:
		if u.team == 0 and u.lane == 1 and not u.is_hero:
			front = maxf(front, u.s)
	var post := sim.lanes[1].point_at(front - 50.0)
	if h.post.distance_to(post) > 60.0 and h.state != "march":
		sim.order_hero(post)
	if not sim.hero_offers[0].is_empty():
		sim.choose_upgrade(0)
	if not stress:
		return
	var foe: Sim.Unit = null
	for u in sim.units:
		if u.team == 1 and (foe == null or u.pos.distance_to(h.pos) < foe.pos.distance_to(h.pos)):
			foe = u
	for a in sim.ability_order[0]:
		if not sim.ability_ready(a):
			continue
		var tries: Array[Vector2] = [foe.pos if foe != null else h.pos, h.pos]
		for k in 8:
			tries.append(h.pos + Vector2.from_angle(TAU * k / 8.0) * 80.0)
		for at in tries:
			if sim.use_ability(a, at):
				break
