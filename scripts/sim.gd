class_name Sim
extends RefCounted
## Symulacja gry: czysta logika, bez węzłów i rysowania.
## scripts/main.gd rysuje jej stan i przekazuje rozkazy gracza,
## tests/bot_test.gd puszcza ją headless. Kształt mapy przychodzi z Levels.
##
## Kolejność w step(dt):
##
##   dochód → umiejętności (cooldowny, salwy) → fale wroga → budynki (regeneracja,
##   strzały, produkcja) → jednostki → pociski → sprzątanie martwych → warunek końca
##
## Jednostka naziemna idzie po swojej ścieżce (Lane): `s` = odległość od bazy gracza
## wzdłuż krzywej. Gracz zwiększa `s`, wróg zmniejsza. Po walce wraca na ścieżkę
## w najbliższym jej punkcie (szukanym lokalnie — pętle ścieżki mogą leżeć blisko).
## Jednostka latająca leci prosto do bazy i bije tylko bazę.
##
## Decyzja jednostki naziemnej (co krok, pierwsza pasująca reguła wygrywa):
##
##   [oblężnicza?] budynek wroga w zasięgu     → strzelaj w budynek
##                 baza wroga w zasięgu         → strzelaj w bazę
##   jednostka wroga w zasięgu + AGGRO          → w zasięgu: bij / poza: podejdź
##     (latające widzą tylko jednostki z pociskami ANTI_AIR)
##   [atak] budynek wroga w zasięgu + B_AGGRO   → w zasięgu: bij / poza: podejdź
##   [atak] baza wroga w zasięgu                → bij bazę
##   [atak] idź ścieżką  |  [obrona] stań w szyku na linii zbiórki swojej ścieżki
##
## Zdarzenia dla renderu i dźwięku lądują w `events`; main opróżnia je co klatkę.


class Lane:
	var name: String
	var curve: Curve2D
	var length: float

	func _init(lane_name: String, points: Array) -> void:
		name = lane_name
		curve = Cfg.smooth_curve(points)
		length = curve.get_baked_length()

	func point_at(s: float) -> Vector2:
		return curve.sample_baked(clampf(s, 0.0, length), true)

	## Wektor prostopadły do ścieżki (po lewej, patrząc od gracza w stronę wroga).
	## Oś X transformacji to kierunek ścieżki, więc lewa strona = -Y.
	func normal_at(s: float) -> Vector2:
		return -curve.sample_baked_with_rotation(clampf(s, 0.0, length)).y

	## Punkt na ścieżce przesunięty w bok o `side` (szyk jednostek, sloty wież).
	## Jedno wywołanie silnika zamiast trzech próbkowań — to najgorętsza funkcja symulacji.
	func slot_at(s: float, side: float) -> Vector2:
		var xf := curve.sample_baked_with_rotation(clampf(s, 0.0, length))
		return xf.origin - xf.y * side

	func offset_of(p: Vector2) -> float:
		return curve.get_closest_offset(p)

	func distance_to(p: Vector2) -> float:
		return curve.get_closest_point(p).distance_to(p)


class Unit:
	var id: int
	var team: int
	var kind: String
	var level := 1
	var flying := false
	var lane: int
	var s: float  ## odległość od bazy gracza wzdłuż ścieżki
	var on_path := true  ## false = zszedł ze ścieżki (walka), musi na nią wrócić
	var pos: Vector2
	var lane_offset: float  ## przesunięcie w bok od osi ścieżki
	var hp: float
	var max_hp: float
	var dmg: float
	var building_dmg := 0.0
	# statystyki z Cfg.UNITS skopiowane przy spawnie — odczyt słownika co krok był drogi
	var radius: float
	var attack_range: float
	var base_speed: float
	var cooldown: float
	var projectile: String
	var splash: float
	var melee: bool
	var anti_air: bool
	var siege: bool
	var cd_left := 0.0
	var slow_timer := 0.0
	var slow_factor := 0.0  ## ułamek prędkości zabrany przez mróz
	var flash := 0.0  ## tylko dla renderu: błysk po trafieniu


class Building:
	var id: int
	var team: int
	var kind: String  ## klucz z Cfg.BUILDINGS albo "basegun" (niewidoczne działko bazy)
	var level := 1
	var pos: Vector2
	var hp: float
	var max_hp: float
	var timer := 0.0
	var cd_left := 0.0
	var invested := 0  ## ile gracz w to włożył (budowa + ulepszenia) — podstawa zwrotu
	var node_index := -1  ## dla wydobywacza: indeks złoża
	var lane := 0  ## dla produkcji: którą ścieżką idą jednostki
	var last_hit := -INF  ## czas ostatniego trafienia (regeneracja)
	var aim := 0.0  ## tylko dla renderu: kąt ostatniego strzału
	var flash := 0.0


