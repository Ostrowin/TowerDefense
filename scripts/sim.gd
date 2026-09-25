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
	var prev_pos: Vector2  ## pozycja z poprzedniego kroku — render interpoluje między nimi
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
	var armor := 0.0  ## jaką część obrażeń od strzał blokuje
	var is_hero := false  ## dowódca (Hero) — szybszy test niż `is Hero` w gorących pętlach
	# wzmocnienia (`buff`): stat → [wartość, czas końca]; mnożniki poniżej liczone z nich
	var buffs := {}
	var dmg_mult := 1.0
	var speed_mult := 1.0
	var attack_speed := 1.0  ## dzieli czas odnowienia ciosu
	var armor_bonus := 0.0
	var lifesteal := 0.0  ## ułamek zadanych obrażeń wręcz wracający jako HP
	var cd_left := 0.0
	var slow_timer := 0.0
	var slow_factor := 0.0  ## ułamek prędkości zabrany przez mróz
	var flash := 0.0  ## tylko dla renderu: błysk po trafieniu


## Dowódca (R4): jednostka sterowana rozkazami, bez ścieżki. Jest w `units` i `_grid`, więc wieże,
## pociski, salwy i mróz widzą go jak każdą jednostkę; nie liczy się do limitów, armii ani obrony
## ścieżek. Rekord trwa po śmierci (`heroes`), a do `units` wraca przy odrodzeniu.
##
##   idle ──rozkaz──▶ march (trasa A*, ignoruje wrogów) ──dotarł──▶ idle w nowym punkcie
##   idle ──wróg w zasięgu + AGGRO──▶ fight (goni najdalej COMMANDER_LEASH od punktu)
##   fight ──brak celu / za daleko──▶ back (wraca do punktu, ignoruje wrogów) ──▶ idle
##   hp ≤ 0 ──▶ dead (Cfg.commander_respawn) ──▶ idle przy bazie, nietykalny COMMANDER_INVULNERABLE s
class Hero extends Unit:
	var commander: String
	var state := "idle"  ## idle / march / fight / back / dead
	var post: Vector2  ## punkt postoju — tu wraca po walce
	var path := PackedVector2Array()
	var path_i := 0
	var respawn := 0.0  ## sekundy do odrodzenia (stan dead)
	var invulnerable := 0.0
	var building_mult: float


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
	var temporary := false  ## budowla z umiejętności (R7) — znika po `life` s
	var life := 0.0


class Shot:
	var team: int
	var kind: String  ## arrow / cannonball / rock / frost
	var start: Vector2
	var pos: Vector2
	var prev_pos: Vector2
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
	var no_base := false  ## pocisk dowódcy — nie rani bazy (R4)
	var done := false


const BUILDING_R := 16.0
## Maks. skok `s` przy powrocie na ścieżkę — dalej = inna pętla tej samej ścieżki.
const REJOIN_WINDOW := 150.0
## Bok komórki siatki przestrzennej do szukania celów (zamiast przeglądać wszystkie jednostki).
const GRID_CELL := 150.0
## Most = odcinek ścieżki, którego oś leży bliżej niż RIVER_HALF + BRIDGE_MARGIN od osi rzeki.
## Próbkujemy co BRIDGE_STEP wzdłuż ścieżki (widok stawia deskę w każdej próbce).
const BRIDGE_MARGIN := 10.0
const BRIDGE_STEP := 7.0
## Nawigacja po mapie (dowódca): siatka drobniejsza niż siatka budowy. Pole jest wodą, gdy
## jego środek leży bliżej niż RIVER_HALF + NAV_CLEARANCE od osi rzeki (zapas = promień postaci).
const NAV_CELL := 20.0
const NAV_CLEARANCE := 12.0
## Próbkowanie odcinka trasy przy sprawdzaniu, czy nie wchodzi w wodę.
const NAV_SAMPLE := 5.0

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
## Rzeka (null na mapie bez rzeki) i mosty: {"lane", "s0", "s1"} — odcinki ścieżek nad wodą.
## Widok rysuje z nich teren, nawigacja omija wodę poza mostami.
var river: Curve2D = null
var bridges: Array[Dictionary] = []
var gold: float
var base_hp: Array[float] = [Cfg.BASE_HP[0], Cfg.BASE_HP[1]]
var units: Array[Unit] = []
var buildings: Array[Building] = []
var shots: Array[Shot] = []
var strikes: Array[Dictionary] = []  ## trwające salwy (typ `strike`): {pos, left, timer, team, cfg}
## Trwające strefy (typ `zone`): {pos, left (s), tick, team, cfg}. Mina znika po wybuchu.
var zones: Array[Dictionary] = []
## Per drużyna: umiejętność → sekundy do gotowości. Wróg ma na razie ten sam zestaw co gracz
## (jeszcze go nie używa — przyjdą dowódcy), ale każdy efekt już działa dla obu stron.
var ability_cd: Array[Dictionary] = [{}, {}]
## Dowódca gracza (id z Cfg.COMMANDERS); "" = bez dowódcy — gra jak przed dowódcami (D8).
var commander := ""
## Per drużyna: umiejętności na pasku (3 dowódcy + rasowa albo Cfg.ABILITY_ORDER bez dowódcy).
var ability_order: Array = [Cfg.ABILITY_ORDER.duplicate(), Cfg.ABILITY_ORDER.duplicate()]
## Per drużyna: dowódca (null = drużyna bez dowódcy). Rekord żyje też po śmierci.
var heroes: Array[Hero] = [null, null]
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
## Profilowanie faz kroku (benchmark tests/perf_test.gd): czasy w µs, sumowane.
var profile := false
var prof_data := {}
var _next_id := 1
## Siatka przestrzenna jednostek per drużyna: Vector2i komórki → Array[Unit].
## Przebudowywana raz na krok; jednostki przesuwają się w kroku o ~1–2 px, więc
## nieaktualność w obrębie kroku nie ma znaczenia.
var _grid: Array[Dictionary] = [{}, {}]
## To samo dla budynków (bez działek baz) — jednostki szukają budynków przy ścieżce co krok.
var _bgrid: Array[Dictionary] = [{}, {}]
## Żywe jednostki per drużyna (liczone przy budowie siatki) — do limitów populacji.
var team_count: Array[int] = [0, 0]
## Rośnie przy każdej zmianie listy budynków — widok po nim unieważnia pamięć podręczną
## (np. wolne pola budowy).
var layout_version := 0
## Siatka nawigacji (A*) — budowana przy pierwszym `path_to`, bo zwykła partia jej nie potrzebuje.
var _nav: AStarGrid2D = null
var _nav_bridge := {}  ## Vector2i → indeks ścieżki: pola mostów (przejezdne mimo wody)
var _nav_near := {}  ## Vector2i → true: pola przy wodzie — tylko tam punkt trzeba sprawdzać dokładnie


