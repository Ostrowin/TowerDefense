extends SceneTree
## Testy headless + narzędzie do strojenia balansu.
##
##   godot --headless --path . --script res://tests/bot_test.gd                  # wszystko (~5 min)
##   godot --headless --path . --script res://tests/bot_test.gd -- --mechanics   # tylko mechaniki (~15 s)
##   godot --headless --path . --script res://tests/bot_test.gd -- --balance     # tylko mecze botów
##       [--maps 0,2] [--diffs 1,2] [--bot balanced|mass|turtle]   — np. kilka procesów równolegle
##
## 1. Testy mechanik: małe, deterministyczne scenariusze na Sim + geometria każdej mapy.
## 2. Mecze botów: bot gra za gracza na każdej mapie i trudności, wypisuje tabelę wyników.
## Kod wyjścia 1 = któraś asercja nie przeszła.

const DT := 1.0 / 30.0
const MAX_TIME := 1500.0  # 25 min czasu gry
const BOT_THINK := 0.5
## Ścieżka, na którą bot „balanced" kieruje całą produkcję.
const PUSH_LANE := 1

## Plan budowy: [rodzaj, kotwica]. Kotwica = Vector2 (okolica punktu) albo
## Vector3(ścieżka, s od bazy gracza, przesunięcie w bok). Bot stawia na
## najbliższym wolnym polu przy kotwicy; po planie ulepsza i dobudowuje produkcję.
const BALANCED_PLAN := [
	["barracks", Vector2(170, 330)], ["tower", Vector3(1, 330, 70)], ["range", Vector2(170, 580)],
	["tower", Vector3(0, 330, -70)], ["tower", Vector3(2, 330, 70)], ["cannon", Vector3(1, 460, -70)],
	["workshop", Vector2(330, 330)], ["frost", Vector3(1, 400, 70)], ["barracks", Vector2(330, 580)],
	["cannon", Vector3(0, 460, 70)], ["cannon", Vector3(2, 460, -70)], ["range", Vector2(120, 250)],
]
const TURTLE_PLAN := [
	["tower", Vector3(1, 330, 70)], ["tower", Vector3(0, 330, -70)], ["tower", Vector3(2, 330, 70)],
	["cannon", Vector3(1, 460, -70)], ["cannon", Vector3(0, 460, 70)], ["cannon", Vector3(2, 460, -70)],
	["frost", Vector3(1, 250, -70)], ["tower", Vector3(0, 250, 70)], ["tower", Vector3(2, 250, -70)],
]

var failures := 0


func _init() -> void:
	Progress.path = "user://test_progress.cfg"
	Progress.reset_cache()
	var args := OS.get_cmdline_user_args()
	if args.has("--balance"):
		# opcjonalnie: --maps 0,2 --diffs 1,2 --bot mass (np. żeby puścić kilka procesów równolegle)
		var maps := _int_list(args, "--maps", Levels.ALL.size())
		var diffs := _int_list(args, "--diffs", Cfg.DIFFICULTIES.size())
		var bot := args[args.find("--bot") + 1] if args.has("--bot") else "balanced"
		_print_header()
		for lv in maps:
			for d in diffs:
				_report(lv, d, bot)
		quit()
		return

	print("== testy mechanik ==")
	for lv in Levels.ALL.size():
		_test_map_layout(lv)
	_test_build_rules()
	_test_upgrade_and_sell()
	_test_income()
	_test_splash()
	_test_catapult_razes_tower()
	_test_lane_following()
	_test_rejoin_stays_on_loop()
	_test_stance()
	_test_production_lane()
	_test_wave_lanes()
	_test_smart_lane_choice()
	_test_enemies_hit_buildings_and_regen()
	_test_flying()
	_test_armor()
	_test_frost_slows()
	_test_abilities()
	_test_progress()
	_test_population_caps()
	_test_wave_composition()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.path))

	if not args.has("--mechanics"):
		print("\n== mecze botów ==")
		_print_header()
		for lv in Levels.ALL.size():
			_report(lv, 1, "idle")
			if lv == 0:
				_report(lv, 1, "turtle")
			for d in Cfg.DIFFICULTIES.size():
				_report(lv, d, "balanced")
			_report(lv, 2, "mass")

	print("\n%s" % ("OK" if failures == 0 else "BŁĘDY: %d" % failures))
	quit(1 if failures > 0 else 0)


