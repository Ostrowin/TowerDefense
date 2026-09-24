extends Node2D
## Prototyp lane-pushera TD. Cała gra w jednym skrypcie — celowo, na etapie prototypu
## (szybka iteracja nad zabawą). Rozbijemy na sceny, gdy mechaniki się ustabilizują.
##
## Pętla: złoto (pasywne + wydobywacze) → koszary/strzelnice spawnują jednostki →
## jednostki same idą linią do bazy wroga → wieże strzelają → zniszcz bazę = wygrana.

const W := 1280.0
const H := 720.0
const LANE_Y := 360.0
const LANE_HALF := 40.0
const GRID := 40.0
const BUILD_MIN_X := 40.0
const BUILD_MAX_X := 600.0
const P_BASE := Vector2(80, LANE_Y)
const E_BASE := Vector2(1200, LANE_Y)
const BASE_HP := 600.0
const BASE_R := 42.0

const START_GOLD := 150.0
const PASSIVE_INCOME := 3.0
const EXTRACTOR_COST := 60
const EXTRACTOR_INCOME := 2.5

const UNIT_TYPES := {
	"soldier": {"hp": 70.0, "dmg": 9.0, "range": 20.0, "cd": 0.8, "speed": 55.0, "r": 9.0, "bounty": 0},
	"archer": {"hp": 35.0, "dmg": 8.0, "range": 110.0, "cd": 1.1, "speed": 50.0, "r": 8.0, "bounty": 0},
	"grunt": {"hp": 55.0, "dmg": 7.0, "range": 20.0, "cd": 0.8, "speed": 48.0, "r": 9.0, "bounty": 6},
	"brute": {"hp": 280.0, "dmg": 20.0, "range": 24.0, "cd": 1.3, "speed": 34.0, "r": 14.0, "bounty": 30},
}
const BUILDINGS := {
	"tower": {"cost": 80, "label": "Wieża", "range": 170.0, "dmg": 14.0, "cd": 0.9},
	"barracks": {"cost": 120, "label": "Koszary", "unit": "soldier", "period": 7.0},
	"range": {"cost": 150, "label": "Strzelnica", "unit": "archer", "period": 9.0},
}
# Działko bazy — żeby pojedyncza jednostka nie zdejmowała bazy za darmo.
const BASE_GUN := {"range": 140.0, "dmg": 10.0, "cd": 1.0}
const RESOURCE_NODES: Array[Vector2] = [Vector2(200, 180), Vector2(420, 560), Vector2(460, 150)]
const ENEMY_TOWERS: Array[Vector2] = [Vector2(900, 280), Vector2(1020, 450)]

const TEAM_COLORS: Array[Color] = [Color(0.35, 0.6, 1.0), Color(1.0, 0.35, 0.3)]


class Unit:
	var team: int
	var kind: String
	var pos: Vector2
	var lane_offset: float
	var hp: float
	var max_hp: float
	var cd_left := 0.0


class Building:
	var team: int
	var kind: String
	var pos: Vector2
	var timer := 0.0
	var cd_left := 0.0
	var hidden := false


class Shot:
	var pos: Vector2
	var target: Unit
	var dmg: float
	var color: Color


var gold := START_GOLD
var base_hp: Array[float] = [BASE_HP, BASE_HP]
var units: Array[Unit] = []
var buildings: Array[Building] = []
var shots: Array[Shot] = []
var taken_nodes: Array[bool] = []
var mode := ""  # "" albo klucz z BUILDINGS
var speed_mult := 1.0
var elapsed := 0.0
var game_over := false
var won := false

var wave := 0
var wave_timer := 20.0
var spawn_queue: Array[String] = []
var spawn_cd := 0.0

var font: Font
var gold_label: Label
var info_label: Label
var build_buttons := {}
var speed_button: Button
var restart_button: Button


