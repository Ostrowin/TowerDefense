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

## Kontrakt regresji (D8): gra bez dowódcy daje dokładnie te mecze botów co tabela wzorcowa.
## Tabelę nadpisuje się wyłącznie świadomie: `... bot_test.gd -- --write-baseline` (po zamierzonej zmianie balansu).
const BASELINE_PATH := "res://tests/bot_baseline.txt"

var failures := 0
var rows: Array[String] = []
var level_times: Array[int] = []
var game_mode := "battle"  ## `--mode survival` w `--balance` (T15)  ## czasy awansów dowódcy w bieżącym meczu (raport)


func _init() -> void:
	Progress.path = "user://test_progress.cfg"
	Progress.reset_cache()
	var args := OS.get_cmdline_user_args()
	if args.has("--balance"):
		# opcjonalnie: --maps 0,2 --diffs 1,2 --bot mass (np. żeby puścić kilka procesów równolegle)
		var maps := _int_list(args, "--maps", Levels.ALL.size())
		var diffs := _int_list(args, "--diffs", Cfg.DIFFICULTIES.size())
		var bot := args[args.find("--bot") + 1] if args.has("--bot") else "balanced"
		var commander := args[args.find("--commander") + 1] if args.has("--commander") else ""
		game_mode = args[args.find("--mode") + 1] if args.has("--mode") else "battle"
		_print_header()
		for lv in maps:
			for d in diffs:
				_report(lv, d, bot, commander)
		quit()
		return

	print("== testy mechanik ==")
	for lv in Levels.ALL.size():
		_test_map_layout(lv)
		_test_bridges(lv)
		_test_navigation(lv)
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
	_test_abilities_both_teams()
	_test_commander_data()
	_test_hero()
	_test_effect_kinds()
	_test_burrow()
	_test_gibbon_kinds()
	_test_hyena_boar_kinds()
	_test_hero_level()
	_test_survival()
	_test_daily()
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
		_compare_baseline(args.has("--write-baseline"))
		# R11: bot balanced z każdym grywalnym dowódcą wygrywa Normalny na każdej mapie (asercja
		# w _report). Łatwy i Trudny — `--balance --commander <id>`, żeby pełny test nie rósł z dowódcami.
		print("\n== mecze botów z dowódcą (Normalny) ==")
		_print_header()
		for commander in Cfg.COMMANDER_ORDER:
			if commander != "veteran" and Cfg.commander_ready(commander):
				for lv in Levels.ALL.size():
					_report(lv, 1, "balanced", commander)

	print("\n%s" % ("OK" if failures == 0 else "BŁĘDY: %d" % failures))
	quit(1 if failures > 0 else 0)


## Porównuje wiersze meczów z tabelą wzorcową (albo ją zapisuje przy --write-baseline).
func _compare_baseline(write: bool) -> void:
	if write:
		var f := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
		f.store_string("\n".join(rows) + "\n")
		print("\nzapisano tabelę wzorcową: ", BASELINE_PATH)
		return
	if not FileAccess.file_exists(BASELINE_PATH):
		_check(false, "brak tabeli wzorcowej %s (--write-baseline)" % BASELINE_PATH)
		return
	var expected := FileAccess.get_file_as_string(BASELINE_PATH).strip_edges().split("\n")
	_check(expected.size() == rows.size(), "tabela wzorcowa: %d wierszy, mecze: %d" % [expected.size(), rows.size()])
	for i in mini(expected.size(), rows.size()):
		if expected[i].strip_edges() != rows[i].strip_edges():
			_check(false, "mecz różni się od wzorca:\n    było:   %s\n    jest:   %s" % [expected[i], rows[i]])


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


func _report(lv: int, d: int, strategy: String, commander := "") -> void:
	level_times.clear()
	var r := _play(lv, d, strategy, commander)
	var row := "%-11s %-9s %-9s %-9s %5ds %5d %6d %6d %6d %8d" % [
		Levels.ALL[lv]["name"], Cfg.DIFFICULTIES[d]["name"], strategy, ["przegrana", "remis", "WYGRANA"][r.result + 1],
		int(r.elapsed), r.wave, r.stats["kills"], r.stats["units_made"], r.stats["towers_razed"], r.stats["buildings_lost"]]
	if commander == "":
		rows.append(row)  # do tabeli wzorcowej tylko gra bez dowódcy (D8)
	else:
		row += "   %s: umiejętności %d, zgonów %d, XP %d, awanse %s" % [commander, r.stats["abilities_used"], r.stats.get("hero_deaths", 0), int(r.hero().xp),
			"/".join(level_times.map(func(t: int) -> String: return "%ds" % t)) if not level_times.is_empty() else "—"]
	print(row)
	var where := "%s/%s" % [Levels.ALL[lv]["name"], Cfg.DIFFICULTIES[d]["name"]]
	if strategy == "idle":
		_check(r.result == -1, "bezczynny gracz musi przegrać (%s)" % where)
	if r.mode == "survival":
		# przetrwanie: forteca stoi, partia kończy się upadkiem bazy gracza — wynik to fala
		_check(r.result == -1 and r.base_hp[1] == Cfg.BASE_HP[1], "przetrwanie kończy się porażką, forteca cała (%s)" % where)
	elif strategy == "balanced" and d <= 1:
		_check(r.result == 1, "bot balanced powinien wygrać (%s)" % where)
	if strategy == "balanced" or strategy == "mass":
		_check(r.result != 0, "partia musi się rozstrzygnąć w %d min (%s, %s)" % [MAX_TIME / 60.0, where, strategy])


# ================================================================ bot

func _play(lv: int, difficulty: int, strategy: String, commander := "") -> Sim:
	var sim := Sim.new(difficulty, 1234, lv, commander, game_mode)
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
		if sim.hero() != null:
			_hero_bot(sim, strategy)
		else:
			_use_abilities(sim)
		_set_stance(sim, strategy)
	return sim


# ---------------------------------------------------------------- bot dowódcy (R9)

## Dowódca bota: balanced/mass — stoi na ścieżce następnej fali na linii zbiórki, przy HP < 30%
## wraca pod bazę; turtle — zawsze pod bazą. Umiejętności według tabeli R9 (po typie efektu).
func _hero_bot(sim: Sim, strategy: String) -> void:
	var h := sim.hero()
	if not sim.hero_alive():
		_cast_racial(sim)
		return
	var post := sim._hero_spawn_pos(0)
	if strategy != "turtle" and h.hp >= h.max_hp * 0.3:
		var lane := sim.lanes[sim.next_wave_lanes[0]]
		post = lane.point_at(sim.rally_s)
		# w natarciu: tuż za czołem własnej armii na ścieżce natarcia (tam jest walka)
		if sim.stance == "attack":
			var front := -1.0
			for u in sim.units:
				if u.team == 0 and u.lane == PUSH_LANE and not u.is_hero and not u.flying:
					front = maxf(front, u.s)
			if front > sim.rally_s:
				post = sim.lanes[PUSH_LANE].point_at(front - 50.0)
	if h.post.distance_to(post) > 40.0 and h.state != "march":
		sim.order_hero(post)
	for a in sim.ability_order[0]:
		if sim.ability_ready(a) and not Cfg.RACIAL.values().has(a):
			_cast_by_rules(sim, a)
	_cast_racial(sim)
	# awans: bot bierze „moc”, jeśli jest w ofercie, inaczej pierwszą opcję
	if not sim.hero_offers[0].is_empty():
		var offer: Array = sim.hero_offers[0][0]
		sim.choose_upgrade(1 if offer[1]["kind"] == "power" and offer[0]["kind"] != "power" else 0)
		level_times.append(int(sim.elapsed))