## Lista liczb z argumentu `--flag 0,2`; bez flagi — 0..count-1.
func _int_list(args: PackedStringArray, flag: String, count: int) -> Array[int]:
	var out: Array[int] = []
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size():
		for part in args[i + 1].split(","):
			out.append(int(part))
	else:
		for k in count:
			out.append(k)
	return out


func _print_header() -> void:
	print("%-11s %-9s %-9s %-9s %6s %5s %6s %6s %6s %8s" % ["mapa", "trudność", "bot", "wynik", "czas", "fala", "zabici", "armia", "wieże", "stracone"])


func _report(lv: int, d: int, strategy: String) -> void:
	var r := _play(lv, d, strategy)
	print("%-11s %-9s %-9s %-9s %5ds %5d %6d %6d %6d %8d" % [
		Levels.ALL[lv]["name"], Cfg.DIFFICULTIES[d]["name"], strategy, ["przegrana", "remis", "WYGRANA"][r.result + 1],
		int(r.elapsed), r.wave, r.stats["kills"], r.stats["units_made"], r.stats["towers_razed"], r.stats["buildings_lost"]])
	var where := "%s/%s" % [Levels.ALL[lv]["name"], Cfg.DIFFICULTIES[d]["name"]]
	if strategy == "idle":
		_check(r.result == -1, "bezczynny gracz musi przegrać (%s)" % where)
	if strategy == "balanced" and d <= 1:
		_check(r.result == 1, "bot balanced powinien wygrać (%s)" % where)
	if strategy == "balanced" or strategy == "mass":
		_check(r.result != 0, "partia musi się rozstrzygnąć w %d min (%s, %s)" % [MAX_TIME / 60.0, where, strategy])


# ================================================================ bot

func _play(lv: int, difficulty: int, strategy: String) -> Sim:
	var sim := Sim.new(difficulty, 1234, lv)
	var plan: Array = TURTLE_PLAN if strategy == "turtle" else BALANCED_PLAN
	var plan_i := 0
	var think := 0.0
	var node_cooldown := {}  # złoże → czas, do którego bot go nie odbudowuje
	while sim.result == 0 and sim.elapsed < MAX_TIME:
		sim.step(DT)
		for e in sim.events:
			if e["type"] == "building_destroyed" and e["kind"] == "extractor":
				node_cooldown[sim.node_at(e["pos"])] = sim.elapsed + 90.0
		sim.events.clear()
		_check(sim.gold >= 0, "złoto nie może spaść poniżej zera")
		think -= DT
		if think > 0 or strategy == "idle":
			continue
		think = BOT_THINK
		for i in sim.nodes.size():
			if sim.elapsed >= node_cooldown.get(i, 0.0):
				sim.build_extractor(i)
		if plan_i < plan.size():
			var cell := _resolve(sim, plan[plan_i][1])
			if cell == Vector2.INF:
				plan_i += 1  # brak miejsca — pomiń (test mapy i tak to wyłapie)
			elif sim.build(plan[plan_i][0], cell):
				sim.set_lane(sim.building_at(cell, 0), PUSH_LANE)
				plan_i += 1
		elif not _upgrade_cheapest(sim) and strategy != "turtle":
			_expand(sim)
		_use_abilities(sim)
		_set_stance(sim, strategy)
	return sim


## Postawa bota:
##   turtle   — zawsze obrona
##   balanced — atak od 10 jednostek, odwrót przy 3 (ciągłe natarcie małymi grupami)
##   mass     — na początku jak balanced; od 4. minuty zbiera armię w obronie do 70%
##              limitu i uderza całością (tak gra rozsądny człowiek przy limicie populacji)
func _set_stance(sim: Sim, strategy: String) -> void:
	var army := sim.army_size(0)
	match strategy:
		"turtle":
			sim.set_stance("defend")
		"balanced":
			if army >= 10:
				sim.set_stance("attack")
			elif army <= 3:
				sim.set_stance("defend")
		"mass":
			var early := sim.elapsed < 240.0
			if army >= (10 if early else int(Cfg.MAX_ARMY * 0.7)):
				sim.set_stance("attack")
			elif army <= (3 if early else 30):
				sim.set_stance("defend")


