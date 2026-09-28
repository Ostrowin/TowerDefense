class_name AbilityRules
extends RefCounted
## Reguły rzucania umiejętności dowódcy (R9) — po typie efektu, nie po umiejętności, więc nowy dowódca
## z istniejących typów nie wymaga zmian. Wspólne dla AI dowódcy wroga (`EnemyCommander`) i bota
## gracza w testach. Tylko komendy Sim (`Sim.apply`) i bez losowania —
## ten sam stan gry daje te same decyzje (warunek gry sieciowej w lockstepie).
##
## Kierunek: ścieżki biegną od bazy gracza (s = 0) do bazy wroga (s = długość). „Czoło” wrogów to
## jednostka najbliżej naszej bazy; „przed czołem” = od strony naszej bazy.


## Wszystkie gotowe umiejętności dowódcy gracza (bez rasowej) według reguł typu.
static func cast_hero_abilities(sim: Sim, player: int) -> void:
	if not sim.hero_alive(player):
		return
	for a in sim.players[player].ability_order:
		if sim.ability_ready(a, player) and not Cfg.RACIAL.values().has(a):
			cast(sim, player, a)


## Awans: bierze „moc”, jeśli jest w ofercie, inaczej pierwszą opcję. true = wybrano.
static func pick_upgrade(sim: Sim, player: int) -> bool:
	var offers: Array = sim.players[player].hero_offers
	if offers.is_empty():
		return false
	var offer: Array = offers[0]
	return sim.apply({"player": player, "type": "choose_upgrade",
		"i": 1 if offer[1]["kind"] == "power" and offer[0]["kind"] != "power" else 0})


## Umiejętność rasy: leczenie — gdy rannych swoich (< 60% HP) jest ≥ 8; reszta — na ścieżkę,
## którą idzie ≥ 6 własnych jednostek (`attacking` = false wstrzymuje, np. postawa „Obrona” gracza).
static func cast_racial(sim: Sim, player: int, attacking := true) -> void:
	var team := sim.players[player].team
	var racial := ""
	for a in sim.players[player].ability_order:
		if Cfg.RACIAL.values().has(a):
			racial = a
	if racial == "" or not sim.ability_ready(racial, player):
		return
	var cfg: Dictionary = sim.ability_config(racial, player)
	if cfg["kind"] == "heal":
		var hurt := sim.units.filter(func(u: Sim.Unit) -> bool: return u.team == team and u.hp > 0 and u.hp < u.max_hp * 0.6)
		if hurt.size() >= 8:
			_use(sim, player, racial, Vector2.ZERO)
		return
	if cfg["kind"] == "bounty_buff" and team == 1:
		return  # łupy liczą się tylko graczowi
	if not attacking:
		return
	var per_lane := {}
	for u in sim.units:
		if u.team == team and not u.flying and not u.is_hero and u.burrow <= 0.0:
			per_lane[u.lane] = per_lane.get(u.lane, 0) + 1
	for li in per_lane:
		if per_lane[li] >= 6:
			_use(sim, player, racial, sim.lanes[li].point_at(sim.lanes[li].length / 2.0))
			return