## Umiejętność rasy: Podkop, gdy na jednej ścieżce idzie w natarciu ≥ 6 własnych jednostek.
func _cast_racial(sim: Sim) -> void:
	var racial := ""
	for a in sim.ability_order[0]:
		if Cfg.RACIAL.values().has(a):
			racial = a
	if racial == "" or not sim.ability_ready(racial) or sim.stance != "attack":
		return
	var per_lane := {}
	for u in sim.units:
		if u.team == 0 and not u.flying and not u.is_hero and u.burrow <= 0.0:
			per_lane[u.lane] = per_lane.get(u.lane, 0) + 1
	for li in per_lane:
		if per_lane[li] >= 6:
			sim.use_ability(racial, sim.lanes[li].point_at(sim.lanes[li].length / 2.0))
			return


## R9: kiedy i gdzie rzucić umiejętność danego typu (wszystko w zasięgu od dowódcy).
func _cast_by_rules(sim: Sim, a: String) -> void:
	var cfg: Dictionary = Cfg.ABILITIES[a]
	var h := sim.hero()
	var reach: float = cfg["cast_range"] if cfg["cast_range"] > 0.0 else 1e9
	var foes: Array[Sim.Unit] = []
	for u in sim.units:
		if u.team == 1 and u.hp > 0 and u.pos.distance_to(h.pos) <= reach:
			foes.append(u)
	match cfg["kind"]:
		"pull":
			var big: Sim.Unit = null
			for u in foes:
				if u.hp >= 150.0 and not u.flying and u.kind != "warlord" and (big == null or u.hp > big.hp):
					big = u
			if big != null and h.hp >= h.max_hp * 0.5:
				sim.use_ability(a, big.pos)
		"taunt":
			var close := foes.filter(func(u: Sim.Unit) -> bool: return not u.flying and u.pos.distance_to(h.pos) <= cfg["radius"])
			if close.size() >= 3 and h.hp >= h.max_hp * 0.5:
				sim.use_ability(a)
		"leap":
			if h.hp < h.max_hp * 0.5:
				return
			for u in foes:
				var n := 0
				for o in foes:
					if o.pos.distance_to(u.pos) <= cfg["radius"]:
						n += 1
				if n >= 3 and sim.ability_target_ok(a, u.pos):
					sim.use_ability(a, u.pos)
					return
		"strike", "line", "repel", "weaken", "raise_dead":
			var r: float = cfg.get("radius", 60.0)
			if not cfg["target"]:
				r = cfg["radius"]  # „wokół siebie" — grupa musi stać przy dowódcy
				foes.assign(foes.filter(func(u: Sim.Unit) -> bool: return u.pos.distance_to(h.pos) <= r))
			var best := Vector2.INF
			var best_n := 2
			for u in foes:
				var n := 0
				for o in foes:
					if o.pos.distance_to(u.pos) <= r:
						n += 1
				if n > best_n:
					best_n = n
					best = u.pos
			if best != Vector2.INF:
				sim.use_ability(a, best if cfg["target"] else Vector2.ZERO)
		"zone":
			# na ścieżce 60 px przed czołem grupy (czoło = wróg najbliżej bazy gracza)
			var lead: Sim.Unit = null
			for u in foes:
				if not u.flying and (lead == null or u.s < lead.s):
					lead = u
			if lead != null:
				sim.use_ability(a, sim.lanes[lead.lane].point_at(lead.s - 60.0))
		"summon_building":
			if foes.is_empty():
				return
			for b in sim.buildings:
				if b.team == 0 and Cfg.is_shooter(b.kind) and b.pos.distance_to(h.pos) < 150.0:
					return
			var target := foes[0].pos
			var best := Vector2.INF
			for dx in range(-4, 5):
				for dy in range(-4, 5):
					var c := Cfg.snap(h.pos + Vector2(dx, dy) * Cfg.GRID)
					if sim.ability_target_ok(a, c) and (best == Vector2.INF or c.distance_to(target) < best.distance_to(target)):
						best = c
			if best != Vector2.INF:
				sim.use_ability(a, best)
		"summon_units":
			var ground := foes.filter(func(u: Sim.Unit) -> bool: return not u.flying)
			if ground.size() >= 3:
				var u: Sim.Unit = ground[0]
				sim.use_ability(a, sim.lanes[u.lane].point_at(maxf(u.s - 60.0, 80.0)))
		"buff":
			var own := 0
			for u in sim.units:
				if u.team == 0 and not u.is_hero and u.pos.distance_to(h.pos) <= maxf(cfg.get("radius", 120.0), 120.0):
					own += 1
			if own >= 4 and not foes.is_empty():
				sim.use_ability(a, h.pos)
		"execute":
			var big: Sim.Unit = null
			for u in foes:
				if u.hp >= 150.0 and (big == null or u.hp > big.hp):
					big = u
			if big != null:
				sim.use_ability(a, big.pos)
		"demolish":
			var near: Sim.Building = null
			for b in sim.buildings:
				if b.team == 1 and b.kind != "basegun" and b.pos.distance_to(h.pos) <= reach:
					if near == null or b.pos.distance_to(h.pos) < near.pos.distance_to(h.pos):
						near = b
			if near != null:
				sim.use_ability(a, near.pos)
		"global":
			if sim.base_hp[0] < Cfg.BASE_HP[0] * 0.6:
				sim.use_ability(a)


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


## Mosty liczy Sim (widok z nich rysuje, nawigacja dowódcy z nich korzysta).
func _test_bridges(lv: int) -> void:
	var sim := Sim.new(1, 1, lv)
	var name: String = Levels.ALL[lv]["name"]
	if sim.river == null:
		_check(sim.bridges.is_empty(), "%s: bez rzeki nie ma mostów" % name)
		return
	for li in sim.lanes.size():
		var own := sim.bridges.filter(func(br: Dictionary) -> bool: return br["lane"] == li)
		_check(not own.is_empty(), "%s: ścieżka %s przechodzi przez rzekę po moście" % [name, sim.lanes[li].name])
	for br in sim.bridges:
		var lane := sim.lanes[br["lane"]]
		var mid := lane.point_at((br["s0"] + br["s1"]) / 2.0)
		_check(sim.river_distance(mid) < Cfg.RIVER_HALF, "%s: środek mostu na %s leży nad wodą" % [name, lane.name])
		_check(br["s1"] - br["s0"] >= Cfg.RIVER_HALF * 2, "%s: most na %s przykrywa całą szerokość rzeki" % [name, lane.name])


## Trasa dowódcy: żaden odcinek nie wchodzi w wodę poza mostem, cel na wodzie → najbliższy ląd,
## mapa bez rzeki → prosto.
func _test_navigation(lv: int) -> void:
	var sim := Sim.new(1, 1, lv)
	var name: String = Levels.ALL[lv]["name"]
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 11 + lv
	var leaks := 0
	var bad_ends := 0
	for i in 40:
		var a := _land_point(sim, rnd)
		var b := Vector2(rnd.randf_range(0, sim.size.x), rnd.randf_range(0, sim.size.y))
		var path := sim.path_to(a, b)
		if path[0].distance_to(a) > 0.01:
			bad_ends += 1
		if sim.river_distance(path[-1]) < Cfg.RIVER_HALF and not _on_bridge(sim, path[-1]):
			bad_ends += 1
		for k in path.size() - 1:
			var n := ceili(path[k].distance_to(path[k + 1]) / 5.0)
			for j in n + 1:
				var p := path[k].lerp(path[k + 1], float(j) / maxi(n, 1))
				if sim.river_distance(p) < Cfg.RIVER_HALF and not _on_bridge(sim, p):
					leaks += 1
	_check(leaks == 0, "%s: trasy dowódcy nie wchodzą w wodę poza mostem (%d próbek w wodzie)" % [name, leaks])
	_check(bad_ends == 0, "%s: trasa zaczyna się w miejscu dowódcy i kończy na lądzie (%d złych)" % [name, bad_ends])
	if sim.river == null:
		var straight := sim.path_to(Vector2(200, 450), Vector2(1400, 450))
		_check(straight.size() == 2, "%s: bez rzeki trasa jest prosta (%d punktów)" % [name, straight.size()])
		return
	# przez rzekę: trasa istnieje, dochodzi do celu i używa mostu
	var across := sim.path_to(Vector2(300, 450), Vector2(1300, 450))
	_check(across[-1].distance_to(Vector2(1300, 450)) < 1.0, "%s: trasa przez rzekę dochodzi do celu" % name)
	var used := false
	for k in across.size() - 1:
		for j in 21:
			used = used or _on_bridge(sim, across[k].lerp(across[k + 1], j / 20.0))
	_check(used, "%s: trasa przez rzekę prowadzi mostem" % name)
	# cel na środku rzeki, z dala od mostów → trasa kończy się na brzegu
	var wet := Vector2.INF
	for k in 50:
		var q := sim.river.sample_baked(sim.river.get_baked_length() * k / 50.0)
		if Rect2(Vector2.ZERO, sim.size).has_point(q) and not _on_bridge(sim, q) and _lane_gap(sim, q) > 120.0:
			wet = q
			break
	if wet != Vector2.INF:
		var shore := sim.path_to(Vector2(300, 450), wet)
		_check(sim.river_distance(shore[-1]) >= Cfg.RIVER_HALF, "%s: cel na wodzie → dowódca staje na brzegu" % name)