class Shot:
	var team: int
	var kind: String  ## arrow / cannonball / rock / frost
	var start: Vector2
	var pos: Vector2
	var target_pos: Vector2
	var target_unit: Unit
	var target_building: Building
	var target_base := -1
	var dmg: float
	var building_dmg := 0.0
	var splash := 0.0
	var slow := 0.0
	var slow_time := 0.0
	var speed: float
	var done := false


const BUILDING_R := 16.0
## Maks. skok `s` przy powrocie na ścieżkę — dalej = inna pętla tej samej ścieżki.
const REJOIN_WINDOW := 150.0
## Bok komórki siatki przestrzennej do szukania celów (zamiast przeglądać wszystkie jednostki).
const GRID_CELL := 150.0

var level_index: int
var level: Dictionary
var size: Vector2
var p_base: Vector2
var e_base: Vector2
var nodes: Array[Vector2] = []
var richness: Array[float] = []
var build_rect: Rect2
var rally_s: float
var difficulty: Dictionary
var lanes: Array[Lane] = []
var gold: float
var base_hp: Array[float] = [Cfg.BASE_HP[0], Cfg.BASE_HP[1]]
var units: Array[Unit] = []
var buildings: Array[Building] = []
var shots: Array[Shot] = []
var strikes: Array[Dictionary] = []  ## trwające „Deszcze strzał": {pos, left, timer}
var ability_cd := {}  ## umiejętność → sekundy do gotowości
var stance := "attack"  ## "attack" albo "defend"
var elapsed := 0.0
var wave := 0
var wave_timer: float
var next_wave_lanes: Array[int] = []  ## którymi ścieżkami przyjdzie następna fala
var spawn_queue: Array[Dictionary] = []  ## {"kind", "lane"}
var spawn_cd := 0.0
var trickle_timer := Cfg.ENEMY_TRICKLE
var result := 0  ## 0 = gra trwa, 1 = wygrana, -1 = przegrana
var events: Array[Dictionary] = []
var stats := {"kills": 0, "units_made": 0, "gold_earned": 0.0, "towers_razed": 0, "buildings_lost": 0, "abilities_used": 0}
var rng := RandomNumberGenerator.new()
var _next_id := 1
## Siatka przestrzenna jednostek per drużyna: Vector2i komórki → Array[Unit].
## Przebudowywana raz na krok; jednostki przesuwają się w kroku o ~1–2 px, więc
## nieaktualność w obrębie kroku nie ma znaczenia.
var _grid: Array[Dictionary] = [{}, {}]
## To samo dla budynków (bez działek baz) — jednostki szukają budynków przy ścieżce co krok.
var _bgrid: Array[Dictionary] = [{}, {}]


func _init(difficulty_index: int = 1, seed_value: int = -1, level_idx: int = 0) -> void:
	difficulty = Cfg.DIFFICULTIES[difficulty_index]
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	level_index = level_idx
	level = Levels.ALL[level_idx]
	size = level["size"]
	p_base = level["p_base"]
	e_base = level["e_base"]
	nodes.assign(level["nodes"])
	richness.assign(level["richness"])
	build_rect = level["build_rect"]
	rally_s = level["rally_s"]
	for l in level["lanes"]:
		lanes.append(Lane.new(l["name"], l["points"]))
	gold = difficulty["start_gold"]
	wave_timer = difficulty["first_wave"]
	for a in Cfg.ABILITY_ORDER:
		ability_cd[a] = 0.0
	for team in 2:
		var gun := _add_building(team, "basegun", base_pos(team))
		gun.level = Cfg.BASE_GUN_LEVEL[team]
	for i in level["enemy_start_towers"]:
		_add_building(1, "tower", enemy_slot_pos(i))
	next_wave_lanes = _plan_lanes(1)


# ================================================================ zapytania

func income() -> float:
	var total := Cfg.PASSIVE_INCOME
	for b in buildings:
		if b.team == 0 and b.kind == "extractor":
			total += extractor_income(b.node_index, b.level)
	return total


func extractor_income(node_index: int, lvl: int) -> float:
	return Cfg.BUILDINGS["extractor"]["income"][lvl - 1] * richness[node_index]


func base_pos(team: int) -> Vector2:
	return p_base if team == 0 else e_base


func enemy_slot_count() -> int:
	return level["enemy_slots"].size()


func enemy_slot_pos(i: int) -> Vector2:
	var slot: Vector3 = level["enemy_slots"][i]
	var lane := lanes[int(slot.x)]
	return lane.slot_at(lane.length - slot.y, slot.z * Cfg.ENEMY_TOWER_OFFSET).round()


func nearest_lane(p: Vector2) -> int:
	var best := 0
	for i in lanes.size():
		if lanes[i].distance_to(p) < lanes[best].distance_to(p):
			best = i
	return best


func node_at(p: Vector2) -> int:
	for i in nodes.size():
		if p.distance_to(nodes[i]) < 30.0:
			return i
	return -1


func extractor_on(node_index: int) -> Building:
	for b in buildings:
		if b.kind == "extractor" and b.node_index == node_index:
			return b
	return null