func _init(difficulty_index: int = 1, seed_value: int = -1, level_idx: int = 0, commander_id := "") -> void:
	difficulty = Cfg.DIFFICULTIES[difficulty_index]
	commander = commander_id
	ability_order[0] = Cfg.commander_abilities(commander)
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
	_find_bridges()
	gold = difficulty["start_gold"]
	wave_timer = difficulty["first_wave"]
	for team in 2:
		for a in ability_order[team]:
			ability_cd[team][a] = 0.0
	for team in 2:
		var gun := _add_building(team, "basegun", base_pos(team))
		gun.level = Cfg.BASE_GUN_LEVEL[team]
	for i in level["enemy_start_towers"]:
		_add_building(1, "tower", enemy_slot_pos(i))
	next_wave_lanes = _plan_lanes(1)
	if commander != "":
		heroes[0] = _make_hero(0, commander)


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
		if b.team == team and b.kind != "basegun" and not b.temporary and p.distance_to(b.pos) < Cfg.GRID * 0.6:
			return b
	return null


func is_alive(b: Building) -> bool:
	return b != null and b.hp > 0 and buildings.has(b)


func army_size(team: int) -> int:
	var n := 0
	for u in units:
		if u.team == team and u.hp > 0 and not u.is_hero:
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
	if b.level >= Cfg.MAX_LEVEL or b.temporary:
		return -1
	return Cfg.BUILDINGS[b.kind]["upgrades"][b.level - 1]


func sell_value(b: Building) -> int:
	return int(b.invested * Cfg.SELL_REFUND)


## Statystyki strzelającego budynku po uwzględnieniu poziomu.
func tower_stats(kind: String, lvl: int) -> Dictionary:
	var base: Dictionary = Cfg.BASE_GUN if kind == "basegun" else Cfg.building(kind)
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
		if u.team == 0 and u.lane == lane_index and not u.is_hero:
			total += 3.0
	return total


## Mnożnik HP i obrażeń nowych wrogów w późnej grze (1.0 do fali ENEMY_FURY_WAVE).
func enemy_fury() -> float:
	return 1.0 + Cfg.ENEMY_FURY_PER_WAVE * maxi(wave - Cfg.ENEMY_FURY_WAVE, 0)


## Gotowa = odnowiona i (dla umiejętności dowódcy) dowódca żyje. Odnowienie biegnie też po śmierci (R3).
func ability_ready(ability: String, team := 0) -> bool:
	if ability_cd[team].get(ability, INF) > 0.0:
		return false
	return not (_is_hero_ability(ability, team) and not hero_alive(team))


## Czy umiejętność da się użyć w tym miejscu: w zasięgu rzucania od dowódcy (`cast_range` > 0),
## przywołanie tylko przy ścieżce — bez zasięgu od dowódcy dodatkowo na swojej połowie.
func ability_target_ok(ability: String, at: Vector2, team := 0) -> bool:
	var cfg: Dictionary = Cfg.ABILITIES[ability]
	if not cfg["target"]:
		return true
	var cast_range: float = cfg.get("cast_range", 0.0)
	if cast_range > 0.0 and heroes[team] != null and heroes[team].pos.distance_to(at) > cast_range:
		return false
	match cfg["kind"]:
		"zone", "summon_building":
			# nie pod bazą przeciwnika i nie na rzece (R2); budowla — na wolnym polu
			if at.distance_to(base_pos(1 - team)) < Cfg.NO_CAST_NEAR_BASE or river_distance(at) < Cfg.RIVER_HALF:
				return false
			return cfg["kind"] == "zone" or _summon_cell_ok(Cfg.snap(at))
		"demolish":
			return _demolish_target(team, at) != null
	if cfg["kind"] != "summon_units":
		return true
	if cast_range <= 0.0:
		var own_half := at.x < size.x / 2.0 if team == 0 else at.x > size.x / 2.0
		if not own_half:
			return false
	return lanes[nearest_lane(at)].distance_to(at) <= cfg["max_lane_dist"]


## Dowódca drużyny (null = bez dowódcy). Martwy ma `state == "dead"` i nie ma go w `units`.
func hero(team := 0) -> Hero:
	return heroes[team]


func hero_alive(team := 0) -> bool:
	return heroes[team] != null and heroes[team].state != "dead"


## Pole pod budowlę tymczasową: na mapie, poza ścieżkami, złożami, bazami i innymi budynkami
## (bez ograniczenia do strefy budowy gracza — R2).
func _summon_cell_ok(cell: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).grow(-Cfg.GRID / 2).has_point(cell):
		return false
	for t in 2:
		if cell.distance_to(base_pos(t)) < Cfg.BASE_R + Cfg.GRID:
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