func _land_point(sim: Sim, rnd: RandomNumberGenerator) -> Vector2:
	while true:
		var p := Vector2(rnd.randf_range(0, sim.size.x), rnd.randf_range(0, sim.size.y))
		if sim.river_distance(p) >= Cfg.RIVER_HALF + Sim.NAV_CLEARANCE:
			return p
	return Vector2.ZERO


func _on_bridge(sim: Sim, p: Vector2) -> bool:
	for br in sim.bridges:
		var lane := sim.lanes[br["lane"]]
		var off := lane.offset_of(p)
		if off >= br["s0"] - 40.0 and off <= br["s1"] + 40.0 and lane.point_at(off).distance_to(p) <= Cfg.PATH_HALF + 6.0:
			return true
	return false


func _lane_gap(sim: Sim, p: Vector2) -> float:
	var best := INF
	for lane in sim.lanes:
		best = minf(best, lane.distance_to(p))
	return best


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


## Typy efektów działają dla obu drużyn i trafiają tylko we właściwą (pod dowódców i bossa rywala).
func _test_abilities_both_teams() -> void:
	var sim := _empty_sim()
	var spot := sim.lanes[1].point_at(700)
	sim._spawn_unit(0, "soldier", 1, 1.0, 1)
	sim._spawn_unit(1, "grunt", 1, 1.0, 1)
	var mine: Sim.Unit = sim.units[0]
	var foe: Sim.Unit = sim.units[1]
	_check(sim.use_ability("arrows", spot, 1), "wróg rzuca salwę (strike)")
	_check(sim.ability_ready("arrows", 0), "odnowienie wroga nie blokuje umiejętności gracza")
	_check(sim.stats["abilities_used"] == 0, "umiejętności wroga nie liczą się do statystyk gracza")
	mine.pos = spot
	foe.pos = spot
	for i in 30 * 2:
		sim._update_strikes(DT)  # same salwy — bez walki wręcz między tymi dwoma jednostkami
	_check(mine.hp < mine.max_hp and foe.hp == foe.max_hp, "salwa wroga rani tylko jednostki gracza")

	var own := sim.lanes[2].point_at(sim.lanes[2].length - 400)
	_check(not sim.use_ability("levy", sim.lanes[2].point_at(400), 1), "przywołanie wroga tylko na jego połowie")
	var before := sim.army_size(1)
	_check(sim.use_ability("levy", own, 1), "wróg przywołuje jednostki (summon_units)")
	_check(sim.army_size(1) == before + Cfg.ABILITIES["levy"]["count"], "przywołane jednostki należą do wroga")

	var t := sim._add_building(1, "tower", sim.enemy_slot_pos(0))
	t.hp = 10.0
	var mine_b := sim._add_building(0, "tower", sim.free_cell_near(Vector2(300, 330)))
	mine_b.hp = 10.0
	sim.base_hp = [100.0, 100.0]
	_check(sim.use_ability("repair", Vector2.ZERO, 1), "wróg używa naprawy (global)")
	_check(t.hp > 100.0 and sim.base_hp[1] > 100.0, "naprawa wroga leczy jego budynki i bazę")
	_check(mine_b.hp == 10.0 and sim.base_hp[0] == 100.0, "naprawa wroga nie leczy gracza")


## Dane dowódców (T4): spójne odwołania, 3 dowódców na grywalną rasę, zastępca, formuła odrodzenia.
func _test_commander_data() -> void:
	for id in Cfg.ABILITIES:
		var a: Dictionary = Cfg.ABILITIES[id]
		for key in ["name", "short", "kind", "cooldown", "target", "cast_range"]:
			_check(a.has(key), "umiejętność %s ma %s" % [id, key])
		if a["kind"] == "summon_units":
			_check(Cfg.UNITS.has(a["unit"]), "%s przywołuje znaną jednostkę" % id)
	_check(Cfg.COMMANDER_ORDER.size() == Cfg.COMMANDERS.size(), "każdy dowódca jest w COMMANDER_ORDER")
	for id in Cfg.COMMANDERS:
		var c: Dictionary = Cfg.COMMANDERS[id]
		_check(Cfg.COMMANDER_ORDER.has(id), "%s w kolejności menu" % id)
		for key in ["race", "name", "role", "hp", "dmg", "range", "cd", "speed", "r", "armor", "projectile", "anti_air"]:
			_check(c.has(key), "dowódca %s ma %s" % [id, key])
		_check(c["abilities"].size() == 3, "%s ma 3 umiejętności" % id)
		for a in Cfg.commander_abilities(id):
			_check(Cfg.ABILITIES.has(a), "%s: umiejętność %s istnieje" % [id, a])
	for race in Cfg.RACIAL:
		_check(Cfg.ABILITIES[Cfg.RACIAL[race]]["cast_range"] == 0.0, "umiejętność rasy %s bez zasięgu" % race)
	for i in Races.ALL.size():
		if not Races.ALL[i]["playable"]:
			continue
		var list := Races.commanders(i)
		var own := list.filter(func(c: String) -> bool: return Cfg.COMMANDERS[c]["race"] == Races.ALL[i]["id"])
		_check(own.size() == 3, "%s: 3 dowódców" % Races.ALL[i]["name"])
		_check(Races.racial(i) != "", "%s: umiejętność rasy" % Races.ALL[i]["name"])
		_check(list.any(Cfg.commander_ready), "%s: jest grywalny dowódca (albo Weteran)" % Races.ALL[i]["name"])
	_check(Cfg.commander_ready("veteran") and Cfg.commander_abilities("veteran") == Cfg.ABILITY_ORDER,
		"Weteran = dzisiejsze umiejętności, bez rasowej")
	_check(Cfg.commander_abilities("sapper") == ["minefield", "drill_turret", "demo_charge", "dig_in"], "pasek Sapera + Podkop")
	_check(Cfg.commander_respawn(0) == 20.0 and Cfg.commander_respawn(5) == 30.0 and Cfg.commander_respawn(50) == 40.0,
		"odrodzenie 20 s + 2 s/falę, maks. 40 s")
	var sim := Sim.new(1, 1, 0, "sapper")
	_check(sim.ability_cd[0].has("dig_in") and not sim.ability_cd[0].has("arrows"), "Sim z dowódcą: jego umiejętności")
	_check(sim.ability_cd[1].has("arrows"), "wróg bez dowódcy — dzisiejszy zestaw")
	_check(Sim.new(1, 1).ability_order[0] == Cfg.ABILITY_ORDER, "Sim bez dowódcy — dzisiejszy zestaw")