func building_at(p: Vector2, team: int) -> Building:
	for b in buildings:
		if b.team == team and b.kind != "basegun" and p.distance_to(b.pos) < Cfg.GRID * 0.6:
			return b
	return null


func is_alive(b: Building) -> bool:
	return b != null and b.hp > 0 and buildings.has(b)


func army_size(team: int) -> int:
	var n := 0
	for u in units:
		if u.team == team and u.hp > 0:
			n += 1
	return n


func can_place(cell: Vector2) -> bool:
	if cell.x < build_rect.position.x or cell.x > build_rect.end.x:
		return false
	if cell.y < build_rect.position.y or cell.y > build_rect.end.y:
		return false
	if cell.distance_to(p_base) < Cfg.BASE_R + Cfg.GRID:
		return false
	for n in nodes:
		if cell.distance_to(n) < Cfg.GRID:
			return false
	for b in buildings:
		if b.kind != "basegun" and cell.distance_to(b.pos) < Cfg.GRID * 0.9:
			return false
	for lane in lanes:
		if lane.distance_to(cell) < Cfg.PATH_CLEARANCE:
			return false
	return true


## Najbliższe wolne pole budowy w promieniu `max_r` od `p` (Vector2.INF, gdy brak).
func free_cell_near(p: Vector2, max_r := 240.0) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	var c0 := Cfg.snap(p)
	var r := int(max_r / Cfg.GRID)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := c0 + Vector2(dx, dy) * Cfg.GRID
			var d := c.distance_to(p)
			if d < best_d and d <= max_r and can_place(c):
				best = c
				best_d = d
	return best


func upgrade_cost(b: Building) -> int:
	if b.level >= Cfg.MAX_LEVEL:
		return -1
	return Cfg.BUILDINGS[b.kind]["upgrades"][b.level - 1]


func sell_value(b: Building) -> int:
	return int(b.invested * Cfg.SELL_REFUND)


## Statystyki strzelającego budynku po uwzględnieniu poziomu.
func tower_stats(kind: String, lvl: int) -> Dictionary:
	var base: Dictionary = Cfg.BASE_GUN if kind == "basegun" else Cfg.BUILDINGS[kind]
	var l := lvl - 1
	var slow: float = base.get("slow", 0.0)
	return {
		"range": base["range"] + Cfg.TOWER_RANGE_PER_LEVEL * l,
		"dmg": base["dmg"] * (1.0 + Cfg.TOWER_DMG_PER_LEVEL * l),
		"cd": base["cd"] * (1.0 - Cfg.TOWER_CD_PER_LEVEL * l),
		"projectile": base["projectile"],
		"splash": base.get("splash", 0.0),
		"slow": slow + Cfg.SLOW_PER_LEVEL * l if slow > 0 else 0.0,
		"slow_time": base.get("slow_time", 0.0) + Cfg.SLOW_TIME_PER_LEVEL * l if slow > 0 else 0.0,
	}


func production_period(kind: String, lvl: int) -> float:
	return Cfg.BUILDINGS[kind]["period"] * (1.0 - Cfg.PRODUCTION_SPEEDUP_PER_LEVEL * (lvl - 1))


func unit_hp(kind: String, lvl: int) -> float:
	return Cfg.UNITS[kind]["hp"] * (1.0 + Cfg.UNIT_HP_PER_LEVEL * (lvl - 1))


func unit_dmg(kind: String, lvl: int) -> float:
	return Cfg.UNITS[kind]["dmg"] * (1.0 + Cfg.UNIT_DMG_PER_LEVEL * (lvl - 1))


func lane_names(ids: Array[int]) -> String:
	var names := PackedStringArray()
	for i in ids:
		names.append(lanes[i].name)
	return ", ".join(names)


## Siła obrony gracza na ścieżce: wieże w zasięgu jej osi + jego jednostki na niej.
func lane_defense(lane_index: int) -> float:
	var lane := lanes[lane_index]
	var total := 0.0
	for b in buildings:
		if b.team != 0 or not Cfg.is_tower(b.kind):
			continue
		var ts := tower_stats(b.kind, b.level)
		if lane.distance_to(b.pos) > ts["range"]:
			continue
		var power: float = ts["dmg"] / ts["cd"]
		if ts["splash"] > 0:
			power *= 2.0
		if ts["slow"] > 0:
			power += 10.0
		total += power
	for u in units:
		if u.team == 0 and u.lane == lane_index:
			total += 3.0
	return total


func ability_ready(ability: String) -> bool:
	return ability_cd.get(ability, INF) <= 0.0


## Czy umiejętność da się użyć w tym miejscu (Pobór: tylko przy ścieżce, na swojej połowie).
func ability_target_ok(ability: String, at: Vector2) -> bool:
	if ability != "levy":
		return true
	var cfg: Dictionary = Cfg.ABILITIES["levy"]
	return at.x < size.x / 2.0 and lanes[nearest_lane(at)].distance_to(at) <= cfg["max_lane_dist"]


# ================================================================ rozkazy gracza