func _resolve(sim: Sim, anchor: Variant) -> Vector2:
	var p: Vector2 = anchor if anchor is Vector2 else sim.lanes[int(anchor.x)].slot_at(anchor.y, anchor.z)
	return sim.free_cell_near(p, 120.0)


## Ulepsza najtańszy budynek, który da się ulepszyć. false = nie ma już czego ulepszać.
func _upgrade_cheapest(sim: Sim) -> bool:
	var best: Sim.Building = null
	for b in sim.buildings:
		if b.team == 0 and b.kind != "basegun" and sim.upgrade_cost(b) > 0:
			if best == null or sim.upgrade_cost(b) < sim.upgrade_cost(best):
				best = b
	if best != null:
		sim.upgrade(best)
	return best != null


## Po planie i ulepszeniach: nadwyżka złota idzie w kolejne budynki produkcyjne.
func _expand(sim: Sim) -> void:
	var kinds := ["workshop", "barracks", "range"]
	var kind: String = kinds[sim.stats["units_made"] % kinds.size()]
	if sim.gold < Cfg.BUILDINGS[kind]["cost"] + 100:
		return
	var cell := sim.free_cell_near(sim.p_base + Vector2(200, 0), 500.0)
	if cell != Vector2.INF and sim.build(kind, cell):
		sim.set_lane(sim.building_at(cell, 0), PUSH_LANE)


## Umiejętności: deszcz strzał w największe skupisko wrogów, pobór przeciw wrogowi
## najbliżej bazy, naprawa przy uszkodzonej bazie.
func _use_abilities(sim: Sim) -> void:
	var radius: float = Cfg.ABILITIES["arrows"]["radius"]
	if sim.ability_ready("arrows"):
		var best_pos := Vector2.INF
		var best_n := 3
		for u in sim.units:
			if u.team != 1:
				continue
			var n := 0
			for o in sim.units:
				if o.team == 1 and o.pos.distance_to(u.pos) <= radius:
					n += 1
			if n > best_n:
				best_n = n
				best_pos = u.pos
		if best_pos != Vector2.INF:
			sim.use_ability("arrows", best_pos)
	if sim.ability_ready("levy"):
		for u in sim.units:
			if u.team == 1 and not u.flying and u.pos.x < sim.size.x * 0.35:
				sim.use_ability("levy", sim.lanes[u.lane].point_at(maxf(u.s - 60.0, 80.0)))
				break
	if sim.ability_ready("repair") and sim.base_hp[0] < Cfg.BASE_HP[0] * 0.7:
		sim.use_ability("repair")


# ================================================================ testy mechanik

func _test_map_layout(lv: int) -> void:
	var sim := Sim.new(1, 1, lv)
	var name: String = Levels.ALL[lv]["name"]
	for i in sim.nodes.size():
		for lane in sim.lanes:
			_check(lane.distance_to(sim.nodes[i]) >= Cfg.PATH_HALF + 30, "%s: złoże %d nie leży na ścieżce %s" % [name, i, lane.name])
	for i in sim.enemy_slot_count():
		var p := sim.enemy_slot_pos(i)
		for lane in sim.lanes:
			_check(lane.distance_to(p) >= Cfg.PATH_HALF + 30, "%s: slot wieży wroga %d nie leży na ścieżce %s" % [name, i, lane.name])
		_check(Rect2(Vector2.ZERO, sim.size).has_point(p), "%s: slot wieży wroga %d na mapie" % [name, i])
	for lane in sim.lanes:
		_check(lane.point_at(0).distance_to(sim.p_base) < 1.0, "%s: ścieżka %s zaczyna się w bazie gracza" % [name, lane.name])
		_check(lane.point_at(lane.length).distance_to(sim.e_base) < 1.0, "%s: ścieżka %s kończy się w bazie wroga" % [name, lane.name])
		_check(lane.length > 1400.0, "%s: ścieżka %s jest kręta i długa" % [name, lane.name])
		# zakręty tej samej ścieżki nie mogą na siebie nachodzić
		var pts := lane.curve.get_baked_points()
		var worst := INF
		for a in range(0, pts.size(), 3):
			for b in range(a + 60, pts.size(), 3):
				worst = minf(worst, pts[a].distance_to(pts[b]))
		_check(worst >= Cfg.PATH_HALF * 2 + 10, "%s: pętle ścieżki %s nie nachodzą na siebie (%.0f px)" % [name, lane.name, worst])
	for p in BALANCED_PLAN + TURTLE_PLAN:
		_check(_resolve(sim, p[1]) != Vector2.INF, "%s: kotwica planu bota %s ma wolne pole" % [name, str(p[1])])