## Dowódca w Sim (T5, R4, D3): marsz przez most, walka na smyczy, śmierć i odrodzenie,
## cel dla wież/jednostek/obszaru, poza limitami i obroną ścieżek, zasięg rzucania.
func _test_hero() -> void:
	# marsz przez rzekę po moście, bez wchodzenia w wodę
	var lv := -1
	for i in Levels.ALL.size():
		if not Levels.ALL[i]["river"].is_empty():
			lv = i
			break
	var sim := _empty_sim(lv, "sapper")
	var h := sim.hero()
	_check(h != null and sim.units.has(h), "dowódca stoi na mapie od startu")
	_check(sim.army_size(0) == 0 and sim.team_count[0] == 0, "dowódca nie liczy się do armii")
	var br: Dictionary = sim.bridges[0]
	var lane: Sim.Lane = sim.lanes[br["lane"]]
	h.pos = lane.point_at(br["s0"] - 160.0)
	var goal := lane.point_at(br["s1"] + 160.0)
	_check(sim.order_hero(goal), "rozkaz marszu przyjęty")
	var wet := false
	for i in 30 * 30:
		sim.step(DT)
		wet = wet or not sim._nav_point_ok(h.pos)
		if h.state == "idle":
			break
	_check(h.state == "idle" and h.pos.distance_to(goal) < 5.0, "dowódca dochodzi za rzekę (%.0f px od celu)" % h.pos.distance_to(goal))
	_check(not wet, "dowódca przechodzi rzekę tylko po moście")

	# walka i powrót do punktu (smycz)
	sim = _empty_sim(0, "sapper")
	h = sim.hero()
	var post := sim.lanes[1].point_at(500)
	h.pos = post
	h.post = post
	sim.base_hp = [1e9, 1e9]
	sim._spawn_unit(1, "grunt", 1, 1.0, 1, 600)
	var foe: Sim.Unit = sim.units[-1]
	var far := 0.0
	for i in 30 * 20:
		sim.step(DT)
		far = maxf(far, h.pos.distance_to(post))
		if foe.hp <= 0 and h.state == "idle":
			break
	_check(foe.hp <= 0, "dowódca zabija wroga w pobliżu")
	_check(far <= Cfg.COMMANDER_LEASH + 1.0, "goni najdalej na smycz (%.0f px)" % far)
	_check(h.state == "idle" and h.pos.distance_to(post) < 2.0, "po walce wraca do punktu")
	# wróg poza smyczą — dowódca stoi
	sim._spawn_unit(1, "grunt", 1, 1.0, 1, 500 + 400)
	var lure: Sim.Unit = sim.units[-1]
	lure.base_speed = 0.0
	for i in 30 * 3:
		sim.step(DT)
	_check(h.pos.distance_to(post) < 2.0, "wróg daleko od punktu nie ściąga dowódcy")

	# D3: wieża, jednostka i obszar ranią i zabijają dowódcę
	for how in ["tower", "unit", "splash"]:
		sim = _empty_sim(0, "sapper")
		h = sim.hero()
		sim.base_hp = [1e9, 1e9]
		h.pos = sim.lanes[1].point_at(900)
		h.post = h.pos
		h.hp = 30.0
		match how:
			"tower":
				sim._add_building(1, "tower", h.pos + Vector2(0, 120))
			"unit":
				sim._spawn_unit(1, "brute", 1, 5.0, 1, 900)  # gruby — dowódca go nie zdąży zabić
			"splash":
				var s := sim._fire(1, "cannonball", h.pos + Vector2(100, 0), h.pos, 50.0, 55.0)
				s.target_pos = h.pos
		for i in 30 * 10:
			sim.step(DT)
			if h.state == "dead":
				break
		_check(h.state == "dead" and not sim.units.has(h), "dowódcę zabija: %s" % how)

	# śmierć → odrodzenie przy bazie z nietykalnością; umiejętności wyszarzone, rasowa działa
	sim = _empty_sim(0, "sniper")
	h = sim.hero()
	sim.wave = 5
	sim.trickle_timer = INF  # bez pojedynczych orków między falami
	sim._damage_unit(h, 1e6, "melee")
	_check(h.state == "dead" and is_equal_approx(h.respawn, Cfg.commander_respawn(5)), "po śmierci odlicza odrodzenie (30 s w fali 5)")
	_check(not sim.ability_ready("barrage") and sim.ability_ready("dig_in"), "umiejętności dowódcy wyszarzone, rasowa działa")
	_check(not sim.order_hero(sim.p_base), "martwy dowódca nie przyjmuje rozkazów")
	sim.ability_cd[0]["barrage"] = 5.0
	for i in 30 * 31:
		sim.step(DT)
	_check(h.state == "idle" and sim.units.has(h) and h.hp == h.max_hp, "dowódca odradza się z pełnym HP")
	_check(h.pos.distance_to(sim.p_base) < Cfg.BASE_R + 40.0, "odradza się przy bazie")
	_check(sim.ability_cd[0]["barrage"] == 0.0 and sim.ability_ready("barrage"), "odnowienie biegło w czasie śmierci")
	_check(h.invulnerable > 0.0, "po odrodzeniu nietykalny")
	var hp := h.hp
	sim._damage_unit(h, 50.0, "melee")
	_check(h.hp == hp, "nietykalny nie traci HP")

	# zasięg rzucania od dowódcy; bez celu (Ostrzał gracza) poza zasięgiem = odmowa
	var near := h.pos + Vector2(100, 0)
	var out := h.pos + Vector2(Cfg.ABILITIES["barrage"]["cast_range"] + 50.0, 0)
	_check(sim.ability_target_ok("barrage", near) and not sim.ability_target_ok("barrage", out), "zasięg rzucania liczony od dowódcy")

	# nie rusza limitów ani obrony ścieżek
	var plain := _empty_sim(0)
	sim = _empty_sim(0, "sapper")
	sim.hero().pos = sim.lanes[1].point_at(300)
	sim.step(DT)
	plain.step(DT)
	_check(sim.team_count[0] == 0 and sim.lane_defense(1) == plain.lane_defense(1), "dowódca poza limitem i obroną ścieżek")