## Budynek wroga do zburzenia (`demolish`): najbliższy wskazanego punktu, nie działko bazy.
## Przegląda listę wprost (rzucenie bywa przed pierwszym krokiem, gdy siatki są puste).
func _demolish_target(team: int, at: Vector2) -> Building:
	var best: Building = null
	var best_d := Cfg.DEMOLISH_PICK
	for b in buildings:
		if b.team != team and b.kind != "basegun" and b.hp > 0 and b.pos.distance_to(at) <= best_d:
			best_d = b.pos.distance_to(at)
			best = b
	return best


func _is_hero_ability(ability: String, team: int) -> bool:
	return heroes[team] != null and Cfg.COMMANDERS[heroes[team].commander]["abilities"].has(ability)


## Limit jednostek drużyny na mapie (gracz: armia, wróg: wrogowie na mapie).
func unit_cap(team: int) -> int:
	return Cfg.MAX_ARMY if team == 0 else Cfg.MAX_ENEMIES


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
	if result != 0 or b.team != 0 or b.temporary or cost < 0 or gold < cost or not is_alive(b):
		return false
	gold -= cost
	b.invested += cost
	_level_up(b)
	events.append({"type": "upgrade", "pos": b.pos})
	return true


func sell(b: Building) -> bool:
	if result != 0 or b.team != 0 or b.temporary or not is_alive(b):
		return false
	gold += sell_value(b)
	b.hp = 0.0
	buildings.erase(b)
	layout_version += 1
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


## Rozkaz marszu dowódcy: trasa A* do `pos` (rzeka po mostach; cel na wodzie → najbliższy ląd).
## Idąc ignoruje wrogów; na miejscu to nowy punkt postoju. false = brak dowódcy albo nie żyje.
func order_hero(pos: Vector2, team := 0) -> bool:
	var h := heroes[team]
	if result != 0 or h == null or h.state == "dead":
		return false
	h.path = path_to(h.pos, pos)
	h.path_i = 1
	h.post = h.path[-1]
	h.state = "march"
	h.on_path = false
	events.append({"type": "hero_order", "team": team, "pos": h.post})
	return true


## Używa umiejętności drużyny `team`. Działanie wynika z typu efektu (`kind` w Cfg.ABILITIES),
## nie z nazwy umiejętności. `at` ignorowane dla umiejętności bez celu (Naprawa).
func use_ability(ability: String, at := Vector2.ZERO, team := 0) -> bool:
	if result != 0 or not ability_ready(ability, team) or not ability_target_ok(ability, at, team):
		return false
	var cfg: Dictionary = Cfg.ABILITIES[ability]
	if cfg["kind"] == "summon_units" and team_count[team] >= unit_cap(team):
		return false
	match cfg["kind"]:
		"strike":
			strikes.append({"pos": at, "left": cfg["volleys"], "timer": 0.3, "team": team, "cfg": cfg})
		"summon_units":
			var lane_i := nearest_lane(at)
			var s := lanes[lane_i].offset_of(at)
			for i in mini(cfg["count"], unit_cap(team) - team_count[team]):
				_spawn_unit(team, cfg["unit"], 1, 1.0, lane_i, s + (i - 1.5) * 14.0)
		"global":
			for b in buildings:
				if b.team == team and b.kind != "basegun":
					b.hp = minf(b.max_hp, b.hp + b.max_hp * cfg["heal"])
			base_hp[team] = minf(Cfg.BASE_HP[team], base_hp[team] + cfg["base_heal"])
		"zone":
			zones.append({"pos": at, "left": cfg["duration"], "tick": 0.0, "team": team, "cfg": cfg})
		"summon_building":
			var b := _add_building(team, cfg["building"], Cfg.snap(at))
			b.temporary = true
			b.life = cfg["duration"]
			events.append({"type": "summon", "pos": b.pos, "team": team, "kind": b.kind})
		"buff":
			_cast_buff(team, at, cfg)
		"line":
			_cast_line(team, at, cfg)
		"execute":
			_cast_execute(team, at, cfg)
		"demolish":
			var target := _demolish_target(team, at)
			_damage_building(target, cfg["building_dmg"])
			events.append({"type": "explosion", "pos": target.pos, "radius": 30.0})
	ability_cd[team][ability] = cfg["cooldown"]
	if team == 0:
		stats["abilities_used"] += 1
	events.append({"type": "ability", "name": ability, "team": team, "pos": at if cfg["target"] else base_pos(team)})
	return true


## `buff`: sam dowódca (`self`), jednostki na wskazanej ścieżce (`lane`), w promieniu od celu
## (`radius` > 0) albo cała armia (`radius` 0). `dmg_mult` — opcjonalne drugie wzmocnienie obrażeń.
func _cast_buff(team: int, at: Vector2, cfg: Dictionary) -> void:
	var targets: Array[Unit] = []
	if cfg.get("self", false):
		if hero_alive(team):
			targets.append(heroes[team])
	else:
		var lane_i := nearest_lane(at) if cfg.get("lane", false) else -1
		var radius: float = cfg.get("radius", 0.0)
		for u in units:
			if u.team != team or u.hp <= 0:
				continue
			if lane_i >= 0 and (u.is_hero or u.flying or u.lane != lane_i):
				continue
			if lane_i < 0 and radius > 0.0 and u.pos.distance_to(at) > radius + u.radius:
				continue
			targets.append(u)
	for u in targets:
		_apply_buff(u, cfg["stat"], cfg["mult"], cfg["duration"])
		if cfg.has("dmg_mult"):
			_apply_buff(u, "dmg", cfg["dmg_mult"], cfg["duration"])
	events.append({"type": "buff", "pos": at, "team": team, "count": targets.size()})