func _ready() -> void:
	font = ThemeDB.fallback_font
	randomize()
	taken_nodes.resize(RESOURCE_NODES.size())
	taken_nodes.fill(false)
	_add_building(0, "basegun", P_BASE, true)
	_add_building(1, "basegun", E_BASE, true)
	for p in ENEMY_TOWERS:
		_add_building(1, "tower", p)
	_build_hud()


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	gold_label = Label.new()
	gold_label.position = Vector2(16, 10)
	gold_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(gold_label)

	info_label = Label.new()
	info_label.position = Vector2(16, 44)
	info_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(info_label)

	var bar := HBoxContainer.new()
	bar.position = Vector2(16, H - 72)
	bar.add_theme_constant_override("separation", 10)
	layer.add_child(bar)
	for key in BUILDINGS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 56)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_build_button.bind(key))
		bar.add_child(b)
		build_buttons[key] = b

	speed_button = Button.new()
	speed_button.custom_minimum_size = Vector2(90, 56)
	speed_button.add_theme_font_size_override("font_size", 20)
	speed_button.pressed.connect(_on_speed)
	bar.add_child(speed_button)

	restart_button = Button.new()
	restart_button.text = "Jeszcze raz"
	restart_button.custom_minimum_size = Vector2(220, 64)
	restart_button.add_theme_font_size_override("font_size", 24)
	restart_button.position = Vector2(W / 2 - 110, H / 2 + 40)
	restart_button.visible = false
	restart_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	layer.add_child(restart_button)
	_update_hud()


func _on_build_button(key: String) -> void:
	mode = "" if mode == key else key
	_update_hud()


func _on_speed() -> void:
	speed_mult = 2.0 if speed_mult == 1.0 else 1.0
	_update_hud()


func _income() -> float:
	return PASSIVE_INCOME + taken_nodes.count(true) * EXTRACTOR_INCOME


func _update_hud() -> void:
	gold_label.text = "Złoto: %d  (+%.1f/s)" % [int(gold), _income()]
	var next := "fala %d za %ds" % [wave + 1, ceili(wave_timer)]
	info_label.text = "%s · kliknij złoże (●) = wydobywacz %dzł · PPM anuluje" % [next, EXTRACTOR_COST]
	for key in build_buttons:
		var b: Button = build_buttons[key]
		var cfg: Dictionary = BUILDINGS[key]
		b.text = "%s  %d" % [cfg["label"], cfg["cost"]]
		b.button_pressed = mode == key
		b.disabled = gold < cfg["cost"] and mode != key
	speed_button.text = "x%d" % int(speed_mult)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mode = ""
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_on_tap(get_global_mouse_position())
		_update_hud()


func _on_tap(p: Vector2) -> void:
	for i in RESOURCE_NODES.size():
		if p.distance_to(RESOURCE_NODES[i]) < 30.0:
			if not taken_nodes[i] and gold >= EXTRACTOR_COST:
				gold -= EXTRACTOR_COST
				taken_nodes[i] = true
			return
	if mode == "":
		return
	var cell := _snap(p)
	var cost: int = BUILDINGS[mode]["cost"]
	if _can_place(cell) and gold >= cost:
		gold -= cost
		_add_building(0, mode, cell)
		if gold < cost:
			mode = ""


func _snap(p: Vector2) -> Vector2:
	return (p / GRID).floor() * GRID + Vector2(GRID, GRID) / 2


func _can_place(c: Vector2) -> bool:
	if c.x < BUILD_MIN_X or c.x > BUILD_MAX_X or c.y < 80 or c.y > H - 100:
		return false
	if absf(c.y - LANE_Y) < LANE_HALF + GRID / 2:
		return false
	if c.distance_to(P_BASE) < BASE_R + GRID:
		return false
	for n in RESOURCE_NODES:
		if c.distance_to(n) < GRID:
			return false
	for b in buildings:
		if not b.hidden and c.distance_to(b.pos) < GRID * 0.9:
			return false
	return true


# ---------------------------------------------------------------- sim

func _process(delta: float) -> void:
	if not game_over:
		var dt := delta * speed_mult
		elapsed += dt
		gold += _income() * dt
		_update_enemy_script(dt)
		_update_buildings(dt)
		_update_units(dt)
		_update_shots(dt)
		units = units.filter(func(u: Unit) -> bool: return u.hp > 0)
		if base_hp[1] <= 0 or base_hp[0] <= 0:
			_end(base_hp[1] <= 0)
		_update_hud()
	queue_redraw()


func _end(player_won: bool) -> void:
	game_over = true
	won = player_won
	mode = ""
	restart_button.visible = true


## Skryptowany wróg: fale rosnące co ~20 s, co 4. fala dochodzi „brute".
func _update_enemy_script(dt: float) -> void:
	wave_timer -= dt
	if wave_timer <= 0:
		wave += 1
		wave_timer = maxf(12.0, 22.0 - wave * 0.5)
		for i in 2 + wave:
			spawn_queue.append("grunt")
		for i in wave / 4:
			spawn_queue.append("brute")
	spawn_cd -= dt
	if spawn_cd <= 0 and not spawn_queue.is_empty():
		spawn_cd = 0.7
		_spawn_unit(1, spawn_queue.pop_front())