## Nowe typy efektów (T6, R1): każdy rzucany przez obie drużyny trafia tylko we właściwą.
func _test_effect_kinds() -> void:
	for team in 2:
		var foe_t := 1 - team
		var who := "team %d" % team
		var spot: Vector2

		# zone: mina wybucha przy wejściu wroga, swojego nie rusza
		var sim := _fx_sim()
		spot = sim.lanes[1].point_at(700)
		_check(not sim.use_ability("minefield", sim.base_pos(foe_t) + Vector2(-60 if foe_t == 1 else 60, 0), team),
			"mina nie pod bazą przeciwnika (%s)" % who)
		_check(sim.use_ability("minefield", spot, team), "mina postawiona (%s)" % who)
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, 700)
		var mine: Sim.Unit = sim.units[-1]
		sim.step(DT)
		_check(sim.zones.size() == 1 and mine.hp == mine.max_hp, "własna jednostka nie odpala miny (%s)" % who)
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1, 700)
		var foe: Sim.Unit = sim.units[-1]
		foe.pos = spot
		sim.step(DT)
		sim.step(DT)
		_check(sim.zones.is_empty() and foe.hp <= 0, "mina wybucha pod wrogiem (%s)" % who)

		# zone tick: lawa rani co sekundę, znika po czasie
		sim = _fx_sim()
		spot = sim.lanes[1].point_at(700)
		sim._spawn_unit(foe_t, "brute", 1, 1.0, 1, 700)
		foe = sim.units[-1]
		foe.base_speed = 0.0
		foe.pos = spot
		_check(sim.use_ability("lava_pool", spot, team), "lawa (%s)" % who)
		for i in 30 * 3:
			sim.step(DT)
		var lost := foe.max_hp - foe.hp
		_check(lost >= Cfg.ABILITIES["lava_pool"]["dps"] * 3 - 1.0, "lawa rani co sekundę (%s, %.0f HP)" % [who, lost])
		for i in 30 * 10:
			sim.step(DT)
		_check(sim.zones.is_empty(), "strefa znika po czasie (%s)" % who)

		# summon_building: wieżyczka strzela we wroga, znika, nie da się jej sprzedać
		sim = _fx_sim()
		sim.base_hp = [1e9, 1e9]
		spot = sim.lanes[1].point_at(700) + Vector2(0, 80)
		var cell := Cfg.snap(spot)
		_check(sim.use_ability("drill_turret", spot, team), "wieżyczka postawiona (%s)" % who)
		var t: Sim.Building = sim.buildings[-1]
		_check(t.temporary and t.team == team and t.pos == cell, "budowla tymczasowa drużyny (%s)" % who)
		_check(not sim.use_ability("drill_turret", spot, team), "wieżyczka ma odnowienie (%s)" % who)
		sim.ability_cd[team]["drill_turret"] = 0.0
		_check(not sim.ability_target_ok("drill_turret", spot, team), "zajęte pole odrzucone (%s)" % who)
		_check(not sim.ability_target_ok("drill_turret", sim.lanes[1].point_at(700), team), "nie na ścieżce (%s)" % who)
		_check(sim.building_at(cell, team) == null and not sim.sell(t) and sim.upgrade_cost(t) < 0,
			"budowli nie da się zaznaczyć, sprzedać ani ulepszyć (%s)" % who)
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1, 700)
		foe = sim.units[-1]
		foe.base_speed = 0.0
		for i in 30 * 8:
			sim.step(DT)
		_check(foe.hp <= 0, "wieżyczka zabija wroga (%s)" % who)
		for i in 30 * 15:
			sim.step(DT)
		_check(not sim.buildings.has(t), "budowla znika po czasie (%s)" % who)
		_check(sim.stats["buildings_lost"] == 0 and sim.stats["towers_razed"] == 0, "zniknięcie nie liczy się do statystyk (%s)" % who)

		# buff: w promieniu tylko własne jednostki; szybkość rośnie, potem wraca
		sim = _fx_sim()
		spot = sim.lanes[1].point_at(700)
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, 700)
		var ally: Sim.Unit = sim.units[-1]
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1, 710)
		foe = sim.units[-1]
		_check(sim.use_ability("drumroll", spot, team), "werble (%s)" % who)
		_check(ally.attack_speed > 1.0 and foe.attack_speed == 1.0, "wzmocnienie tylko dla swoich (%s)" % who)
		sim.elapsed += Cfg.ABILITIES["drumroll"]["duration"] + 1.0
		sim._expire_buffs(ally)
		_check(ally.attack_speed == 1.0 and ally.buffs.is_empty(), "wzmocnienie wygasa (%s)" % who)
		# buff na ścieżkę i globalny (Pieśń: szybkość + obrażenia)
		sim._spawn_unit(team, "soldier", 1, 1.0, 2, 300)
		var other: Sim.Unit = sim.units[-1]
		_check(sim.use_ability("march_beat", sim.lanes[1].point_at(400), team), "rytm marszu (%s)" % who)
		_check(ally.speed_mult > 1.0 and other.speed_mult == 1.0, "wzmocnienie na ścieżce tylko na niej (%s)" % who)
		_check(sim.use_ability("song", Vector2.ZERO, team), "pieśń (%s)" % who)
		_check(other.speed_mult > 1.0 and other.dmg_mult > 1.0 and foe.dmg_mult == 1.0, "pieśń wzmacnia całą armię (%s)" % who)

		# line: przebicie rani wrogów na linii (także latających), swoich nie
		sim = _fx_sim()
		var from := sim.base_pos(team)
		var dir := (sim.base_pos(foe_t) - from).normalized()
		spot = from + dir * 200.0
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1)
		foe = sim.units[-1]
		foe.pos = spot
		sim._spawn_unit(foe_t, "bat", 1, 1.0, 1)
		var bat: Sim.Unit = sim.units[-1]
		bat.pos = from + dir * 120.0
		sim._spawn_unit(team, "soldier", 1, 1.0, 1)
		ally = sim.units[-1]
		ally.pos = from + dir * 160.0
		var aside: Sim.Unit
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1)
		aside = sim.units[-1]
		aside.pos = spot + dir.orthogonal() * 80.0
		_check(sim.use_ability("railshot", spot, team), "przebicie (%s)" % who)
		_check(foe.hp < foe.max_hp and bat.hp < bat.max_hp, "przebicie rani wrogów na linii i latających (%s)" % who)
		_check(ally.hp == ally.max_hp and aside.hp == aside.max_hp, "przebicie omija swoich i wrogów obok linii (%s)" % who)

		# execute: dobija najsilniejszego; Wódz odporny na dobicie
		sim = _fx_sim()
		spot = sim.lanes[1].point_at(700)
		sim._spawn_unit(foe_t, "brute", 1, 1.0, 1, 700)
		var big: Sim.Unit = sim.units[-1]
		big.pos = spot
		big.hp = big.max_hp * 0.5
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1, 700)
		var small: Sim.Unit = sim.units[-1]
		small.pos = spot
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, 700)
		ally = sim.units[-1]
		ally.pos = spot
		_check(sim.use_ability("snipe", spot, team), "strzał snajperski (%s)" % who)
		_check(big.hp <= 0 and small.hp == small.max_hp and ally.hp == ally.max_hp, "dobija najsilniejszego wroga (%s)" % who)
		sim._spawn_unit(foe_t, "warlord", 1, 1.0, 1, 700)
		var boss: Sim.Unit = sim.units[-1]
		boss.pos = spot
		boss.hp = boss.max_hp * 0.2
		sim.ability_cd[team]["snipe"] = 0.0
		var before := boss.hp
		sim.use_ability("snipe", spot, team)
		_check(boss.hp > 0 and is_equal_approx(before - boss.hp, Cfg.ABILITIES["snipe"]["dmg"]), "Wódz odporny na dobicie (%s)" % who)

		# demolish: ładunek w budynek wroga, nie w swój; bez budynku — odmowa
		sim = _fx_sim()
		var enemy_b := sim._add_building(foe_t, "tower", sim.lanes[1].point_at(700) + Vector2(0, 80))
		var own_b := sim._add_building(team, "tower", sim.lanes[1].point_at(500) + Vector2(0, 80))
		_check(not sim.use_ability("demo_charge", own_b.pos, team), "ładunek nie we własny budynek (%s)" % who)
		_check(sim.use_ability("demo_charge", enemy_b.pos, team), "ładunek burzący (%s)" % who)
		_check(enemy_b.hp < enemy_b.max_hp and own_b.hp == own_b.max_hp, "ładunek rani budynek wroga (%s)" % who)


## Podkop (`burrow`, T9): jednostki na ścieżce pod ziemią — nietykalne i niewidoczne dla wież
## i jednostek, idą szybciej naprzód, wynurzają się ze wstrząsem. Dla obu drużyn.
func _test_burrow() -> void:
	for team in 2:
		var foe_t := 1 - team
		var who := "team %d" % team
		var sim := _fx_sim()
		sim.base_hp = [1e9, 1e9]
		var s0 := 500.0 if team == 0 else sim.lanes[1].length - 500.0
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, s0)
		var digger: Sim.Unit = sim.units[-1]
		sim._spawn_unit(team, "soldier", 1, 1.0, 0, s0)
		var other_lane: Sim.Unit = sim.units[-1]
		var tower := sim._add_building(foe_t, "tower", sim.lanes[1].slot_at(s0 + (150.0 if team == 0 else -150.0), 70))
		_check(sim.use_ability("dig_in", digger.pos, team), "Podkop (%s)" % who)
		_check(digger.burrow > 0.0 and other_lane.burrow == 0.0, "pod ziemię schodzi tylko wskazana ścieżka (%s)" % who)
		var hp := digger.hp
		sim._damage_unit(digger, 50.0, "melee")
		_check(digger.hp == hp, "pod ziemią nietykalny (%s)" % who)
		var start_s := digger.s
		for i in 30 * 2:
			sim.step(DT)
			_check(sim._nearest_unit(team, tower.pos, 500.0, true) != digger, "wieża nie widzi jednostki pod ziemią (%s)" % who)
		_check(digger.hp == hp, "wieża nie rani pod ziemią (%s)" % who)
		var moved := absf(digger.s - start_s)
		_check(moved > Cfg.UNITS["soldier"]["speed"] * 2.0 * 1.1, "pod ziemią szybciej naprzód (%s, %.0f px)" % [who, moved])
		# wynurzenie: wstrząs rani wroga obok
		sim._spawn_unit(foe_t, "brute", 1, 1.0, 1)
		var victim: Sim.Unit = sim.units[-1]
		victim.base_speed = 0.0
		victim.s = digger.s
		victim.pos = digger.pos
		digger.burrow = 0.05
		sim.step(DT)
		sim.step(DT)
		_check(digger.burrow == 0.0 and victim.hp < victim.max_hp, "wynurzenie ze wstrząsem rani wrogów (%s)" % who)