## `line`: przebicie od dowódcy (albo od bazy, gdy dowódcy brak) w stronę `at` na `length` px.
## Trafia też latających.
func _cast_line(team: int, at: Vector2, cfg: Dictionary) -> void:
	var from := heroes[team].pos if hero_alive(team) else base_pos(team)
	var dir := (at - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT if team == 0 else Vector2.LEFT
	var to: Vector2 = from + dir * cfg["length"]
	for u in units:
		if u.team == team or u.hp <= 0:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(u.pos, from, to)
		if closest.distance_to(u.pos) <= cfg["width"] / 2.0 + u.radius:
			_damage_unit(u, cfg["dmg"], cfg.get("dmg_type", "arrow"))
	events.append({"type": "line", "from": from, "to": to, "team": team})


## `execute`: najsilniejszy (najwięcej HP) wróg w promieniu dostaje `dmg`; gdy zostałoby mu
## najwyżej `threshold` maks. HP — ginie. Wódz i dowódcy są odporni na dobicie (tylko `dmg`).
func _cast_execute(team: int, at: Vector2, cfg: Dictionary) -> void:
	var best: Unit = null
	for u in units:
		if u.team != team and u.hp > 0 and u.pos.distance_to(at) <= cfg["radius"] + u.radius:
			if best == null or u.hp > best.hp:
				best = u
	if best == null:
		return
	var immune := best.is_hero or best.kind == "warlord"
	var dmg: float = cfg["dmg"]
	if not immune and best.hp - dmg <= best.max_hp * cfg["threshold"]:
		dmg = best.hp + 1.0  # dobicie — bez pancerza
		_damage_unit(best, dmg, "execute")
	else:
		_damage_unit(best, dmg, cfg.get("dmg_type", "blast"))
	events.append({"type": "execute", "pos": best.pos, "team": team})


## Strefy (`zone`): mina wybucha, gdy wróg naziemny wejdzie w promień; strefa `tick` rani
## co sekundę (i spowalnia, jeśli ma `slow`). Wrogów szuka przez siatkę.
func _update_zones(dt: float) -> void:
	for z in zones:
		var cfg: Dictionary = z["cfg"]
		var foe: int = 1 - z["team"]
		z["left"] -= dt
		if cfg["trigger"] == "enter":
			var inside := _units_near(foe, z["pos"], cfg["radius"], false)
			if not inside.is_empty():
				for u in inside:
					_damage_unit(u, cfg["dmg"], cfg.get("dmg_type", "blast"))
				events.append({"type": "explosion", "pos": z["pos"], "radius": cfg["radius"]})
				z["left"] = 0.0
			continue
		z["tick"] -= dt
		if z["tick"] > 0.0:
			continue
		z["tick"] = 1.0
		for u in _units_near(foe, z["pos"], cfg["radius"], false):
			_damage_unit(u, cfg["dps"], cfg.get("dmg_type", "fire"))
			if cfg.has("slow"):
				u.slow_timer = maxf(u.slow_timer, 1.2)
				u.slow_factor = maxf(u.slow_factor, cfg["slow"])
	zones = zones.filter(func(z: Dictionary) -> bool: return z["left"] > 0.0)


# ================================================================ krok symulacji

func step(dt: float) -> void:
	if result != 0:
		return
	elapsed += dt
	var earned := income() * dt
	gold += earned
	stats["gold_earned"] += earned

	for cds in ability_cd:
		for a in cds:
			cds[a] = maxf(0.0, cds[a] - dt)
	for u in units:
		u.prev_pos = u.pos
	for s in shots:
		s.prev_pos = s.pos
	var events_at_start := events.size()
	var t := Time.get_ticks_usec() if profile else 0
	_update_strikes(dt)
	_update_respawns(dt)
	_update_waves(dt)
	t = _prof("fale", t)
	_rebuild_grid()
	t = _prof("siatka", t)
	if not zones.is_empty():
		_update_zones(dt)
	for b in buildings:
		_update_building(b, dt)
	t = _prof("budynki", t)
	for u in units:
		if u.hp > 0:
			_update_unit(u, dt)
	t = _prof("jednostki", t)
	_update_shots(dt)
	t = _prof("pociski", t)

	units = units.filter(func(u: Unit) -> bool: return u.hp > 0)
	var building_count := buildings.size()
	buildings = buildings.filter(func(b: Building) -> bool: return b.hp > 0)
	if buildings.size() != building_count:
		layout_version += 1
	shots = shots.filter(func(s: Shot) -> bool: return not s.done)
	t = _prof("sprzątanie", t)
	if profile:
		prof_data["zdarzenia"] = prof_data.get("zdarzenia", 0) + events.size() - events_at_start
		prof_data["kroki"] = prof_data.get("kroki", 0) + 1

	if base_hp[1] <= 0:
		result = 1
	elif base_hp[0] <= 0:
		result = -1
	if result != 0:
		events.append({"type": "end", "result": result})


## Profiler faz kroku (tylko gdy `profile`): dopisuje czas od `t0` w µs do `prof_data[key]`.
func _prof(key: String, t0: int) -> int:
	if not profile:
		return 0
	var now := Time.get_ticks_usec()
	prof_data[key] = prof_data.get(key, 0) + now - t0
	return now


## Salwy typu `strike`: każda salwa rani wrogów rzucającego (także latających) w promieniu.
func _update_strikes(dt: float) -> void:
	for st in strikes:
		st["timer"] -= dt
		if st["timer"] > 0:
			continue
		var cfg: Dictionary = st["cfg"]
		var foe: int = 1 - st["team"]
		st["timer"] = cfg["interval"]
		st["left"] -= 1
		var at: Vector2 = st["pos"]
		events.append({"type": "volley", "pos": at, "radius": cfg["radius"], "team": st["team"]})
		for u in units:
			if u.team == foe and u.hp > 0 and u.pos.distance_to(at) <= cfg["radius"]:
				_damage_unit(u, cfg["dmg"], cfg.get("dmg_type", "blast"))
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
		if spawn_queue.size() > Cfg.MAX_SPAWN_QUEUE:
			spawn_queue.resize(Cfg.MAX_SPAWN_QUEUE)  # nadmiar najnowszej fali przepada
		events.append({"type": "wave", "n": wave, "boss": comp.has("warlord"), "count": comp.size(), "lanes": wave_lanes, "fury": wave == Cfg.ENEMY_FURY_WAVE})
		next_wave_lanes = _plan_lanes(wave + 1)
		if wave % Cfg.ENEMY_BUILD_EVERY == 0:
			_enemy_build()

	var hp_mult: float = difficulty["enemy_hp"] * (1.0 + Cfg.ENEMY_HP_PER_WAVE * maxi(wave - 1, 0)) * enemy_fury()
	spawn_cd -= dt
	if spawn_cd <= 0 and not spawn_queue.is_empty():
		# Każda ścieżka wypuszcza po jednej jednostce naraz — inaczej przy dzielonych
		# falach kolejka rosłaby bez końca, a siła wroga przestałaby rosnąć.
		spawn_cd = maxf(Cfg.MIN_SPAWN_GAP, Cfg.SPAWN_GAP - wave * Cfg.SPAWN_GAP_DECAY)
		var used: Array[int] = []
		var rest: Array[Dictionary] = []
		for e in spawn_queue:
			if used.has(e["lane"]) or team_count[1] >= Cfg.MAX_ENEMIES:
				rest.append(e)  # ścieżka już wypuściła jednostkę albo wróg jest na limicie
			else:
				used.append(e["lane"])
				_spawn_unit(1, e["kind"], 1, hp_mult, e["lane"])
		spawn_queue = rest

	if wave >= 1:
		trickle_timer -= dt
		if trickle_timer <= 0:
			trickle_timer = Cfg.ENEMY_TRICKLE
			if team_count[1] < Cfg.MAX_ENEMIES:
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
	if b.temporary:
		b.life -= dt
		if b.life <= 0.0:
			b.hp = 0.0  # sprzątanie martwych usunie ją w tym kroku (layout_version rośnie)
			events.append({"type": "summon_expired", "pos": b.pos, "team": b.team, "kind": b.kind})
			return
		var cfg := Cfg.building(b.kind)
		if cfg.has("pulse"):
			b.timer += dt
			if b.timer >= cfg["pulse"]:
				b.timer = 0.0
				_building_pulse(b, cfg)
			return
	if b.kind != "basegun" and b.hp < b.max_hp and elapsed - b.last_hit >= Cfg.REGEN_DELAY:
		b.hp = minf(b.max_hp, b.hp + b.max_hp * Cfg.REGEN_RATE * dt)
	if b.kind == "basegun" or Cfg.is_shooter(b.kind):
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
		var period := production_period(b.kind, b.level)
		b.timer = minf(b.timer + dt, period)
		# na limicie armii budynek czeka z gotową jednostką, aż zwolni się miejsce
		if b.timer >= period and team_count[b.team] < Cfg.MAX_ARMY:
			b.timer = 0.0
			_spawn_unit(b.team, Cfg.BUILDINGS[b.kind]["unit"], b.level, 1.0, b.lane)


## Puls budowli tymczasowej: totem leczy swoich, odpychacz cofa wrogów naziemnych.
func _building_pulse(b: Building, cfg: Dictionary) -> void:
	if cfg.has("heal"):
		for u in _units_near(b.team, b.pos, cfg["range"]):
			u.hp = minf(u.max_hp, u.hp + cfg["heal"])
		events.append({"type": "pulse", "pos": b.pos, "radius": cfg["range"], "team": b.team})
	if cfg.has("repel"):
		for u in _units_near(1 - b.team, b.pos, cfg["range"]):
			_repel(u, cfg["repel"])
		events.append({"type": "pulse", "pos": b.pos, "radius": cfg["range"], "team": b.team})


## Cofa jednostkę naziemną o `dist` px wzdłuż jej ścieżki (w stronę jej bazy).
func _repel(u: Unit, dist: float) -> void:
	if u.flying or u.is_hero:
		return
	var lane := lanes[u.lane]
	u.s = clampf(u.s + (-dist if u.team == 0 else dist), 0.0, lane.length)
	u.pos = lane.slot_at(u.s, u.lane_offset)
	u.on_path = true


# ---------------------------------------------------------------- jednostki

func _update_unit(u: Unit, dt: float) -> void:
	if not u.buffs.is_empty():
		_expire_buffs(u)
	if u.is_hero:
		_update_hero(u as Hero, dt)
		return
	var rng_ := u.attack_range
	u.cd_left -= dt
	u.flash = maxf(0.0, u.flash - dt)
	if u.slow_timer > 0.0:
		u.slow_timer -= dt
		if u.slow_timer <= 0.0:
			u.slow_factor = 0.0
	var speed := u.base_speed * (1.0 - u.slow_factor) * u.speed_mult
	var foe_team := 1 - u.team
	var foe_base := base_pos(foe_team)
	var base_in_range := u.pos.distance_to(foe_base) <= rng_ + Cfg.BASE_R

	if u.flying:
		if base_in_range:
			if u.cd_left <= 0:
				u.cd_left = u.cooldown / u.attack_speed
				_damage_base(foe_team, u.dmg * u.dmg_mult)
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
				u.cd_left = u.cooldown / u.attack_speed
				_melee_hit(u, foe)
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
					u.cd_left = u.cooldown / u.attack_speed
					_damage_building(tb, u.dmg * u.dmg_mult)
					events.append({"type": "hit", "pos": tb.pos})
			else:
				_ranged_attack(u, tb.pos, null, tb, -1)
			return
		if base_in_range:
			if u.melee:
				if u.cd_left <= 0:
					u.cd_left = u.cooldown / u.attack_speed
					_damage_base(foe_team, u.dmg * u.dmg_mult)
			else:
				_ranged_attack(u, foe_base, null, null, foe_team)
			return
		_follow_lane(u, lanes[u.lane].length if u.team == 0 else 0.0, speed * dt)
	else:
		_follow_lane(u, _rally_s(u), speed * dt)


## Maszyna stanów dowódcy (opis przy klasie Hero). Martwego obsługuje `_update_respawns`.
func _update_hero(h: Hero, dt: float) -> void:
	h.cd_left -= dt
	h.flash = maxf(0.0, h.flash - dt)
	h.invulnerable = maxf(0.0, h.invulnerable - dt)
	if h.slow_timer > 0.0:
		h.slow_timer -= dt
		if h.slow_timer <= 0.0:
			h.slow_factor = 0.0
	var step_len := h.base_speed * (1.0 - h.slow_factor) * h.speed_mult * dt
	var foe_team := 1 - h.team
	match h.state:
		"march":
			if _walk_path(h, step_len):
				h.state = "idle"
		"back":
			if _walk_path(h, step_len):
				h.state = "idle"
		"idle", "fight":
			var sight := h.attack_range + Cfg.AGGRO
			var foe := _nearest_unit(foe_team, h.pos, sight, h.anti_air)
			if foe != null and foe.pos.distance_to(h.post) > Cfg.COMMANDER_LEASH + h.attack_range:
				foe = null  # za daleko od punktu — nie goni
			var tb: Building = null
			if foe == null:
				tb = _nearest_building(foe_team, h.pos, h.attack_range + Cfg.BUILDING_AGGRO)
				if tb != null and tb.pos.distance_to(h.post) > Cfg.COMMANDER_LEASH + h.attack_range:
					tb = null
			if foe == null and tb == null:
				if h.pos.distance_to(h.post) > 1.0:
					_hero_return(h)
				else:
					h.state = "idle"
				return
			h.state = "fight"
			var target_pos := foe.pos if foe != null else tb.pos
			var reach := h.attack_range + h.radius + (foe.radius if foe != null else BUILDING_R)
			if h.pos.distance_to(target_pos) > reach:
				var next := h.pos.move_toward(target_pos, step_len)
				if next.distance_to(h.post) > Cfg.COMMANDER_LEASH:
					_hero_return(h)  # smycz — wraca do punktu
					return
				h.pos = next
			elif h.cd_left <= 0:
				if h.melee:
					h.cd_left = h.cooldown / h.attack_speed
					if foe != null:
						_melee_hit(h, foe)
					else:
						_damage_building(tb, h.dmg * h.dmg_mult * h.building_mult)
					events.append({"type": "hit", "pos": target_pos})
				else:
					_ranged_attack(h, target_pos, foe, tb, -1)


## Powrót do punktu postoju trasą (ignoruje wrogów, żeby nie szarpać się na granicy smyczy).
func _hero_return(h: Hero) -> void:
	h.state = "back"
	h.path = path_to(h.pos, h.post)
	h.path_i = 1


## Krok po trasie dowódcy. true = dotarł do końca.
func _walk_path(h: Hero, step_len: float) -> bool:
	while h.path_i < h.path.size():
		var p := h.path[h.path_i]
		var d := h.pos.distance_to(p)
		if d > step_len:
			h.pos = h.pos.move_toward(p, step_len)
			return false
		h.pos = p
		step_len -= d
		h.path_i += 1
	return true


## Martwi dowódcy: odliczanie i odrodzenie przy bazie.
func _update_respawns(dt: float) -> void:
	for h in heroes:
		if h == null or h.state != "dead":
			continue
		h.respawn -= dt
		if h.respawn > 0.0:
			continue
		h.pos = _hero_spawn_pos(h.team)
		h.prev_pos = h.pos
		h.post = h.pos
		h.hp = h.max_hp
		h.slow_timer = 0.0
		h.slow_factor = 0.0
		h.invulnerable = Cfg.COMMANDER_INVULNERABLE
		h.state = "idle"
		units.append(h)
		events.append({"type": "hero_respawn", "team": h.team, "pos": h.pos})


## Miejsce pojawienia się dowódcy: tuż przed bazą, w stronę środka mapy.
func _hero_spawn_pos(team: int) -> Vector2:
	var b := base_pos(team)
	return b + (size / 2.0 - b).normalized() * (Cfg.BASE_R + 24.0)


func _make_hero(team: int, id: String) -> Hero:
	var c: Dictionary = Cfg.COMMANDERS[id]
	var h := Hero.new()
	h.id = _take_id()
	h.team = team
	h.kind = id
	h.commander = id
	h.is_hero = true
	h.radius = c["r"]
	h.attack_range = c["range"]
	h.base_speed = c["speed"]
	h.cooldown = c["cd"]
	h.projectile = c["projectile"]
	h.splash = c.get("splash", 0.0)
	h.melee = h.projectile == ""
	h.anti_air = c["anti_air"]
	h.armor = c["armor"]
	h.max_hp = c["hp"]
	h.hp = h.max_hp
	h.dmg = c["dmg"]
	h.building_mult = c.get("building_mult", Cfg.COMMANDER_BUILDING_MULT)
	h.building_dmg = h.dmg * h.building_mult
	h.lane = 0
	h.on_path = false
	h.pos = _hero_spawn_pos(team)
	h.prev_pos = h.pos
	h.post = h.pos
	units.append(h)
	return h


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


## Cios wręcz z mnożnikiem obrażeń i wysysaniem życia (wzmocnienia).
func _melee_hit(u: Unit, foe: Unit) -> void:
	var dmg := u.dmg * u.dmg_mult
	_damage_unit(foe, dmg, "melee")
	if u.lifesteal > 0.0:
		u.hp = minf(u.max_hp, u.hp + dmg * u.lifesteal)


## Wzmocnienie jednostki (typ `buff`): ta sama statystyka nie kumuluje się — liczy się
## mocniejsza wartość i dłuższy czas.
func _apply_buff(u: Unit, stat: String, value: float, duration: float) -> void:
	var cur: Array = u.buffs.get(stat, [value, 0.0])
	u.buffs[stat] = [maxf(cur[0], value), maxf(cur[1], elapsed + duration)]
	_refresh_buffs(u)


func _expire_buffs(u: Unit) -> void:
	var changed := false
	for stat in u.buffs.keys():
		if u.buffs[stat][1] <= elapsed:
			u.buffs.erase(stat)
			changed = true
	if changed:
		_refresh_buffs(u)


func _refresh_buffs(u: Unit) -> void:
	u.dmg_mult = u.buffs["dmg"][0] if u.buffs.has("dmg") else 1.0
	u.speed_mult = u.buffs["speed"][0] if u.buffs.has("speed") else 1.0
	u.attack_speed = u.buffs["attack_speed"][0] if u.buffs.has("attack_speed") else 1.0
	u.armor_bonus = u.buffs["armor"][0] if u.buffs.has("armor") else 0.0
	u.lifesteal = u.buffs["lifesteal"][0] if u.buffs.has("lifesteal") else 0.0


func _ranged_attack(u: Unit, at: Vector2, unit: Unit, building: Building, base_team: int) -> void:
	if u.cd_left > 0:
		return
	u.cd_left = u.cooldown / u.attack_speed
	var s := _fire(u.team, u.projectile, u.pos, at, u.dmg * u.dmg_mult, u.splash)
	s.building_dmg = u.building_dmg * u.dmg_mult
	s.target_unit = unit
	s.target_building = building
	s.target_base = base_team
	s.no_base = u.is_hero


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
	u.armor = st.get("armor", 0.0)
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
	if team == 1:
		u.dmg *= enemy_fury()
	u.building_dmg = st.get("building_dmg", 0.0) * (1.0 + Cfg.UNIT_DMG_PER_LEVEL * (lvl - 1))
	u.prev_pos = u.pos
	units.append(u)
	team_count[team] += 1
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
	s.prev_pos = from
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
			if not s.no_base and (s.target_base == foe_team or base_pos(foe_team).distance_to(s.target_pos) <= s.splash + Cfg.BASE_R):
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
	if u.is_hero and (u as Hero).invulnerable > 0.0:
		return
	if kind == "arrow":
		dmg *= 1.0 - minf(u.armor + u.armor_bonus, Cfg.MAX_ARMOR)
	u.hp -= dmg
	u.flash = 0.12
	if u.hp > 0:
		return
	if u.is_hero:
		var h := u as Hero
		h.state = "dead"
		h.respawn = Cfg.commander_respawn(wave)
		events.append({"type": "hero_died", "pos": h.pos, "team": h.team, "respawn": h.respawn})
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
	if b.temporary:
		return  # bez nagrody i bez liczenia strat (R7)
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
	team_count = [0, 0]
	for u in units:
		if u.hp > 0:
			_grid_add(_grid[u.team], u.pos, u)
			if not u.is_hero:
				team_count[u.team] += 1
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


## Żywe jednostki drużyny `team` w promieniu `r` (środek + promień jednostki) — przez siatkę.
## Siatka jest z początku kroku, więc jednostki przywołane w tym kroku pomija (bez znaczenia).
func _units_near(team: int, from: Vector2, r: float, air := true) -> Array[Unit]:
	var out: Array[Unit] = []
	var reach := r + 20.0  # zapas na promień jednostki i przesunięcie od przebudowy siatki
	var cells: Dictionary = _grid[team]
	for gx in range(floori((from.x - reach) / GRID_CELL), floori((from.x + reach) / GRID_CELL) + 1):
		for gy in range(floori((from.y - reach) / GRID_CELL), floori((from.y + reach) / GRID_CELL) + 1):
			var bucket: Variant = cells.get(Vector2i(gx, gy))
			if bucket == null:
				continue
			for o: Unit in bucket:
				if o.hp > 0 and (air or not o.flying) and from.distance_to(o.pos) <= r + o.radius:
					out.append(o)
	return out


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
	b.max_hp = INF if kind == "basegun" else Cfg.building(kind)["hp"]
	b.hp = b.max_hp
	buildings.append(b)
	layout_version += 1
	return b


func _level_up(b: Building) -> void:
	b.level += 1
	var new_max: float = Cfg.BUILDINGS[b.kind]["hp"] * (1.0 + 0.3 * (b.level - 1))
	b.hp += new_max - b.max_hp
	b.max_hp = new_max


func _take_id() -> int:
	_next_id += 1
	return _next_id


# ---------------------------------------------------------------- rzeka i nawigacja

## Rzeka z punktów mapy i mosty: kolejne próbki ścieżki (co BRIDGE_STEP), które leżą nad wodą.
func _find_bridges() -> void:
	if level["river"].is_empty():
		return
	river = Cfg.smooth_curve(level["river"], 6.0)
	for li in lanes.size():
		var lane := lanes[li]
		var start := -1.0
		var last := -1.0
		var s := 0.0
		while s <= lane.length:
			if river_distance(lane.point_at(s)) < Cfg.RIVER_HALF + BRIDGE_MARGIN:
				if start < 0.0:
					start = s
				last = s
			elif start >= 0.0:
				bridges.append({"lane": li, "s0": start, "s1": last})
				start = -1.0
			s += BRIDGE_STEP
		if start >= 0.0:
			bridges.append({"lane": li, "s0": start, "s1": last})


## Siatka A*: woda (z zapasem NAV_CLEARANCE) zablokowana, mosty przejezdne. Pas mostu to
## pola w odległości PATH_HALF od osi ścieżki, przedłużony za brzeg o zapas i jedno pole,
## żeby przejście przez cały zablokowany pas było ciągłe. Budynki, drzewa i bazy nie blokują.
func _ensure_nav() -> void:
	if _nav != null:
		return
	_nav = AStarGrid2D.new()
	_nav.region = Rect2i(0, 0, ceili(size.x / NAV_CELL), ceili(size.y / NAV_CELL))
	_nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
	_nav.offset = Vector2(NAV_CELL, NAV_CELL) / 2.0  # get_point_path zwraca środki pól
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.update()
	if river == null:
		return
	var extend := NAV_CLEARANCE - BRIDGE_MARGIN + NAV_CELL
	for br in bridges:
		var lane := lanes[br["lane"]]
		var s: float = br["s0"] - extend
		while s <= br["s1"] + extend:
			var p := lane.point_at(s)
			var c := _nav_cell(p)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var cell := c + Vector2i(dx, dy)
					if _nav.is_in_boundsv(cell) and _nav_center(cell).distance_to(p) <= Cfg.PATH_HALF:
						_nav_bridge[cell] = br["lane"]
			s += NAV_CELL / 4.0
	for y in _nav.region.size.y:
		for x in _nav.region.size.x:
			var cell := Vector2i(x, y)
			var d := river_distance(_nav_center(cell))
			if d < Cfg.RIVER_HALF + NAV_CLEARANCE + NAV_CELL:
				_nav_near[cell] = true
			if d < Cfg.RIVER_HALF + NAV_CLEARANCE and not _nav_bridge.has(cell):
				_nav.set_point_solid(cell, true)


func _nav_cell(p: Vector2) -> Vector2i:
	var r := _nav.region.size
	return Vector2i(clampi(floori(p.x / NAV_CELL), 0, r.x - 1), clampi(floori(p.y / NAV_CELL), 0, r.y - 1))


func _nav_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * NAV_CELL


## Najbliższe przejezdne pole (szukane w coraz większych kwadratach wokół punktu).
func _nav_walkable_near(p: Vector2) -> Vector2i:
	var c := _nav_cell(p)
	if not _nav.is_point_solid(c):
		return c
	for r in range(1, maxi(_nav.region.size.x, _nav.region.size.y)):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue  # tylko obwód kwadratu — środek sprawdzony wcześniej
				var cell := c + Vector2i(dx, dy)
				if _nav.is_in_boundsv(cell) and not _nav.is_point_solid(cell):
					var d := _nav_center(cell).distance_squared_to(p)
					if d < best_d:
						best_d = d
						best = cell
		if best.x >= 0:
			return best
	return c


## Czy punkt jest „na lądzie” dla dowódcy: w przejezdnym polu i nie w wodzie, a nad wodą
## tylko na moście (w szerokości ścieżki). Środek pola bywa daleko od wody, a jego róg blisko.
func _nav_point_ok(p: Vector2) -> bool:
	var cell := _nav_cell(p)
	if _nav.is_point_solid(cell):
		return false
	if not _nav_near.has(cell) or river_distance(p) >= Cfg.RIVER_HALF + NAV_CLEARANCE / 2.0:
		return true
	return _nav_bridge.has(cell) and lanes[_nav_bridge[cell]].distance_to(p) <= Cfg.PATH_HALF


func _nav_segment_ok(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / NAV_SAMPLE)
	for i in range(1, n + 1):
		if not _nav_point_ok(a.lerp(b, float(i) / n)):
			return false
	return true


# ================================================================ zapytania: rzeka i trasa

## Odległość od osi rzeki (INF, gdy mapa nie ma rzeki).
func river_distance(p: Vector2) -> float:
	return INF if river == null else river.get_closest_point(p).distance_to(p)


## Trasa dowódcy z `from` do `to`: omija wodę, rzekę przechodzi po mostach. Cel na wodzie,
## poza mapą albo nieosiągalny → najbliższe przejezdne miejsce. Trasa wygładzona (odcinki
## na przełaj, póki nie wchodzą w wodę). Zwraca [start, …, cel].
func path_to(from: Vector2, to: Vector2) -> PackedVector2Array:
	_ensure_nav()
	var start := from.clamp(Vector2.ZERO, size)
	var goal := to.clamp(Vector2.ZERO, size)
	var goal_cell := _nav_walkable_near(goal)
	if not _nav_point_ok(goal):
		goal = _nav_center(goal_cell)
	var cells := _nav.get_id_path(_nav_walkable_near(start), goal_cell)
	if cells.is_empty():
		return PackedVector2Array([start])  # brak przejścia — zostań w miejscu
	var raw := PackedVector2Array([start])
	for i in range(1, cells.size() - 1):
		raw.append(_nav_center(cells[i]))
	raw.append(goal)
	# wygładzanie „po sznurku" jednym przejściem: punkt pośredni zostaje tylko wtedy, gdy
	# prosty odcinek od ostatniego zachowanego punktu do następnego wszedłby w wodę
	var out := PackedVector2Array([raw[0]])
	for k in range(1, raw.size() - 1):
		if not _nav_segment_ok(out[-1], raw[k + 1]):
			out.append(raw[k])
	out.append(raw[-1])
	return out