func _test_build_rules() -> void:
	var sim := Sim.new(1, 1)
	sim.gold = 10000
	_check(not sim.can_place(Cfg.snap(sim.lanes[1].point_at(300))), "nie można stawiać na ścieżce")
	_check(not sim.can_place(sim.nodes[0]), "nie można stawiać na złożu")
	_check(not sim.can_place(Vector2(1100, 820)), "nie można stawiać na połowie wroga")
	var cell := sim.free_cell_near(sim.lanes[0].slot_at(330, -70))
	_check(sim.build("tower", cell), "budowa wieży")
	_check(not sim.build("tower", cell), "nie można stawiać na zajętej komórce")
	_check(sim.build_extractor(0), "budowa wydobywacza")
	_check(not sim.build_extractor(0), "jedno złoże = jeden wydobywacz")
	sim.gold = 0
	_check(not sim.build("tower", sim.free_cell_near(Vector2(300, 330))), "brak złota blokuje budowę")


func _test_upgrade_and_sell() -> void:
	var sim := Sim.new(1, 1)
	sim.gold = 1000
	var cell := sim.free_cell_near(Vector2(300, 330))
	sim.build("tower", cell)
	var t := sim.building_at(cell, 0)
	_check(t != null, "building_at znajduje wieżę")
	_check(sim.upgrade(t) and sim.upgrade(t), "dwa ulepszenia")
	_check(t.level == 3 and not sim.upgrade(t), "maks. poziom 3")
	_check(t.invested == 80 + 70 + 140, "invested sumuje koszty")
	var before := sim.gold
	_check(sim.sell(t), "sprzedaż")
	_check(is_equal_approx(sim.gold - before, int(290 * Cfg.SELL_REFUND)), "zwrot 60% włożonego złota")
	_check(sim.building_at(cell, 0) == null, "sprzedany budynek znika")
	_check(sim.tower_stats("tower", 3)["dmg"] > sim.tower_stats("tower", 1)["dmg"], "ulepszenie zwiększa obrażenia")


func _test_income() -> void:
	var sim := Sim.new(1, 1)
	sim.gold = 1000
	_check(is_equal_approx(sim.income(), Cfg.PASSIVE_INCOME), "dochód bazowy")
	sim.build_extractor(1)
	sim.upgrade(sim.extractor_on(1))
	_check(is_equal_approx(sim.income(), Cfg.PASSIVE_INCOME + 4.0), "wydobywacz poz. 2 daje 4/s")
	sim.build_extractor(4)
	_check(is_equal_approx(sim.income(), Cfg.PASSIVE_INCOME + 4.0 + 2.5 * sim.richness[4]), "bogate złoże daje więcej")


func _test_splash() -> void:
	var sim := _empty_sim()
	sim.gold = 1000
	var lane := sim.lanes[1]
	var cell := sim.free_cell_near(lane.slot_at(400, 60))
	sim.build("cannon", cell)
	var spot := lane.point_at(lane.offset_of(cell))
	for i in 3:
		sim._spawn_unit(1, "grunt", 1, 1.0, 1)
	for i in 90:
		for u in sim.units:
			u.pos = spot + Vector2(u.id % 3 * 6, 0)  # stoją w miejscu
		sim.step(DT)
	var hurt := 0
	for u in sim.units:
		if u.hp < u.max_hp:
			hurt += 1
	_check(hurt + (3 - sim.units.size()) == 3, "pocisk armaty rani wszystkich w promieniu")