func build(kind: String, cell: Vector2) -> bool:
	var cost: int = Cfg.BUILDINGS[kind]["cost"]
	if result != 0 or gold < cost or not can_place(cell):
		return false
	gold -= cost
	var b := _add_building(0, kind, cell)
	b.invested = cost
	b.lane = nearest_lane(cell)
	events.append({"type": "build", "pos": cell})
	return true


func build_extractor(node_index: int) -> bool:
	var cost: int = Cfg.BUILDINGS["extractor"]["cost"]
	if result != 0 or gold < cost or extractor_on(node_index) != null:
		return false
	gold -= cost
	var b := _add_building(0, "extractor", nodes[node_index])
	b.node_index = node_index
	b.invested = cost
	events.append({"type": "build", "pos": b.pos})
	return true


func upgrade(b: Building) -> bool:
	var cost := upgrade_cost(b)
	if result != 0 or b.team != 0 or cost < 0 or gold < cost or not is_alive(b):
		return false
	gold -= cost
	b.invested += cost
	_level_up(b)
	events.append({"type": "upgrade", "pos": b.pos})
	return true


func sell(b: Building) -> bool:
	if result != 0 or b.team != 0 or not is_alive(b):
		return false
	gold += sell_value(b)
	b.hp = 0.0
	buildings.erase(b)
	events.append({"type": "sell", "pos": b.pos, "amount": sell_value(b)})
	return true


## Kieruje produkcję budynku na wybraną ścieżkę.
func set_lane(b: Building, lane_index: int) -> bool:
	if b.team != 0 or not Cfg.is_production(b.kind) or lane_index < 0 or lane_index >= lanes.size():
		return false
	b.lane = lane_index
	return true


func set_stance(s: String) -> void:
	stance = s


## Używa umiejętności. `at` ignorowane dla umiejętności bez celu (Naprawa).
func use_ability(ability: String, at := Vector2.ZERO) -> bool:
	if result != 0 or not ability_ready(ability) or not ability_target_ok(ability, at):
		return false
	var cfg: Dictionary = Cfg.ABILITIES[ability]
	match ability:
		"arrows":
			strikes.append({"pos": at, "left": cfg["volleys"], "timer": 0.3})
		"levy":
			var lane_i := nearest_lane(at)
			var s := lanes[lane_i].offset_of(at)
			for i in cfg["count"]:
				_spawn_unit(0, cfg["unit"], 1, 1.0, lane_i, s + (i - 1.5) * 14.0)
		"repair":
			for b in buildings:
				if b.team == 0 and b.kind != "basegun":
					b.hp = minf(b.max_hp, b.hp + b.max_hp * cfg["heal"])
			base_hp[0] = minf(Cfg.BASE_HP[0], base_hp[0] + cfg["base_heal"])
	ability_cd[ability] = cfg["cooldown"]
	stats["abilities_used"] += 1
	events.append({"type": "ability", "name": ability, "pos": at if cfg["target"] else p_base})
	return true


# ================================================================ krok symulacji

func step(dt: float) -> void:
	if result != 0:
		return
	elapsed += dt
	var earned := income() * dt
	gold += earned
	stats["gold_earned"] += earned

	for a in ability_cd:
		ability_cd[a] = maxf(0.0, ability_cd[a] - dt)
	_update_strikes(dt)
	_update_waves(dt)
	_rebuild_grid()
	for b in buildings:
		_update_building(b, dt)
	for u in units:
		if u.hp > 0:
			_update_unit(u, dt)
	_update_shots(dt)

	units = units.filter(func(u: Unit) -> bool: return u.hp > 0)
	buildings = buildings.filter(func(b: Building) -> bool: return b.hp > 0)
	shots = shots.filter(func(s: Shot) -> bool: return not s.done)

	if base_hp[1] <= 0:
		result = 1
	elif base_hp[0] <= 0:
		result = -1
	if result != 0:
		events.append({"type": "end", "result": result})


func _update_strikes(dt: float) -> void:
	var cfg: Dictionary = Cfg.ABILITIES["arrows"]
	for st in strikes:
		st["timer"] -= dt
		if st["timer"] > 0:
			continue
		st["timer"] = cfg["interval"]
		st["left"] -= 1
		var at: Vector2 = st["pos"]
		events.append({"type": "volley", "pos": at, "radius": cfg["radius"]})
		for u in units:
			if u.team == 1 and u.hp > 0 and u.pos.distance_to(at) <= cfg["radius"]:
				_damage_unit(u, cfg["dmg"], "arrow")
	strikes = strikes.filter(func(st: Dictionary) -> bool: return st["left"] > 0)


# ---------------------------------------------------------------- wróg