## Kiedy i gdzie rzucić umiejętność danego typu (wszystko w zasięgu od dowódcy).
static func cast(sim: Sim, player: int, a: String) -> void:
	var team := sim.players[player].team
	var cfg: Dictionary = sim.ability_config(a, player)
	var h := sim.hero(player)
	var fwd := 1.0 if team == 0 else -1.0  # w stronę bazy przeciwnika
	var reach: float = cfg["cast_range"] if cfg["cast_range"] > 0.0 else 1e9
	var foes: Array[Sim.Unit] = []
	for u in sim.units:
		if u.team != team and u.hp > 0 and u.pos.distance_to(h.pos) <= reach:
			foes.append(u)
	match cfg["kind"]:
		"pull":
			var big: Sim.Unit = null
			for u in foes:
				if u.hp >= 150.0 and not u.flying and not u.is_hero and u.kind != "warlord" and (big == null or u.hp > big.hp):
					big = u
			if big != null and h.hp >= h.max_hp * 0.5:
				_use(sim, player, a, big.pos)
		"taunt":
			var close := foes.filter(func(u: Sim.Unit) -> bool: return not u.flying and u.pos.distance_to(h.pos) <= cfg["radius"])
			if close.size() >= 3 and h.hp >= h.max_hp * 0.5:
				_use(sim, player, a, Vector2.ZERO)
		"leap":
			if h.hp < h.max_hp * 0.5:
				return
			for u in foes:
				var n := 0
				for o in foes:
					if o.pos.distance_to(u.pos) <= cfg["radius"]:
						n += 1
				if n >= 3 and sim.ability_target_ok(a, u.pos, player):
					_use(sim, player, a, u.pos)
					return
		"strike", "line", "repel", "weaken", "raise_dead":
			var r: float = cfg.get("radius", 60.0)
			if not cfg["target"]:
				r = cfg["radius"]  # „wokół siebie" — grupa musi stać przy dowódcy
				foes.assign(foes.filter(func(u: Sim.Unit) -> bool: return u.pos.distance_to(h.pos) <= r))
			var best := _densest(foes, r, 2)
			if best != Vector2.INF:
				_use(sim, player, a, best if cfg["target"] else Vector2.ZERO)
		"zone":
			# na ścieżce 60 px przed czołem grupy
			var lead := _lead(foes, fwd)
			if lead != null:
				_use(sim, player, a, sim.lanes[lead.lane].point_at(lead.s - 60.0 * fwd))
		"summon_building":
			if foes.is_empty():
				return
			for b in sim.buildings:
				if b.team == team and Cfg.is_shooter(b.kind) and b.pos.distance_to(h.pos) < 150.0:
					return
			var target := foes[0].pos
			var best := Vector2.INF
			for dx in range(-4, 5):
				for dy in range(-4, 5):
					var c := Cfg.snap(h.pos + Vector2(dx, dy) * Cfg.GRID)
					if sim.ability_target_ok(a, c, player) and (best == Vector2.INF or c.distance_to(target) < best.distance_to(target)):
						best = c
			if best != Vector2.INF:
				_use(sim, player, a, best)
		"summon_units":
			var ground := foes.filter(func(u: Sim.Unit) -> bool: return not u.flying)
			if ground.size() >= 3:
				var u: Sim.Unit = ground[0]
				var lane: Sim.Lane = sim.lanes[u.lane]
				var s := u.s - 60.0 * fwd
				s = maxf(s, 80.0) if team == 0 else minf(s, lane.length - 80.0)
				_use(sim, player, a, lane.point_at(s))
		"buff":
			var own := 0
			for u in sim.units:
				if u.team == team and not u.is_hero and u.pos.distance_to(h.pos) <= maxf(cfg.get("radius", 120.0), 120.0):
					own += 1
			if own >= 4 and not foes.is_empty():
				_use(sim, player, a, h.pos)
		"execute":
			var big: Sim.Unit = null
			for u in foes:
				if u.hp >= 150.0 and (big == null or u.hp > big.hp):
					big = u
			if big != null:
				_use(sim, player, a, big.pos)
		"demolish":
			var near: Sim.Building = null
			for b in sim.buildings:
				if b.team != team and b.kind != "basegun" and b.pos.distance_to(h.pos) <= reach:
					if near == null or b.pos.distance_to(h.pos) < near.pos.distance_to(h.pos):
						near = b
			if near != null:
				_use(sim, player, a, near.pos)
		"global":
			if sim.base_hp[team] < Cfg.BASE_HP[team] * 0.6:
				_use(sim, player, a, Vector2.ZERO)
		"heal":
			if not cfg["target"] and h.hp < h.max_hp * 0.5:  # leczenie wokół siebie — ratuje dowódcę
				_use(sim, player, a, Vector2.ZERO)
				return
			# tam, gdzie w promieniu jest najwięcej rannych swoich (poniżej 60% HP)
			var hurt: Array[Sim.Unit] = []
			for u in sim.units:
				if u.team == team and u.hp > 0 and u.hp < u.max_hp * 0.6 and u.pos.distance_to(h.pos) <= reach:
					hurt.append(u)
			var best := _densest(hurt, cfg["radius"], 3)
			if best != Vector2.INF:
				_use(sim, player, a, best if cfg["target"] else Vector2.ZERO)


## Komenda rzucenia umiejętności (`Sim.apply`) — ta sama droga co u gracza.
static func _use(sim: Sim, player: int, a: String, at: Vector2) -> bool:
	return sim.apply({"player": player, "type": "use_ability", "ability": a, "at": at})


## Pozycja jednostki, wokół której w promieniu `r` stoi najwięcej innych (więcej niż `min_n`).
static func _densest(list: Array[Sim.Unit], r: float, min_n: int) -> Vector2:
	var best := Vector2.INF
	var best_n := min_n
	for u in list:
		var n := 0
		for o in list:
			if o.pos.distance_to(u.pos) <= r:
				n += 1
		if n > best_n:
			best_n = n
			best = u.pos
	return best


## Czoło wrogów naziemnych: najbliżej bazy drużyny, która patrzy w kierunku `fwd`.
static func _lead(foes: Array[Sim.Unit], fwd: float) -> Sim.Unit:
	var lead: Sim.Unit = null
	for u in foes:
		if not u.flying and not u.is_hero and (lead == null or u.s * fwd < lead.s * fwd):
			lead = u
	return lead