func _test_catapult_razes_tower() -> void:
	var sim := _empty_sim()
	var tower_pos := sim.enemy_slot_pos(0)
	sim._add_building(1, "tower", tower_pos)
	sim._spawn_unit(0, "catapult", 1, 1.0, 0)
	var cat: Sim.Unit = sim.units[0]
	var lane := sim.lanes[0]
	cat.s = lane.offset_of(tower_pos) - 180.0
	cat.pos = lane.slot_at(cat.s, 0.0)
	cat.max_hp = 1e6
	cat.hp = 1e6
	for i in 30 * 90:
		sim.step(DT)
		if sim.stats["towers_razed"] > 0:
			break
	_check(sim.stats["towers_razed"] == 1, "katapulta burzy wieżę wroga")


func _test_lane_following() -> void:
	for lv in Levels.ALL.size():
		for lane_i in 3:
			var sim := _empty_sim(lv)
			sim._spawn_unit(0, "soldier", 1, 1.0, lane_i)
			var u: Sim.Unit = sim.units[0]
			u.max_hp = 1e6
			u.hp = 1e6
			var lane := sim.lanes[lane_i]
			var worst := 0.0
			for i in 30 * 80:
				sim.step(DT)
				worst = maxf(worst, lane.distance_to(u.pos))
				if sim.base_hp[1] < Cfg.BASE_HP[1]:
					break
			var name := "%s/%s" % [Levels.ALL[lv]["name"], lane.name]
			_check(worst <= Cfg.PATH_HALF, "jednostka trzyma się ścieżki %s (max %.1f px)" % [name, worst])
			_check(sim.base_hp[1] < Cfg.BASE_HP[1], "jednostka dochodzi ścieżką %s do bazy wroga" % name)


## Na Serpentynie jednostka zepchnięta z pętli wraca na TĘ SAMĄ pętlę, nie przeskakuje.
func _test_rejoin_stays_on_loop() -> void:
	var sim := _empty_sim(Levels.index_of("serpentyna"))
	sim._spawn_unit(0, "soldier", 1, 1.0, 0)
	var u: Sim.Unit = sim.units[0]
	var lane := sim.lanes[0]
	u.s = 900.0
	u.lane_offset = 0.0
	# zepchnij prostopadle w stronę sąsiedniej pętli, tuż za połowę odstępu
	u.pos = lane.slot_at(u.s, 0.0) + lane.normal_at(u.s) * 45.0
	u.on_path = false
	var s_before := u.s
	for i in 30 * 2:
		sim.step(DT)
	_check(absf(u.s - s_before) < 200.0, "powrót na ścieżkę nie przeskakuje pętli (Δs %.0f)" % absf(u.s - s_before))


func _test_stance() -> void:
	var sim := _empty_sim()
	sim._spawn_unit(0, "soldier", 1, 1.0, 2)
	sim.set_stance("defend")
	for i in 30 * 20:
		sim.step(DT)
	var u: Sim.Unit = sim.units[0]
	_check(absf(u.s - sim._rally_s(u)) < 1.0, "w obronie jednostka stoi na linii zbiórki swojej ścieżki")
	sim.set_stance("attack")
	for i in 30 * 5:
		sim.step(DT)
	_check(u.s > sim.rally_s + 100, "w ataku jednostka maszeruje")


func _test_production_lane() -> void:
	var sim := _empty_sim()
	sim.gold = 1000
	var cell := sim.free_cell_near(Vector2(170, 330))
	sim.build("barracks", cell)
	var b := sim.building_at(cell, 0)
	_check(b.lane == sim.nearest_lane(cell), "domyślnie produkcja idzie najbliższą ścieżką")
	_check(sim.set_lane(b, 2), "zmiana ścieżki produkcji")
	_check(not sim.set_lane(b, 7), "nie ma ścieżki 7")
	b.timer = 100.0
	sim.step(DT)
	_check(sim.units.size() == 1 and sim.units[0].lane == 2, "jednostka wychodzi na wybraną ścieżkę")