## Skryptowany wróg: fale co ~20 s (coraz częściej i grubiej), rozkładane na
## ścieżki zapowiedziane wcześniej w `next_wave_lanes`. Między falami pojedyncze orki.
## Co kilka fal stawia/odbudowuje wieżę i podnosi poziom istniejących.
func _update_waves(dt: float) -> void:
	wave_timer -= dt
	if wave_timer <= 0:
		wave += 1
		var interval := maxf(Cfg.MIN_WAVE_INTERVAL, Cfg.FIRST_WAVE_INTERVAL - wave * Cfg.WAVE_INTERVAL_DECAY)
		wave_timer = interval * difficulty["wave_interval"]
		var comp := Cfg.wave_composition(wave)
		var wave_lanes := next_wave_lanes
		for i in comp.size():
			spawn_queue.append({"kind": comp[i], "lane": wave_lanes[i % wave_lanes.size()]})
		events.append({"type": "wave", "n": wave, "boss": comp.has("warlord"), "count": comp.size(), "lanes": wave_lanes})
		next_wave_lanes = _plan_lanes(wave + 1)
		if wave % Cfg.ENEMY_BUILD_EVERY == 0:
			_enemy_build()

	var hp_mult: float = difficulty["enemy_hp"] * (1.0 + Cfg.ENEMY_HP_PER_WAVE * maxi(wave - 1, 0))
	spawn_cd -= dt
	if spawn_cd <= 0 and not spawn_queue.is_empty():
		# Każda ścieżka wypuszcza po jednej jednostce naraz — inaczej przy dzielonych
		# falach kolejka rosłaby bez końca, a siła wroga przestałaby rosnąć.
		spawn_cd = maxf(Cfg.MIN_SPAWN_GAP, Cfg.SPAWN_GAP - wave * Cfg.SPAWN_GAP_DECAY)
		var used: Array[int] = []
		var rest: Array[Dictionary] = []
		for e in spawn_queue:
			if used.has(e["lane"]):
				rest.append(e)
			else:
				used.append(e["lane"])
				_spawn_unit(1, e["kind"], 1, hp_mult, e["lane"])
		spawn_queue = rest

	if wave >= 1:
		trickle_timer -= dt
		if trickle_timer <= 0:
			trickle_timer = Cfg.ENEMY_TRICKLE
			_spawn_unit(1, "grunt", 1, hp_mult, rng.randi_range(0, lanes.size() - 1))


## Wybiera ścieżki dla fali n: im dalej, tym na więcej ścieżek dzieli się fala.
## Losowanie jest ważone — słabo bronione ścieżki są wybierane częściej.
func _plan_lanes(n: int) -> Array[int]:
	var count := 1
	if n >= Cfg.WAVE_SPLIT_3:
		count = 3
	elif n >= Cfg.WAVE_SPLIT_2:
		count = 2
	var pool: Array[int] = []
	var weights: Array[float] = []
	for i in lanes.size():
		pool.append(i)
		weights.append(pow(1.0 + lane_defense(i) / Cfg.LANE_DEFENSE_SCALE, -2.0))
	var picked: Array[int] = []
	while picked.size() < mini(count, lanes.size()):
		var total := 0.0
		for w in weights:
			total += w
		var roll := rng.randf() * total
		var k := 0
		while k < weights.size() - 1 and roll > weights[k]:
			roll -= weights[k]
			k += 1
		picked.append(pool[k])
		pool.remove_at(k)
		weights.remove_at(k)
	picked.sort()
	return picked


@warning_ignore("integer_division")
func _enemy_build() -> void:
	var lvl := mini(1 + wave / 8, Cfg.MAX_LEVEL)
	for b in buildings:
		if b.team == 1 and b.kind == "basegun":
			b.level = maxi(b.level, lvl)
		while b.team == 1 and b.kind == "tower" and b.level < lvl:
			_level_up(b)
	for i in enemy_slot_count():
		var slot := enemy_slot_pos(i)
		var taken := false
		for b in buildings:
			if b.team == 1 and b.pos.distance_to(slot) < 1.0:
				taken = true
		if not taken:
			var t := _add_building(1, "tower", slot)
			while t.level < lvl:
				_level_up(t)
			events.append({"type": "enemy_build", "pos": slot})
			return


# ---------------------------------------------------------------- budynki

func _update_building(b: Building, dt: float) -> void:
	b.flash = maxf(0.0, b.flash - dt)
	if b.kind != "basegun" and b.hp < b.max_hp and elapsed - b.last_hit >= Cfg.REGEN_DELAY:
		b.hp = minf(b.max_hp, b.hp + b.max_hp * Cfg.REGEN_RATE * dt)
	if b.kind == "basegun" or Cfg.is_tower(b.kind):
		b.cd_left -= dt
		if b.cd_left > 0:
			return
		var ts := tower_stats(b.kind, b.level)
		var target := _nearest_unit(1 - b.team, b.pos, ts["range"], Cfg.ANTI_AIR.has(ts["projectile"]))
		if target == null:
			return
		b.cd_left = ts["cd"]
		b.aim = (target.pos - b.pos).angle()
		var s := _fire(b.team, ts["projectile"], b.pos, target.pos, ts["dmg"], ts["splash"])
		s.target_unit = target
		s.slow = ts["slow"]
		s.slow_time = ts["slow_time"]
	elif Cfg.is_production(b.kind):
		b.timer += dt
		if b.timer >= production_period(b.kind, b.level):
			b.timer = 0.0
			_spawn_unit(b.team, Cfg.BUILDINGS[b.kind]["unit"], b.level, 1.0, b.lane)