## Typy gibonów (T11): ogłuszenie w salwie, przyciągnięcie, prowokacja, odrzut — dla obu drużyn.
func _test_gibbon_kinds() -> void:
	for team in 2:
		var foe_t := 1 - team
		var who := "team %d" % team
		var sim := _fx_sim()
		sim.base_hp = [1e9, 1e9]
		var lane: Sim.Lane = sim.lanes[1]
		var h := sim._make_hero(team, "iron_grip")
		sim.heroes[team] = h
		h.pos = lane.point_at(700)
		h.post = h.pos
		var fwd := 1.0 if team == 0 else -1.0  # „naprzód" dla rzucającego wzdłuż ścieżki

		# strike ze stun: Uderzenie o ziemię wokół dowódcy ogłusza
		sim._spawn_unit(foe_t, "brute", 1, 5.0, 1, 700 + 30 * fwd)
		var foe: Sim.Unit = sim.units[-1]
		_check(sim.use_ability("ground_slam", Vector2.ZERO, team), "uderzenie o ziemię (%s)" % who)
		sim.step(DT)
		_check(foe.stun > 0.0 and foe.hp < foe.max_hp, "uderzenie wokół dowódcy rani i ogłusza (%s)" % who)
		var stunned_at := foe.pos
		for i in 10:
			sim.step(DT)
		_check(foe.pos == stunned_at, "ogłuszony stoi (%s)" % who)
		foe.hp = 0.0

		# pull: najsilniejszy wróg w obszarze ląduje przy dowódcy; Wódz odporny
		sim = _fx_sim()
		h = sim._make_hero(team, "iron_grip")
		sim.heroes[team] = h
		h.pos = lane.point_at(700)
		var spot := lane.point_at(700 + 160 * fwd)
		_check(not sim.ability_target_ok("grip", spot, team), "chwyt bez celu — odmowa (%s)" % who)
		sim._spawn_unit(foe_t, "warlord", 1, 1.0, 1, 700 + 160 * fwd)
		_check(not sim.ability_target_ok("grip", spot, team), "Wódz odporny na chwyt (%s)" % who)
		sim._spawn_unit(foe_t, "brute", 1, 1.0, 1, 700 + 170 * fwd)
		foe = sim.units[-1]
		_check(sim.use_ability("grip", spot, team), "chwyt (%s)" % who)
		_check(foe.pos.distance_to(h.pos) < 40.0, "chwyt przyciąga wroga do dowódcy (%s)" % who)

		# taunt: wrogowie w promieniu idą na dowódcę, choć normalnie by go nie widzieli
		sim = _fx_sim()
		sim.base_hp = [1e9, 1e9]
		h = sim._make_hero(team, "iron_grip")
		sim.heroes[team] = h
		h.pos = lane.slot_at(700, 130)  # obok ścieżki, poza zasięgiem wzroku przechodzących
		h.post = h.pos
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1, 700)
		foe = sim.units[-1]
		foe.base_speed = 60.0
		var d0 := foe.pos.distance_to(h.pos)
		_check(sim.use_ability("war_roar", Vector2.ZERO, team), "ryk wojenny (%s)" % who)
		_check(foe.taunt > 0.0, "ryk prowokuje wrogów w promieniu (%s)" % who)
		for i in 30:
			sim.step(DT)
		_check(foe.pos.distance_to(h.pos) < d0 - 30.0, "sprowokowany idzie na dowódcę (%s)" % who)

		# repel: fala uderzeniowa cofa wrogów na linii wzdłuż ich ścieżki, swoich nie
		sim = _fx_sim()
		h = sim._make_hero(team, "wrecker")
		sim.heroes[team] = h
		h.pos = lane.point_at(700)
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1, 700 + 120 * fwd)
		foe = sim.units[-1]
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, 700 + 60 * fwd)
		var ally: Sim.Unit = sim.units[-1]
		var foe_s := foe.s
		var ally_s := ally.s
		_check(sim.use_ability("shockwave", foe.pos, team), "fala uderzeniowa (%s)" % who)
		_check((foe.s - foe_s) * fwd >= Cfg.ABILITIES["shockwave"]["distance"] - 1.0, "odrzut cofa wroga wzdłuż ścieżki (%s)" % who)
		_check(ally.s == ally_s and foe.hp < foe.max_hp, "odrzut omija swoich i rani wroga (%s)" % who)


## Typy hien i dzików (T11b): osłabienie, skok, wskrzeszenie, Padlina, krótko żyjące przywołania,
## odrzut przy pierwszym ciosie — dla obu drużyn.
func _test_hyena_boar_kinds() -> void:
	var river_lv := 0
	for i in Levels.ALL.size():
		if not Levels.ALL[i]["river"].is_empty():
			river_lv = i
	for team in 2:
		var foe_t := 1 - team
		var who := "team %d" % team
		var fwd := 1.0 if team == 0 else -1.0

		# weaken: wróg dostaje więcej obrażeń, swój nie
		var sim := _fx_sim()
		var lane: Sim.Lane = sim.lanes[1]
		sim._spawn_unit(foe_t, "brute", 1, 1.0, 1, 700)
		var foe: Sim.Unit = sim.units[-1]
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, 700)
		var ally: Sim.Unit = sim.units[-1]
		_check(sim.use_ability("curse", foe.pos, team), "klątwa (%s)" % who)
		_check(foe.vuln > 1.0 and ally.vuln == 1.0, "klątwa osłabia tylko wrogów (%s)" % who)
		var hp := foe.hp
		sim._damage_unit(foe, 10.0, "melee")
		_check(is_equal_approx(hp - foe.hp, 10.0 * Cfg.ABILITIES["curse"]["mult"]), "osłabiony dostaje więcej obrażeń (%s)" % who)

		# leap: dowódca skacze na ląd i rani przy lądowaniu; do rzeki — odmowa
		sim = _fx_sim(river_lv)
		lane = sim.lanes[1]
		var h := sim._make_hero(team, "cackle")
		sim.heroes[team] = h
		h.pos = lane.point_at(600)
		var land := lane.point_at(600 + 150 * fwd)
		sim._spawn_unit(foe_t, "brute", 1, 1.0, 1, 600 + 150 * fwd)
		foe = sim.units[-1]
		_check(sim.use_ability("pounce", land, team), "skok (%s)" % who)
		_check(h.pos == land and h.post == land, "dowódca ląduje w celu (%s)" % who)
		_check(foe.hp < foe.max_hp, "lądowanie rani wrogów (%s)" % who)
		var water := Vector2.INF  # woda z dala od mostów (na moście skakać wolno)
		for p in sim.river.get_baked_points():
			if Rect2(Vector2(200, 200), sim.size - Vector2(400, 400)).has_point(p) and _lane_gap(sim, p) > 80.0:
				water = p
				break
		h.pos = water + Vector2(150, 0)
		sim.ability_cd[team]["pounce"] = 0.0
		_check(not sim.ability_target_ok("pounce", water, team), "skok do rzeki — odmowa (%s)" % who)

		# raise_dead: wróg ginący w obszarze wstaje po naszej stronie
		sim = _fx_sim()
		lane = sim.lanes[1]
		var spot := lane.point_at(700)
		_check(sim.use_ability("raise", spot, team), "wskrzeszenie (%s)" % who)
		sim._spawn_unit(foe_t, "grunt", 1, 1.0, 1, 700)
		foe = sim.units[-1]
		var mine_before := sim.army_size(team)
		sim._damage_unit(foe, 1e6, "melee")
		sim.step(DT)
		_check(sim.army_size(team) == mine_before + 1 and sim.units[-1].kind == "grunt" and sim.units[-1].team == team,
			"poległy wróg wstaje po stronie rzucającego (%s)" % who)
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, 700)
		ally = sim.units[-1]
		var foes_before := sim.army_size(foe_t)
		sim._damage_unit(ally, 1e6, "melee")
		sim.step(DT)
		_check(sim.army_size(foe_t) == foes_before, "własny poległy nie wstaje u wroga (%s)" % who)

		# bounty_buff: Padlina podnosi nagrody gracza tylko wtedy, gdy rzuca ją gracz
		sim = _fx_sim()
		_check(sim.use_ability("carrion", Vector2.ZERO, team), "padlina (%s)" % who)
		sim._spawn_unit(1, "brute", 1, 1.0, 1, 700)
		var gold := sim.gold
		sim._damage_unit(sim.units[-1], 1e6, "melee")
		var expected: int = Cfg.UNITS["brute"]["bounty"]
		if team == 0:
			expected = roundi(expected * Cfg.ABILITIES["carrion"]["mult"])
		_check(is_equal_approx(sim.gold - gold, expected), "nagroda za zabicie: %d (%s)" % [expected, who])

		# summon_units z lifetime (Tabun) znika po czasie; Szarża — pierwszy cios odrzuca
		sim = _fx_sim()
		lane = sim.lanes[1]
		var own_s := 400.0 if team == 0 else lane.length - 400.0
		var n0 := sim.army_size(team)
		_check(sim.use_ability("herd", lane.point_at(own_s), team), "tabun (%s)" % who)
		_check(sim.army_size(team) > n0, "tabun przywołuje jednostki (%s)" % who)
		sim.elapsed += Cfg.ABILITIES["herd"]["lifetime"] + 0.5
		sim.step(DT)
		_check(sim.army_size(team) == n0, "tabun znika po czasie (%s)" % who)
		sim._spawn_unit(team, "soldier", 1, 1.0, 1, 700)
		ally = sim.units[-1]
		sim._spawn_unit(foe_t, "brute", 1, 5.0, 1, 700 + 25 * fwd)
		foe = sim.units[-1]
		_check(sim.use_ability("stampede", ally.pos, team), "szarża (%s)" % who)
		var s0 := foe.s
		sim._melee_hit(ally, foe)
		_check((foe.s - s0) * fwd > 30.0 and not ally.buffs.has("knockback"), "pierwszy cios odrzuca, potem już nie (%s)" % who)