func _test_wave_lanes() -> void:
	var sim := Sim.new(1, 7)
	_check(sim.next_wave_lanes.size() == 1, "pierwsza fala idzie jedną ścieżką")
	var announced := sim.next_wave_lanes.duplicate()
	sim.wave_timer = 0.0
	sim.step(DT)
	var ok := true
	for e in sim.spawn_queue:
		ok = ok and announced.has(e["lane"])
	_check(ok, "fala przychodzi zapowiedzianymi ścieżkami")
	_check(sim._plan_lanes(Cfg.WAVE_SPLIT_2).size() == 2, "od WAVE_SPLIT_2 fala dzieli się na 2 ścieżki")
	_check(sim._plan_lanes(Cfg.WAVE_SPLIT_3).size() == 3, "od WAVE_SPLIT_3 fala idzie wszystkimi ścieżkami")


## Mocno bronione ścieżki 0 i 1 → fala najczęściej idzie ścieżką 2.
func _test_smart_lane_choice() -> void:
	var sim := _empty_sim()
	sim.gold = 1e6
	for lane_i in 2:
		for s in [300.0, 380.0, 460.0]:
			# poz. 1: zasięg sięga tylko „swojej" ścieżki (poz. 3 dosięgnąłby też trzeciej)
			sim.build("tower", sim.free_cell_near(sim.lanes[lane_i].slot_at(s, 70.0 if lane_i == 1 else -70.0), 120))
	_check(sim.lane_defense(0) > 50 and sim.lane_defense(1) > 50 and sim.lane_defense(2) < 1, "obrona liczona per ścieżka")
	var weak := 0
	for i in 300:
		if sim._plan_lanes(1)[0] == 2:
			weak += 1
	_check(weak > 200, "wróg zwykle wybiera słabo bronioną ścieżkę (%d/300, oczekiwane ~237)" % weak)


func _test_enemies_hit_buildings_and_regen() -> void:
	var sim := _empty_sim()
	sim.gold = 1000
	sim.build_extractor(4)  # sporne złoże przy Północy
	var ex := sim.extractor_on(4)
	var lane := sim.lanes[0]
	var near_s := lane.offset_of(ex.pos)
	sim._spawn_unit(1, "brute", 1, 1.0, 0)
	var ogre: Sim.Unit = sim.units[0]
	ogre.s = near_s + 120.0
	ogre.pos = lane.slot_at(ogre.s, 0.0)
	ogre.lane_offset = 0.0
	for i in 30 * 8:
		sim.step(DT)
	_check(ex.hp < ex.max_hp, "wróg przechodzący ścieżką atakuje wydobywacz przy niej")
	ogre.hp = 0.0
	sim.step(DT)
	var damaged := ex.hp
	for i in 30 * 12:
		sim.step(DT)
	_check(not sim.is_alive(ex) or ex.hp > damaged, "budynek regeneruje się poza walką")


func _test_flying() -> void:
	var sim := _empty_sim()
	sim._spawn_unit(1, "bat", 1, 1.0, 0)
	var bat: Sim.Unit = sim.units[0]
	bat.max_hp = 1e6
	bat.hp = 1e6
	sim._spawn_unit(0, "soldier", 1, 1.0, 1)
	var guard: Sim.Unit = sim.units[1]
	guard.max_hp = 1e6
	guard.hp = 1e6
	sim.set_stance("defend")
	var worst_off_line := 0.0
	var line_dir := (sim.p_base - sim.e_base).normalized()
	for i in 30 * 40:
		sim.step(DT)
		var rel := bat.pos - sim.e_base
		worst_off_line = maxf(worst_off_line, absf(rel.cross(line_dir)))
		if sim.base_hp[0] < Cfg.BASE_HP[0]:
			break
	_check(sim.base_hp[0] < Cfg.BASE_HP[0], "nietoperz dolatuje do bazy i ją atakuje")
	_check(worst_off_line < 40.0, "nietoperz leci na skróty, nie ścieżką")
	_check(is_equal_approx(bat.hp, bat.max_hp) or bat.hp < bat.max_hp, "sanity")
	var arrows := Sim.new(1, 1)
	var cannons := Sim.new(1, 1)
	for s in [arrows, cannons]:
		s.buildings = s.buildings.filter(func(b: Sim.Building) -> bool: return b.kind == "basegun" and b.team == 1)
		s.wave_timer = INF
		s.gold = 1000
	arrows.build("tower", arrows.free_cell_near(Vector2(400, 450)))
	cannons.build("cannon", cannons.free_cell_near(Vector2(400, 450)))
	for s in [arrows, cannons]:
		s._spawn_unit(1, "bat", 1, 1.0, 1)
		s.units[0].pos = Vector2(520, 450)
		s.units[0].max_hp = 1e6
		s.units[0].hp = 1e6
		for i in 30 * 4:
			s.step(DT)
	_check(arrows.units[0].hp < 1e6, "wieża (strzały) trafia nietoperza")
	_check(cannons.units.is_empty() or is_equal_approx(cannons.units[0].hp, 1e6), "armata nie trafia latających")