func _add_building(team: int, kind: String, pos: Vector2, hidden := false) -> void:
	var b := Building.new()
	b.team = team
	b.kind = kind
	b.pos = pos
	b.hidden = hidden
	buildings.append(b)


func _spawn_unit(team: int, kind: String) -> void:
	var st: Dictionary = UNIT_TYPES[kind]
	var u := Unit.new()
	u.team = team
	u.kind = kind
	u.lane_offset = randf_range(-LANE_HALF + 12, LANE_HALF - 12)
	var base := P_BASE if team == 0 else E_BASE
	u.pos = base + Vector2((BASE_R + 10) * (1 if team == 0 else -1), u.lane_offset)
	u.hp = st["hp"]
	u.max_hp = st["hp"]
	units.append(u)


func _update_buildings(dt: float) -> void:
	for b in buildings:
		if b.kind == "tower" or b.kind == "basegun":
			var cfg: Dictionary = BUILDINGS["tower"] if b.kind == "tower" else BASE_GUN
			b.cd_left -= dt
			if b.cd_left <= 0:
				var target := _nearest_foe(b.team, b.pos, cfg["range"])
				if target:
					b.cd_left = cfg["cd"]
					_fire(b.pos, target, cfg["dmg"], TEAM_COLORS[b.team].lightened(0.4))
		else:
			var cfg: Dictionary = BUILDINGS[b.kind]
			b.timer += dt
			if b.timer >= cfg["period"]:
				b.timer = 0.0
				_spawn_unit(b.team, cfg["unit"])


func _update_units(dt: float) -> void:
	for u in units:
		if u.hp <= 0:
			continue
		var st: Dictionary = UNIT_TYPES[u.kind]
		var rng: float = st["range"]
		u.cd_left -= dt
		var dir := 1.0 if u.team == 0 else -1.0
		var foe := _nearest_foe(u.team, u.pos, rng + 70.0)
		var foe_base := E_BASE if u.team == 0 else P_BASE
		if foe:
			var reach: float = rng + st["r"] + UNIT_TYPES[foe.kind]["r"]
			if u.pos.distance_to(foe.pos) <= reach:
				_attack(u, st, foe)
			else:
				u.pos = u.pos.move_toward(foe.pos, st["speed"] * dt)
		elif absf(u.pos.x - foe_base.x) <= rng + BASE_R:
			if u.cd_left <= 0:
				u.cd_left = st["cd"]
				base_hp[1 - u.team] -= st["dmg"]
		else:
			var goal := Vector2(u.pos.x + dir * 100.0, LANE_Y + u.lane_offset)
			u.pos = u.pos.move_toward(goal, st["speed"] * dt)


func _attack(u: Unit, st: Dictionary, foe: Unit) -> void:
	if u.cd_left > 0:
		return
	u.cd_left = st["cd"]
	if st["range"] > 40.0:
		_fire(u.pos, foe, st["dmg"], TEAM_COLORS[u.team])
	else:
		_damage(foe, st["dmg"])


func _nearest_foe(team: int, from: Vector2, max_dist: float) -> Unit:
	var best: Unit = null
	var best_d := max_dist
	for o in units:
		if o.team != team and o.hp > 0:
			var d := from.distance_to(o.pos)
			if d <= best_d:
				best_d = d
				best = o
	return best


func _fire(from: Vector2, target: Unit, dmg: float, color: Color) -> void:
	var s := Shot.new()
	s.pos = from
	s.target = target
	s.dmg = dmg
	s.color = color
	shots.append(s)


func _update_shots(dt: float) -> void:
	for s in shots:
		if s.target.hp <= 0:
			s.dmg = 0.0
			continue
		s.pos = s.pos.move_toward(s.target.pos, 420.0 * dt)
		if s.pos.distance_to(s.target.pos) < 4.0:
			_damage(s.target, s.dmg)
			s.dmg = 0.0
	shots = shots.filter(func(s: Shot) -> bool: return s.dmg > 0)


func _damage(u: Unit, dmg: float) -> void:
	if u.hp <= 0:
		return
	u.hp -= dmg
	if u.hp <= 0 and u.team == 1:
		gold += UNIT_TYPES[u.kind]["bounty"]


