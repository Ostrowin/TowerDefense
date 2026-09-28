class_name EnemyCommander
extends RefCounted
## AI dowódcy wroga (drużyna 1). Wydaje te same rozkazy co gracz (`order_hero`, `use_ability`,
## `choose_upgrade`), co THINK sekund z `Sim.step`, bez losowania — w grze sieciowej drugi gracz
## po prostu zajmie jego miejsce.
##
## Gdzie stoi (punkt postoju; sam dowódca walczy z tym, co podejdzie — smycz COMMANDER_LEASH):
##   HP < RETREAT_HP             → pod własną bazą (dowódca się nie leczy; tam pomaga działko i wieże)
##   armia gracza na naszej połowie → na tej ścieżce, między jej czołem a naszą bazą (obrona)
##   nasza fala na mapie          → za czołem fali na ścieżce, gdzie idzie jej najwięcej (natarcie)
##   inaczej                      → przed bazą, na ścieżce następnej fali (czeka)
## Natarcie kończy się MIN_S od bazy gracza — dowódca nie wchodzi pod jego fortecę.

const THINK := 0.5
const RETREAT_HP := 0.3
const MIN_S := 350.0  ## najbliżej bazy gracza (wzdłuż ścieżki)
const GUARD_S := 250.0  ## czekanie: tyle przed własną bazą
const REORDER := 60.0  ## nowy rozkaz, gdy punkt postoju zmienia się o więcej

## Sim przychodzi w każdym wywołaniu, nie jest polem: Sim trzyma AI, a cykl referencji między
## dwoma RefCounted nigdy by się nie zwolnił (każda partia zostawałaby w pamięci).
var team := 1


func _init(team_ := 1) -> void:
	team = team_


func think(sim: Sim) -> void:
	AbilityRules.pick_upgrade(sim, team)
	AbilityRules.cast_racial(sim, team)
	if not sim.hero_alive(team):
		return
	var h := sim.hero(team)
	var post := _desired_post(sim, h)
	if h.post.distance_to(post) > REORDER and h.state != "march":
		sim.order_hero(post, team)
	AbilityRules.cast_hero_abilities(sim, team)


func _desired_post(sim: Sim, h: Sim.Hero) -> Vector2:
	if h.hp < h.max_hp * RETREAT_HP:
		return sim._hero_spawn_pos(team)
	# odległość wzdłuż ścieżki mierzona od bazy gracza (s), nasza baza na końcu (length)
	var foe_count := {}
	var foe_front := {}  # ścieżka → największe s wroga (najbliżej nas)
	var own_count := {}
	var own_front := {}  # ścieżka → najmniejsze s naszych (czoło natarcia)
	for u in sim.units:
		if u.hp <= 0 or u.flying or u.is_hero:
			continue
		if u.team == team:
			own_count[u.lane] = own_count.get(u.lane, 0) + 1
			own_front[u.lane] = minf(own_front.get(u.lane, INF), u.s)
		else:
			foe_count[u.lane] = foe_count.get(u.lane, 0) + 1
			foe_front[u.lane] = maxf(foe_front.get(u.lane, -INF), u.s)
	# obrona: ścieżka, na której armia gracza weszła najgłębiej na naszą połowę
	var threat := -1
	for li in foe_front:
		var lane: Sim.Lane = sim.lanes[li]
		if foe_front[li] > lane.length * 0.5 and (threat < 0 or foe_front[li] / lane.length > foe_front[threat] / sim.lanes[threat].length):
			threat = li
	if threat >= 0:
		var lane: Sim.Lane = sim.lanes[threat]
		return lane.point_at(minf(foe_front[threat] + 40.0, lane.length - GUARD_S * 0.5))
	# natarcie: tam, gdzie idzie najwięcej naszych
	var push := -1
	for li in own_count:
		if push < 0 or own_count[li] > own_count[push]:
			push = li
	if push >= 0 and own_count[push] >= 3:
		var lane: Sim.Lane = sim.lanes[push]
		return lane.point_at(clampf(own_front[push] + 50.0, MIN_S, lane.length - GUARD_S))
	var wait: Sim.Lane = sim.lanes[sim.next_wave_lanes[0]]
	return wait.point_at(wait.length - GUARD_S)