func _test_armor() -> void:
	var sim := _empty_sim()
	sim._spawn_unit(1, "shield", 1, 1.0, 1)
	sim._spawn_unit(1, "grunt", 1, 1.0, 1)
	var shield: Sim.Unit = sim.units[0]
	var grunt: Sim.Unit = sim.units[1]
	sim._damage_unit(shield, 10.0, "arrow")
	sim._damage_unit(grunt, 10.0, "arrow")
	_check(is_equal_approx(shield.max_hp - shield.hp, 10.0 * (1.0 - Cfg.UNITS["shield"]["armor"])), "pancerz blokuje część strzał")
	_check(is_equal_approx(grunt.max_hp - grunt.hp, 10.0), "bez pancerza strzała bije w pełni")
	var before := shield.hp
	sim._damage_unit(shield, 10.0, "cannonball")
	_check(is_equal_approx(before - shield.hp, 10.0), "armata ignoruje pancerz")


func _test_frost_slows() -> void:
	var moved: Array[float] = []
	for frosted in [false, true]:
		var sim := _empty_sim()
		sim.gold = 1000
		if frosted:
			sim.build("frost", sim.free_cell_near(sim.lanes[1].slot_at(420, 70)))
		sim._spawn_unit(1, "grunt", 1, 1.0, 1)
		var g: Sim.Unit = sim.units[0]
		g.max_hp = 1e6
		g.hp = 1e6
		g.s = 560.0
		g.pos = sim.lanes[1].slot_at(g.s, g.lane_offset)
		for i in 30 * 4:
			sim.step(DT)
		moved.append(560.0 - g.s)
	_check(moved[1] < moved[0] * 0.8, "mróz spowalnia (%.0f vs %.0f px)" % [moved[1], moved[0]])


func _test_abilities() -> void:
	var sim := _empty_sim()
	var spot := sim.lanes[1].point_at(700)
	for i in 4:
		sim._spawn_unit(1, "grunt", 1, 1.0, 1)
		sim.units[i].pos = spot + Vector2(i * 8, 0)
	_check(sim.use_ability("arrows", spot), "Deszcz strzał użyty")
	_check(not sim.use_ability("arrows", spot), "Deszcz strzał ma cooldown")
	for i in 30 * 2:
		for u in sim.units:
			u.pos = spot + Vector2(u.id % 4 * 8, 0)
		sim.step(DT)
	_check(sim.army_size(1) == 0, "trzy salwy zabijają orki w promieniu")

	_check(not sim.use_ability("levy", Vector2(300, 60)), "Pobór tylko przy ścieżce")
	_check(not sim.use_ability("levy", sim.lanes[1].point_at(sim.lanes[1].length - 100)), "Pobór tylko na swojej połowie")
	var at := sim.lanes[2].point_at(400)
	_check(sim.use_ability("levy", at), "Pobór przy ścieżce")
	_check(sim.army_size(0) == Cfg.ABILITIES["levy"]["count"], "Pobór wystawia oddział")
	_check(sim.units[0].lane == 2 and absf(sim.units[0].s - 400.0) < 60.0, "posiłki stają na wskazanej ścieżce")

	sim.gold = 1000
	sim.build("tower", sim.free_cell_near(Vector2(300, 330)))
	var t: Sim.Building = sim.buildings[-1]
	t.hp = 10.0
	sim.base_hp[0] = 100.0
	_check(sim.use_ability("repair"), "Naprawa użyta")
	_check(t.hp > 100.0 and sim.base_hp[0] > 100.0, "Naprawa leczy budynki i bazę")