# ---------------------------------------------------------------- jednostki

func _update_unit(u: Unit, dt: float) -> void:
	var rng_ := u.attack_range
	u.cd_left -= dt
	u.flash = maxf(0.0, u.flash - dt)
	if u.slow_timer > 0.0:
		u.slow_timer -= dt
		if u.slow_timer <= 0.0:
			u.slow_factor = 0.0
	var speed := u.base_speed * (1.0 - u.slow_factor)
	var foe_team := 1 - u.team
	var foe_base := base_pos(foe_team)
	var base_in_range := u.pos.distance_to(foe_base) <= rng_ + Cfg.BASE_R

	if u.flying:
		if base_in_range:
			if u.cd_left <= 0:
				u.cd_left = u.cooldown
				_damage_base(foe_team, u.dmg)
		else:
			u.pos = u.pos.move_toward(foe_base, speed * dt)
		return

	var attacking := u.team == 1 or stance == "attack"
	if u.siege:
		var tb := _nearest_building(foe_team, u.pos, rng_)
		if tb != null:
			_ranged_attack(u, tb.pos, null, tb, -1)
			return
		if base_in_range and attacking:
			var aim := foe_base + (u.pos - foe_base).normalized() * Cfg.BASE_R * 0.5
			_ranged_attack(u, aim, null, null, foe_team)
			return

	var foe := _nearest_unit(foe_team, u.pos, rng_ + Cfg.AGGRO, u.anti_air)
	if foe != null:
		if u.pos.distance_to(foe.pos) > rng_ + u.radius + foe.radius:
			u.pos = u.pos.move_toward(foe.pos, speed * dt)
			u.on_path = false
		elif u.melee:
			if u.cd_left <= 0:
				u.cd_left = u.cooldown
				_damage_unit(foe, u.dmg, "melee")
				events.append({"type": "hit", "pos": foe.pos})
		else:
			_ranged_attack(u, foe.pos, foe, null, -1)
		return

	if attacking:
		var tb := _nearest_building(foe_team, u.pos, rng_ + Cfg.BUILDING_AGGRO)
		if tb != null:
			if u.pos.distance_to(tb.pos) > rng_ + u.radius + BUILDING_R:
				u.pos = u.pos.move_toward(tb.pos, speed * dt)
				u.on_path = false
			elif u.melee:
				if u.cd_left <= 0:
					u.cd_left = u.cooldown
					_damage_building(tb, u.dmg)
					events.append({"type": "hit", "pos": tb.pos})
			else:
				_ranged_attack(u, tb.pos, null, tb, -1)
			return
		if base_in_range:
			if u.melee:
				if u.cd_left <= 0:
					u.cd_left = u.cooldown
					_damage_base(foe_team, u.dmg)
			else:
				_ranged_attack(u, foe_base, null, null, foe_team)
			return
		_follow_lane(u, lanes[u.lane].length if u.team == 0 else 0.0, speed * dt)
	else:
		_follow_lane(u, _rally_s(u), speed * dt)


## Idzie wzdłuż ścieżki do `goal_s`. Jeśli walka zepchnęła jednostkę ze ścieżki,
## najpierw wraca do najbliższego jej punktu — szukanego tylko w pobliżu dotychczasowego
## `s`, żeby na krętej ścieżce nie „przeskoczyć" na sąsiednią pętlę.
func _follow_lane(u: Unit, goal_s: float, step_len: float) -> void:
	var lane := lanes[u.lane]
	if not u.on_path:
		var candidate := lane.offset_of(u.pos)
		if absf(candidate - u.s) < REJOIN_WINDOW:
			u.s = candidate
		var slot := lane.slot_at(u.s, u.lane_offset)
		u.pos = u.pos.move_toward(slot, step_len)
		u.on_path = u.pos.distance_to(slot) < 1.0
		return
	if u.s == goal_s:
		return  # stoi w szyku — pozycja się nie zmienia
	u.s = move_toward(u.s, goal_s, step_len)
	u.pos = lane.slot_at(u.s, u.lane_offset)


## Szyk w obronie: piechota z przodu, łucznicy za nią, katapulty na końcu.
func _rally_s(u: Unit) -> float:
	var depth := {"soldier": 0.0, "archer": 50.0, "catapult": 100.0}
	return rally_s - depth.get(u.kind, 0.0) - (u.id % 3) * 12.0


func _ranged_attack(u: Unit, at: Vector2, unit: Unit, building: Building, base_team: int) -> void:
	if u.cd_left > 0:
		return
	u.cd_left = u.cooldown
	var s := _fire(u.team, u.projectile, u.pos, at, u.dmg, u.splash)
	s.building_dmg = u.building_dmg
	s.target_unit = unit
	s.target_building = building
	s.target_base = base_team