# ---------------------------------------------------------------- render

func _draw() -> void:
	# teren
	draw_rect(Rect2(0, 0, W, H), Color(0.16, 0.22, 0.15))
	draw_rect(Rect2(0, LANE_Y - LANE_HALF, W, LANE_HALF * 2), Color(0.42, 0.36, 0.26))
	if mode != "":
		draw_rect(Rect2(BUILD_MIN_X, 60, BUILD_MAX_X - BUILD_MIN_X + GRID / 2, H - 140), Color(1, 1, 1, 0.05))

	# złoża
	for i in RESOURCE_NODES.size():
		var n := RESOURCE_NODES[i]
		draw_circle(n, 18, Color(0.95, 0.8, 0.2))
		if taken_nodes[i]:
			draw_rect(Rect2(n - Vector2(12, 12), Vector2(24, 24)), Color(0.3, 0.3, 0.35))
			draw_rect(Rect2(n - Vector2(12, 12), Vector2(24, 24)), TEAM_COLORS[0], false, 3)
		else:
			draw_arc(n, 24, 0, TAU, 32, Color(1, 1, 1, 0.4), 2)

	# bazy
	for team in 2:
		var p := P_BASE if team == 0 else E_BASE
		draw_rect(Rect2(p - Vector2(BASE_R, BASE_R), Vector2(BASE_R, BASE_R) * 2), TEAM_COLORS[team].darkened(0.3))
		_hp_bar(p + Vector2(0, -BASE_R - 12), 90, base_hp[team] / BASE_HP)

	# budynki
	for b in buildings:
		if b.hidden:
			continue
		var c := TEAM_COLORS[b.team]
		match b.kind:
			"tower":
				draw_circle(b.pos, 16, c.darkened(0.2))
				draw_circle(b.pos, 7, Color.WHITE)
			"barracks":
				draw_rect(Rect2(b.pos - Vector2(17, 17), Vector2(34, 34)), c.darkened(0.2))
				_progress(b.pos + Vector2(0, 22), b.timer / BUILDINGS[b.kind]["period"])
			"range":
				draw_colored_polygon(PackedVector2Array([b.pos + Vector2(0, -19), b.pos + Vector2(18, 15), b.pos + Vector2(-18, 15)]), c.darkened(0.2))
				_progress(b.pos + Vector2(0, 22), b.timer / BUILDINGS[b.kind]["period"])

	# jednostki
	for u in units:
		var r: float = UNIT_TYPES[u.kind]["r"]
		draw_circle(u.pos, r, TEAM_COLORS[u.team])
		if u.kind == "archer":
			draw_circle(u.pos, 3, Color.WHITE)
		if u.hp < u.max_hp:
			_hp_bar(u.pos + Vector2(0, -r - 6), r * 2.4, u.hp / u.max_hp)

	for s in shots:
		draw_circle(s.pos, 3, s.color)

	# podgląd stawiania
	if mode != "" and not game_over:
		var cell := _snap(get_global_mouse_position())
		var ok := _can_place(cell)
		draw_rect(Rect2(cell - Vector2(GRID, GRID) / 2, Vector2(GRID, GRID)), Color(0, 1, 0, 0.3) if ok else Color(1, 0, 0, 0.3))
		if mode == "tower":
			draw_arc(cell, BUILDINGS["tower"]["range"], 0, TAU, 64, Color(1, 1, 1, 0.35), 2)

	if game_over:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
		var msg := "WYGRANA!" if won else "PRZEGRANA"
		draw_string(font, Vector2(0, H / 2 - 10), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 64, Color.WHITE)
		draw_string(font, Vector2(0, H / 2 + 24), "fala %d · %ds" % [wave, int(elapsed)], HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 1, 0.8))


func _hp_bar(center: Vector2, width: float, frac: float) -> void:
	var tl := center - Vector2(width / 2, 3)
	draw_rect(Rect2(tl, Vector2(width, 6)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(tl, Vector2(width * clampf(frac, 0, 1), 6)), Color(0.3, 0.9, 0.3))


func _progress(center: Vector2, frac: float) -> void:
	var tl := center - Vector2(17, 2)
	draw_rect(Rect2(tl, Vector2(34, 4)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(tl, Vector2(34 * clampf(frac, 0, 1), 4)), Color(1, 1, 1, 0.8))