## Awans dowódcy (T14): doświadczenie w pobliżu i za zabicie osobiste, progi, statystyki,
## oferta 2 ulepszeń, ulepszenie tylko dla swojej drużyny, doświadczenie po śmierci.
func _test_hero_level() -> void:
	var sim := _fx_sim()
	var h := sim._make_hero(0, "sapper")
	sim.heroes[0] = h
	h.pos = sim.lanes[1].point_at(700)
	var bounty: float = Cfg.UNITS["grunt"]["bounty"]
	sim._spawn_unit(1, "grunt", 1, 1.0, 1, 760)
	sim._damage_unit(sim.units[-1], 1e6, "arrow")
	_check(is_equal_approx(h.xp, bounty), "wróg ginący obok daje nagrodę jako doświadczenie")
	sim._spawn_unit(1, "grunt", 1, 1.0, 1, 1300)
	sim._damage_unit(sim.units[-1], 1e6, "arrow")
	_check(is_equal_approx(h.xp, bounty), "wróg ginący daleko nie daje doświadczenia")
	sim._spawn_unit(1, "grunt", 1, 1.0, 1, 1300)
	var far: Sim.Unit = sim.units[-1]
	far.hp = 1.0
	sim._melee_hit(h, far)
	_check(is_equal_approx(h.xp, bounty * (2.0 + Cfg.HERO_XP_OWN_BONUS)), "zabicie osobiste daje więcej (także z daleka)")
	var cast_xp := h.xp
	sim._spawn_unit(1, "grunt", 1, 1.0, 1, 1300)
	sim.units[-1].pos = h.pos + Vector2(100, 0)
	sim.units[-1].hp = 1.0
	sim.use_ability("minefield", h.pos + Vector2(100, 0))
	sim.step(DT)
	sim.step(DT)
	_check(h.xp - cast_xp >= bounty * (1.0 + Cfg.HERO_XP_OWN_BONUS) - 0.01, "zabicie umiejętnością dowódcy (mina) jest osobiste")

	var before_tower := h.xp
	var tower := sim._add_building(1, "tower", h.pos + Vector2(0, 120))
	sim._damage_building(tower, 1e6)
	_check(is_equal_approx(h.xp - before_tower, Cfg.TOWER_KILL_BOUNTY), "zburzona wieża obok daje doświadczenie")

	# awans: próg, statystyki, oferta 2 różnych ulepszeń
	var hp0 := h.max_hp
	sim._gain_xp(h, Cfg.HERO_XP[0])
	_check(h.hero_level == 2 and is_equal_approx(h.max_hp, hp0 * (1.0 + Cfg.HERO_STAT_PER_LEVEL)), "próg → poziom 2, więcej HP")
	_check(sim.hero_offers[0].size() == 1 and sim.hero_offers[0][0].size() == 2, "awans daje ofertę 2 ulepszeń")
	var offer: Array = sim.hero_offers[0][0]
	_check(offer[0]["label"] != offer[1]["label"], "opcje oferty są różne")
	_check(sim.choose_upgrade(1), "wybór ulepszenia")
	_check(sim.hero_offers[0].is_empty() and not sim.choose_upgrade(0), "po wyborze oferta znika")
	sim._gain_xp(h, 1e6)
	_check(h.hero_level == Cfg.HERO_MAX_LEVEL and sim.hero_offers[0].size() == 1, "poziom maksymalny = %d" % Cfg.HERO_MAX_LEVEL)

	# ulepszenia ogólne działają na konfigurację drużyny, Cfg zostaje
	sim = _fx_sim()
	h = sim._make_hero(0, "sapper")
	sim.heroes[0] = h
	var base_cd: float = Cfg.ABILITIES["minefield"]["cooldown"]
	var base_dmg: float = Cfg.ABILITIES["minefield"]["dmg"]
	sim.hero_offers[0] = [[{"ability": "minefield", "kind": "cooldown", "label": "a"}, {"ability": "minefield", "kind": "power", "label": "b"}]]
	sim.choose_upgrade(0)
	_check(is_equal_approx(sim.ability_config("minefield", 0)["cooldown"], base_cd * Cfg.UPGRADE_COOLDOWN), "odnowienie −25%")
	_check(Cfg.ABILITIES["minefield"]["cooldown"] == base_cd and sim.ability_config("minefield", 1)["cooldown"] == base_cd,
		"ulepszenie nie rusza Cfg ani drugiej drużyny")
	sim.hero_offers[0] = [[{"ability": "minefield", "kind": "power", "label": "a"}, {"ability": "minefield", "kind": "reach", "label": "b"}]]
	sim.choose_upgrade(0)
	_check(is_equal_approx(sim.ability_config("minefield", 0)["dmg"], base_dmg * Cfg.UPGRADE_POWER), "moc +30%")
	h.pos = sim.lanes[1].point_at(700)
	sim.use_ability("minefield", h.pos + Vector2(60, 0))
	_check(is_equal_approx(sim.ability_cd[0]["minefield"], base_cd * Cfg.UPGRADE_COOLDOWN), "rzucenie używa ulepszonej konfiguracji")
	sim.hero_offers[0] = [[{"ability": "demo_charge", "kind": "manual", "label": "a", "set": {"building_dmg": 999.0}}, {}]]
	sim.choose_upgrade(0)
	_check(sim.ability_config("demo_charge", 0)["building_dmg"] == 999.0, "ulepszenie ręczne (Cfg.UPGRADES) nadpisuje wartości")

	# doświadczenie zostaje po śmierci; dowódca wroga zbiera je za poległych gracza
	var xp := h.xp + 50.0
	sim._gain_xp(h, 50.0)
	sim._damage_unit(h, 1e6, "melee")
	_check(h.state == "dead" and h.xp == xp, "doświadczenie zostaje po śmierci")
	var foe_h := sim._make_hero(1, "iron_grip")
	sim.heroes[1] = foe_h
	foe_h.pos = sim.lanes[1].point_at(900)
	sim._spawn_unit(0, "soldier", 1, 1.0, 1, 900)
	sim._damage_unit(sim.units[-1], 1e6, "arrow")
	_check(foe_h.xp > 0.0, "dowódca wroga zbiera doświadczenie za poległych gracza")