## Wystawia jednostkę na ścieżce. `at_s` < 0 = przy własnej bazie.
func _spawn_unit(team: int, kind: String, lvl: int, hp_mult: float, lane_index: int, at_s := -1.0) -> void:
	var st: Dictionary = Cfg.UNITS[kind]
	var lane := lanes[lane_index]
	var u := Unit.new()
	u.id = _take_id()
	u.team = team
	u.kind = kind
	u.level = lvl
	u.flying = st.get("flying", false)
	u.radius = st["r"]
	u.attack_range = st["range"]
	u.base_speed = st["speed"]
	u.cooldown = st["cd"]
	u.projectile = st["projectile"]
	u.splash = st.get("splash", 0.0)
	u.melee = u.projectile == ""
	u.anti_air = Cfg.ANTI_AIR.has(u.projectile)
	u.siege = st.get("siege", false)
	u.lane = lane_index
	u.lane_offset = rng.randf_range(-Cfg.PATH_HALF + 8.0, Cfg.PATH_HALF - 8.0)
	if at_s >= 0.0:
		u.s = clampf(at_s, 0.0, lane.length)
	else:
		u.s = Cfg.BASE_R + 14.0 if team == 0 else lane.length - Cfg.BASE_R - 14.0
	u.pos = lane.slot_at(u.s, u.lane_offset)
	u.max_hp = unit_hp(kind, lvl) * hp_mult
	u.hp = u.max_hp
	u.dmg = unit_dmg(kind, lvl)
	u.building_dmg = st.get("building_dmg", 0.0) * (1.0 + Cfg.UNIT_DMG_PER_LEVEL * (lvl - 1))
	units.append(u)
	if team == 0:
		stats["units_made"] += 1
	events.append({"type": "spawn", "pos": u.pos, "team": team, "kind": kind})


# ---------------------------------------------------------------- pociski i obrażenia

func _fire(team: int, kind: String, from: Vector2, to: Vector2, dmg: float, splash: float) -> Shot:
	var s := Shot.new()
	s.team = team
	s.kind = kind
	s.start = from
	s.pos = from
	s.target_pos = to
	s.dmg = dmg
	s.splash = splash
	s.speed = Cfg.PROJECTILE_SPEED[kind]
	shots.append(s)
	events.append({"type": "shot", "kind": kind, "team": team})
	return s


func _update_shots(dt: float) -> void:
	for s in shots:
		if s.done:
			continue
		if s.target_unit != null:
			if s.target_unit.hp > 0:
				s.target_pos = s.target_unit.pos
			elif s.splash <= 0:
				s.done = true  # strzała bez celu znika; pocisk obszarowy leci dalej
				continue
		if s.target_building != null and s.target_building.hp <= 0 and s.splash <= 0:
			s.done = true
			continue
		s.pos = s.pos.move_toward(s.target_pos, s.speed * dt)
		if s.pos.distance_squared_to(s.target_pos) < 4.0:
			s.done = true
			_impact(s)


func _impact(s: Shot) -> void:
	var foe_team := 1 - s.team
	if s.splash > 0:
		var hits_air := Cfg.ANTI_AIR.has(s.kind)
		events.append({"type": "frost" if s.kind == "frost" else "explosion", "pos": s.target_pos, "radius": s.splash})
		for u in units:
			if u.team != foe_team or u.hp <= 0 or (u.flying and not hits_air):
				continue
			if u.pos.distance_to(s.target_pos) <= s.splash + u.radius:
				_damage_unit(u, s.dmg, s.kind)
				if s.slow > 0:
					u.slow_timer = maxf(u.slow_timer, s.slow_time)
					u.slow_factor = maxf(u.slow_factor, s.slow)
		if s.building_dmg > 0:
			for b in buildings:
				if b.team == foe_team and b.kind != "basegun" and b.hp > 0 and b.pos.distance_to(s.target_pos) <= s.splash + BUILDING_R:
					_damage_building(b, s.building_dmg)
			if s.target_base == foe_team or base_pos(foe_team).distance_to(s.target_pos) <= s.splash + Cfg.BASE_R:
				_damage_base(foe_team, s.building_dmg)
		return
	if s.target_unit != null and s.target_unit.hp > 0:
		_damage_unit(s.target_unit, s.dmg, s.kind)
		events.append({"type": "hit", "pos": s.target_pos})
	elif s.target_building != null and s.target_building.hp > 0:
		_damage_building(s.target_building, s.building_dmg if s.building_dmg > 0 else s.dmg)
	elif s.target_base >= 0:
		_damage_base(s.target_base, s.dmg)