func _test_progress() -> void:
	Progress.reset_cache()
	_check(Progress.best("x_test", 1) < 0, "brak rekordu na starcie")
	_check(Progress.record_win("x_test", 1, 300.0), "pierwsza wygrana to rekord")
	_check(not Progress.record_win("x_test", 1, 400.0), "wolniejsza wygrana nie jest rekordem")
	_check(Progress.record_win("x_test", 1, 250.0), "szybsza wygrana to rekord")
	Progress.reset_cache()  # wymuś odczyt z pliku
	_check(is_equal_approx(Progress.best("x_test", 1), 250.0), "rekord przetrwał zapis")
	_check(Progress.stars("x_test") == 1, "gwiazdka za wygraną trudność")


## Limity populacji: bez nich w długiej partii jednostek przybywało bez końca.
func _test_population_caps() -> void:
	var sim := _empty_sim()
	sim.gold = 1e6
	for i in 8:
		sim.build("barracks", sim.free_cell_near(Vector2(170, 330), 400))
	sim.base_hp = [1e9, 1e9]
	sim.set_stance("defend")  # stoją w szyku — nikt nie ginie, liczy się tylko limit
	for i in 30 * 300:  # 8 koszar × ~0,14 jedn./s → limit po ~180 s
		sim.step(DT)
	_check(sim.army_size(0) == Cfg.MAX_ARMY, "armia gracza zatrzymuje się na limicie (%d)" % sim.army_size(0))
	var waiting := 0
	for b in sim.buildings:
		if Cfg.is_production(b.kind) and b.timer >= sim.production_period(b.kind, b.level):
			waiting += 1
	_check(waiting > 0, "na limicie budynki czekają z gotową jednostką")
	_check(not sim.use_ability("levy", sim.lanes[1].point_at(300)), "Pobór nie przekracza limitu armii")

	var foe := Sim.new(1, 3)
	foe.buildings = foe.buildings.filter(func(b: Sim.Building) -> bool: return b.kind == "basegun" and b.team == 1)
	foe.base_hp = [1e9, 1e9]
	foe.wave = 40
	foe.wave_timer = 0.0
	var most := 0
	for i in 30 * 240:
		foe.step(DT)
		most = maxi(most, foe.army_size(1))
		_check(foe.spawn_queue.size() <= Cfg.MAX_SPAWN_QUEUE, "kolejka wroga ma limit")
	_check(most <= Cfg.MAX_ENEMIES, "wrogów na mapie nigdy więcej niż limit (%d)" % most)
	_check(most >= Cfg.MAX_ENEMIES - 5, "wróg dochodzi do limitu w późnej grze (%d)" % most)


func _test_wave_composition() -> void:
	_check(Cfg.wave_composition(1).size() == 3, "fala 1 = 3 orki")
	_check(Cfg.wave_composition(Cfg.BOSS_EVERY).has("warlord"), "boss co BOSS_EVERY fal")
	_check(not Cfg.wave_composition(Cfg.BOSS_EVERY - 1).has("warlord"), "brak bossa poza jego falą")
	_check(Cfg.wave_composition(6).has("bat") and Cfg.wave_composition(6).has("shield"), "od fal 4–5 nietoperze i tarczownicy")
	_check(not Cfg.wave_composition(3).has("bat"), "na początku bez nietoperzy")


## Sim bez wież wroga i bez fal — czysta scena do testów mechanik.
func _empty_sim(lv := 0) -> Sim:
	var sim := Sim.new(1, 1, lv)
	sim.buildings = sim.buildings.filter(func(b: Sim.Building) -> bool: return b.kind == "basegun")
	sim.wave_timer = INF
	return sim


func _check(ok: bool, what: String) -> void:
	if ok:
		return
	failures += 1
	push_error("FAIL: " + what)
	print("  FAIL: ", what)