## Tryb przetrwania (T15): forteca wroga nie pada, furia od SURVIVAL_FURY_WAVE, koniec = baza gracza.
func _test_survival() -> void:
	var sim := Sim.new(1, 1, 0, "sapper", "survival")
	sim.base_hp[1] = 10.0
	sim._damage_base(1, 1e6)
	sim.step(DT)
	_check(sim.base_hp[1] == 10.0 and sim.result == 0, "w przetrwaniu forteca wroga nie pada")
	var battle := Sim.new(1, 1, 0, "sapper")
	sim.wave = Cfg.SURVIVAL_FURY_WAVE + 5
	battle.wave = Cfg.SURVIVAL_FURY_WAVE + 5
	_check(sim.enemy_fury() > 1.0 and battle.enemy_fury() == 1.0, "furia w przetrwaniu rusza od fali %d" % Cfg.SURVIVAL_FURY_WAVE)
	sim._damage_base(0, 1e6)
	sim.step(DT)
	_check(sim.result == -1, "przetrwanie kończy się upadkiem bazy gracza")
	_check(Sim.new(1, 1, 0).mode == "battle", "domyślny tryb to bitwa")

	Progress.reset_cache()
	_check(Progress.best_survival("x_test", 1, "sapper") == 0, "brak rekordu przetrwania na starcie")
	_check(Progress.record_survival("x_test", 1, "sapper", 20), "pierwszy wynik to rekord")
	_check(not Progress.record_survival("x_test", 1, "sapper", 18), "gorszy wynik nie jest rekordem")
	_check(Progress.record_survival("x_test", 1, "sniper", 5), "inny dowódca — osobny rekord")
	_check(Progress.best_survival("x_test", 2, "sapper") == 0, "inna trudność — osobny rekord")
	Progress.reset_cache()
	_check(Progress.best_survival("x_test", 1, "sapper") == 20, "rekord przetrwania przetrwał zapis")


## Wyzwanie dnia (T16): powtarzalność ziarna, poprawny zestaw, działanie modyfikatorów, rekord dnia.
func _test_daily() -> void:
	var a := Cfg.daily("2026-09-26")
	_check(a == Cfg.daily("2026-09-26"), "ta sama data = ten sam zestaw")
	var differs := false
	for day in range(1, 8):
		if Cfg.daily("2026-10-%02d" % day) != a:
			differs = true
	_check(differs, "inne dni dają inne zestawy")
	_check(Races.ALL[a["race"]]["playable"] and Cfg.COMMANDERS[a["commander"]]["race"] == Races.ALL[a["race"]]["id"]
		and Cfg.commander_ready(a["commander"]), "dowódca dnia grywalny i z rasy dnia")
	_check(Cfg.DAILY_MODS[a["mods"][0]]["good"] and not Cfg.DAILY_MODS[a["mods"][1]]["good"], "jeden modyfikator na plus, jeden na minus")

	# ziarno dnia = identyczna partia (fale, ścieżki, losowania) przy tych samych rozkazach
	var runs: Array[String] = []
	for k in 2:
		var sim := Sim.new(a["difficulty"], a["seed"], a["map"], a["commander"], a["mode"], a["mods"])
		for i in 30 * 90:
			sim.step(DT)
		runs.append("%d %d %.2f %s" % [sim.wave, sim.units.size(), sim.gold, sim.next_wave_lanes])
	_check(runs[0] == runs[1], "partia z ziarnem dnia jest powtarzalna (%s)" % runs[0])

	# modyfikatory
	var plain := Sim.new(1, 7, 0, "sapper")
	var rich := Sim.new(1, 7, 0, "sapper", "battle", ["rich", "cheap_towers", "hero", "frenzy"])
	_check(is_equal_approx(rich.extractor_income(0, 1), plain.extractor_income(0, 1) * 1.5), "Bogate złoża: wydobycie ×1,5")
	_check(rich.build_cost("tower") < plain.build_cost("tower") and rich.build_cost("barracks") == plain.build_cost("barracks"),
		"Tanie wieże: taniej tylko wieże")
	_check(is_equal_approx(rich.hero().max_hp, plain.hero().max_hp * 1.5), "Bohater: dowódca ×1,5")
	rich.hero().pos = rich.lanes[1].point_at(500)
	rich.use_ability("minefield", rich.hero().pos + Vector2(40, 0))
	_check(is_equal_approx(rich.ability_cd[0]["minefield"], Cfg.ABILITIES["minefield"]["cooldown"] * 0.6), "Szał umiejętności: odnowienia ×0,6")
	var hard := Sim.new(1, 7, 0, "sapper", "battle", ["poor", "hordes", "tough", "rush"])
	_check(is_equal_approx(hard.gold, plain.gold * 0.5) and is_equal_approx(hard.income(), plain.income() * 0.5), "Bieda: złoto i dochód ×0,5")
	_check(hard.wave_timer < plain.wave_timer, "Pośpiech: fale szybciej")
	hard.wave_timer = 0.0
	plain.wave_timer = 0.0
	hard.step(DT)
	plain.step(DT)
	_check(hard.spawn_queue.size() + hard.army_size(1) > plain.spawn_queue.size() + plain.army_size(1), "Hordy: więcej wrogów w fali")
	var foe_hp := func(s: Sim) -> float:
		for u in s.units:
			if u.team == 1 and u.kind == "grunt":
				return u.max_hp
		return 0.0
	_check(is_equal_approx(foe_hp.call(hard), foe_hp.call(plain) * 1.3), "Twardzi wrogowie: HP ×1,3 (%.0f vs %.0f)" % [foe_hp.call(hard), foe_hp.call(plain)])

	# rekord dnia
	Progress.reset_cache()
	_check(Progress.best_daily("x_day") < 0, "brak rekordu dnia na starcie")
	_check(Progress.record_daily("x_day", "battle", 400.0) and not Progress.record_daily("x_day", "battle", 450.0)
		and Progress.record_daily("x_day", "battle", 380.0), "bitwa: rekord dnia = szybsza wygrana")
	_check(Progress.record_daily("x_surv", "survival", 30) and not Progress.record_daily("x_surv", "survival", 25)
		and Progress.best_daily("x_surv") == 30, "przetrwanie: rekord dnia = więcej fal")


## Sim do testów typów efektów: obie drużyny mają gotowe wszystkie umiejętności z Cfg.
func _fx_sim(lv := 0) -> Sim:
	var sim := _empty_sim(lv)
	for team in 2:
		for a in Cfg.ABILITIES:
			sim.ability_cd[team][a] = 0.0
	return sim


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
func _empty_sim(lv := 0, commander := "") -> Sim:
	var sim := Sim.new(1, 1, lv, commander)
	sim.buildings = sim.buildings.filter(func(b: Sim.Building) -> bool: return b.kind == "basegun")
	sim.wave_timer = INF
	return sim


func _check(ok: bool, what: String) -> void:
	if ok:
		return
	failures += 1
	push_error("FAIL: " + what)
	print("  FAIL: ", what)