## `kind` = rodzaj obrażeń (pocisk albo "melee") — pancerz blokuje część strzał.
func _damage_unit(u: Unit, dmg: float, kind: String) -> void:
	if u.hp <= 0:
		return
	if kind == "arrow":
		dmg *= 1.0 - Cfg.UNITS[u.kind].get("armor", 0.0)
	u.hp -= dmg
	u.flash = 0.12
	if u.hp > 0:
		return
	events.append({"type": "death", "pos": u.pos, "team": u.team, "kind": u.kind})
	if u.team == 1:
		var bounty: int = Cfg.UNITS[u.kind].get("bounty", 0)
		stats["kills"] += 1
		_earn(bounty, u.pos)


func _damage_building(b: Building, dmg: float) -> void:
	if b.hp <= 0:
		return
	b.hp -= dmg
	b.flash = 0.15
	b.last_hit = elapsed
	if b.team == 0:
		events.append({"type": "building_hit", "pos": b.pos, "id": b.id})
	if b.hp > 0:
		return
	events.append({"type": "building_destroyed", "pos": b.pos, "team": b.team, "kind": b.kind})
	if b.team == 1:
		stats["towers_razed"] += 1
		_earn(Cfg.TOWER_KILL_BOUNTY, b.pos)
	else:
		stats["buildings_lost"] += 1


func _damage_base(team: int, dmg: float) -> void:
	if base_hp[team] <= 0:
		return
	base_hp[team] = maxf(0.0, base_hp[team] - dmg)
	events.append({"type": "base_hit", "team": team, "pos": base_pos(team), "dmg": dmg})


func _earn(amount: int, at: Vector2) -> void:
	if amount <= 0:
		return
	gold += amount
	stats["gold_earned"] += amount
	events.append({"type": "gold", "pos": at, "amount": amount})


# ---------------------------------------------------------------- pomocnicze

func _rebuild_grid() -> void:
	_grid = [{}, {}]
	_bgrid = [{}, {}]
	for u in units:
		if u.hp > 0:
			_grid_add(_grid[u.team], u.pos, u)
	for b in buildings:
		if b.hp > 0 and b.kind != "basegun":
			_grid_add(_bgrid[b.team], b.pos, b)


static func _grid_add(cells: Dictionary, pos: Vector2, item: Object) -> void:
	var key := Vector2i(floori(pos.x / GRID_CELL), floori(pos.y / GRID_CELL))
	var bucket: Variant = cells.get(key)
	if bucket == null:
		cells[key] = [item]
	else:
		bucket.append(item)


## Najbliższa żywa jednostka drużyny `team`; latające tylko gdy `anti_air`.
## Przegląda tylko komórki siatki w zasięgu `max_dist`.
func _nearest_unit(team: int, from: Vector2, max_dist: float, anti_air: bool) -> Unit:
	var best: Unit = null
	var best_d := max_dist
	var cells: Dictionary = _grid[team]
	# dokładny zakres komórek, które przecina kwadrat o boku 2·max_dist (zwykle 2–4 komórki)
	var x0 := floori((from.x - max_dist) / GRID_CELL)
	var y0 := floori((from.y - max_dist) / GRID_CELL)
	for gx in range(x0, floori((from.x + max_dist) / GRID_CELL) + 1):
		for gy in range(y0, floori((from.y + max_dist) / GRID_CELL) + 1):
			var bucket: Variant = cells.get(Vector2i(gx, gy))
			if bucket == null:
				continue
			for o: Unit in bucket:
				if o.hp > 0 and (anti_air or not o.flying):
					var d := from.distance_to(o.pos)
					if d <= best_d:
						best_d = d
						best = o
	return best


func _nearest_building(team: int, from: Vector2, max_dist: float) -> Building:
	var best: Building = null
	var best_d := max_dist
	var cells: Dictionary = _bgrid[team]
	# dokładny zakres komórek, które przecina kwadrat o boku 2·max_dist (zwykle 2–4 komórki)
	var x0 := floori((from.x - max_dist) / GRID_CELL)
	var y0 := floori((from.y - max_dist) / GRID_CELL)
	for gx in range(x0, floori((from.x + max_dist) / GRID_CELL) + 1):
		for gy in range(y0, floori((from.y + max_dist) / GRID_CELL) + 1):
			var bucket: Variant = cells.get(Vector2i(gx, gy))
			if bucket == null:
				continue
			for b: Building in bucket:
				if b.hp > 0:
					var d := from.distance_to(b.pos)
					if d <= best_d:
						best_d = d
						best = b
	return best


func _add_building(team: int, kind: String, pos: Vector2) -> Building:
	var b := Building.new()
	b.id = _take_id()
	b.team = team
	b.kind = kind
	b.pos = pos
	b.max_hp = INF if kind == "basegun" else Cfg.BUILDINGS[kind]["hp"]
	b.hp = b.max_hp
	buildings.append(b)
	return b


func _level_up(b: Building) -> void:
	b.level += 1
	var new_max: float = Cfg.BUILDINGS[b.kind]["hp"] * (1.0 + 0.3 * (b.level - 1))
	b.hp += new_max - b.max_hp
	b.max_hp = new_max


func _take_id() -> int:
	_next_id += 1
	return _next_id
