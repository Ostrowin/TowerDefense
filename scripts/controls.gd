class_name Controls
extends RefCounted
## Sterowanie: mysz, dotyk i gesty, klawiatura, klik w mapę, dowódca (zaznaczenie, rozkaz marszu),
## celowanie umiejętnościami, budowa i akcje paska. Tryb i zaznaczenie trzyma main (`mode`,
## `selected`, `hero_selected`) — czyta je też render i HUD.
##
## Wskaźnik (mysz albo jeden palec — dotyk jest emulowany jako mysz):
##
##   wciśnij ─┬─ tryb budowy/umiejętności ──▶ podgląd pod palcem ── puść ──▶ buduj / użyj
##            └─ inaczej ──┬─ ruch > TAP_SLOP ──▶ przesuwanie mapy
##                         └─ puść w miejscu ───▶ klik (złoże / zaznaczenie)
##   dwa palce = szczypanie (zoom) + przesuwanie; kółko myszy = zoom; WASD/strzałki = przesuwanie

const TAP_SLOP := 12.0
const KEY_PAN_SPEED := 700.0
## Skróty pól paska umiejętności: Q/E/R — dowódca, T — rasa (kolejność z paska lokalnego gracza).
const ABILITY_KEYS := {KEY_Q: 0, KEY_E: 1, KEY_R: 2, KEY_T: 3}
## Promień trafienia w dowódcę — w pikselach ekranu, niezależnie od przybliżenia (R6).
const HERO_PICK := 28.0

var pointer_screen := Vector2.ZERO
var pointer_active := false
var press_button := -1  ## trzymany przycisk myszy (-1 = żaden)
var press_screen := Vector2.ZERO
var panning := false
var dragging := false  ## stawianie budynku / celowanie umiejętnością: podgląd pod palcem
var touches := {}  ## indeks palca → pozycja ekranowa
var gesture := false  ## dwa palce — emulowana mysz jest wtedy ignorowana

var m: Main


func _init(main: Main) -> void:
	m = main


func key_pan(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		m.pan_screen(-v * KEY_PAN_SPEED * delta)


func on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		touches[e.index] = e.position
	else:
		touches.erase(e.index)
	if touches.size() >= 2 and not gesture:
		gesture = true
		press_button = -1  # drugi palec anuluje rozpoczęty klik/stawianie/przesuwanie
		dragging = false
		panning = false
	elif touches.is_empty():
		gesture = false


## Dwa palce: zmiana odległości = zoom, ruch środka = przesuwanie.
func on_touch_drag(e: InputEventScreenDrag) -> void:
	if not gesture or touches.size() < 2 or not touches.has(e.index):
		touches[e.index] = e.position
		return
	var ids := touches.keys()
	var a0: Vector2 = touches[ids[0]]
	var b0: Vector2 = touches[ids[1]]
	touches[e.index] = e.position
	var a1: Vector2 = touches[ids[0]]
	var b1: Vector2 = touches[ids[1]]
	var d0 := a0.distance_to(b0)
	if d0 > 1.0:
		m.zoom_at((a1 + b1) / 2.0, a1.distance_to(b1) / d0)
	m.pan_screen((a1 + b1) / 2.0 - (a0 + b0) / 2.0)


func on_mouse_button(e: InputEventMouseButton) -> void:
	pointer_screen = e.position
	var p := m.to_world(e.position)
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				m.zoom_at(e.position, 1.12)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				m.zoom_at(e.position, 1.0 / 1.12)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				press_button = e.button_index
				press_screen = e.position
				panning = false
				var left := e.button_index == MOUSE_BUTTON_LEFT
				dragging = left and (ability_mode() != "" or (is_build_mode() and is_free_spot(p)))
			elif e.button_index == press_button:
				press_button = -1
				if dragging:
					dragging = false
					if DisplayServer.is_touchscreen_available():
						pointer_active = false  # na dotyku podgląd znika razem z palcem
					if ability_mode() != "":
						use_targeted(p)
					else:
						place(p)
				elif not panning:
					if e.button_index == MOUSE_BUTTON_LEFT:
						tap(p)
					elif e.button_index == MOUSE_BUTTON_RIGHT:
						cancel()
				panning = false


func on_mouse_motion(e: InputEventMouseMotion) -> void:
	pointer_screen = e.position
	pointer_active = true
	if press_button == -1 or dragging:
		return
	if not panning and e.position.distance_to(press_screen) > TAP_SLOP:
		panning = true
	if panning:
		m.pan_screen(e.relative)


func is_build_mode() -> bool:
	return m.mode != "" and not m.mode.begins_with("ab:")


## Nazwa umiejętności, którą właśnie celujemy ("" = żadna).
func ability_mode() -> String:
	return m.mode.substr(3) if m.mode.begins_with("ab:") else ""


## Czy w tym miejscu wciśnięcie w trybie budowy zaczyna stawianie (a nie klik w coś).
func is_free_spot(p: Vector2) -> bool:
	return m.sim.node_at(p) < 0 and m.sim.building_at(p, 0) == null


func on_key(key: int) -> void:
	match key:
		KEY_ESCAPE:
			m.back()
		KEY_P:
			if m.overlay == "":
				m.set_paused(m.state == Main.State.PLAY)
		KEY_F3:
			m.toggle_perf()
	if m.state != Main.State.PLAY or m.overlay != "":
		return
	if ABILITY_KEYS.has(key):
		var slot: int = ABILITY_KEYS[key]
		var order: Array[String] = m.sim.players[m.me].ability_order
		if slot < order.size():
			select_ability(order[slot])
		return
	match key:
		KEY_H:
			pick_hero(true)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			select_mode(Cfg.BUILD_ORDER[key - KEY_1])
		KEY_SPACE:
			toggle_stance()
		KEY_U:
			upgrade_selected()
		KEY_DELETE, KEY_X:
			sell_selected()
		KEY_TAB:
			if m.selected != null and Cfg.is_production(m.selected.kind):
				set_selected_lane((m.selected.lane + 1) % m.sim.lanes.size())
		KEY_F:
			cycle_speed()
		KEY_M:
			toggle_mute()
		KEY_C, KEY_HOME:
			m.reset_camera()
		KEY_EQUAL, KEY_KP_ADD:
			m.zoom_at(m.view_size / 2.0, 1.2)
		KEY_MINUS, KEY_KP_SUBTRACT:
			m.zoom_at(m.view_size / 2.0, 1.0 / 1.2)


## Klik bez przeciągania: dowódca → zaznacz/odznacz; złoże → wydobywacz / zaznacz;
## budynek → zaznacz; przy zaznaczonym dowódcy pusty teren → rozkaz marszu (D6).
func tap(p: Vector2) -> void:
	if ability_mode() != "":
		use_targeted(p)
		return
	if m.mode == "" and hero_at(p):
		if m.hero_selected:
			m.hero_selected = false
		else:
			pick_hero(false)
		return
	var node := m.sim.node_at(p)
	if node >= 0 or m.sim.building_at(p, 0) != null or m.sim.building_at(p, 1) != null:
		m.hero_selected = false  # budynek, złoże, wieża wroga — normalna akcja i odznaczenie
	elif m.hero_selected:
		order_hero(p)
		return
	if node >= 0:
		var ex := m.sim.extractor_on(node)
		if ex != null:
			m.selected = ex
			m.mode = ""
		elif m.sim.players[m.me].gold < Cfg.BUILDINGS["extractor"]["cost"] or not m.send({"type": "build_extractor", "node": node}):
			deny(p)
		return
	var own := m.sim.building_at(p, 0)
	if own != null:
		m.mode = ""  # klik we własny budynek w trybie budowy = zaznacz go
		m.selected = own
		return
	if m.mode != "":
		return
	m.selected = null
	var enemy := m.sim.building_at(p, 1)
	if enemy != null and Cfg.is_tower(enemy.kind):
		m.selected = enemy


## Czy punkt świata trafia w żywego dowódcę gracza (HERO_PICK px ekranu).
func hero_at(p: Vector2) -> bool:
	return m.sim.hero_alive(m.me) and m.sim.hero(m.me).pos.distance_to(p) <= maxf(HERO_PICK / m.camera.zoom.x, m.sim.hero(m.me).radius + 4.0)


## Zaznacza dowódcę (klik, portret, H); `center` — kamera na niego (portret i H, przy przybliżeniu).
func pick_hero(center: bool) -> void:
	var h := m.sim.hero(m.me)
	if h == null:
		return
	if not m.sim.hero_alive(m.me):
		m.float_text(m.sim.p_base + Vector2(0, -70), "Dowódca wróci za %d s" % ceili(h.respawn), Main.WARN_COLOR)
		m.sfx.play("error", 0.1)
		return
	if m.hero_selected and not center:
		m.hero_selected = false
		return
	m.hero_selected = true
	m.mode = ""
	m.selected = null
	if center and m.is_zoomed_in():
		m.camera.position = h.pos
		m.clamp_camera()


func order_hero(p: Vector2) -> void:
	if m.send({"type": "order_hero", "at": p}):
		m.hero_ordered = true
		m.sfx.play("build", 0.1)
	else:
		m.hero_selected = false


func place(p: Vector2) -> void:
	var cell := Cfg.snap(p)
	if not m.sim.can_place(cell):
		m.sfx.play("error", 0.1)
		return
	if m.sim.players[m.me].gold < m.sim.build_cost(m.mode) or not m.send({"type": "build", "kind": m.mode, "cell": cell}):
		deny(cell)
		return
	if m.sim.players[m.me].gold < m.sim.build_cost(m.mode):
		m.mode = ""


func select_ability(ability: String) -> void:
	if not m.sim.ability_ready(ability, m.me):
		if m.sim.players[m.me].ability_cd.get(ability, 0.0) <= 0.0 and not m.sim.hero_alive(m.me):
			m.float_text(m.sim.p_base + Vector2(0, -70), "Dowódca poległ", Main.WARN_COLOR)
		m.sfx.play("error", 0.1)
		return
	m.hero_selected = false
	if not m.sim.ability_config(ability, m.me)["target"]:
		m.send({"type": "use_ability", "ability": ability})
		m.mode = ""
		return
	m.mode = "" if m.mode == "ab:" + ability else "ab:" + ability
	m.selected = null


func choose_upgrade(i: int) -> void:
	if m.send({"type": "choose_upgrade", "i": i}):
		m.sfx.play("upgrade", 0.0)


func select_ability_slot(i: int) -> void:
	var order: Array[String] = m.sim.players[m.me].ability_order
	if i < order.size():
		select_ability(order[i])


func use_targeted(p: Vector2) -> void:
	var ability := ability_mode()
	if m.sim.ability_target_ok(ability, p, m.me) and m.send({"type": "use_ability", "ability": ability, "at": p}):
		m.mode = ""
	else:
		m.float_text(p, deny_reason(ability, p), Main.WARN_COLOR)
		m.sfx.play("error", 0.1)


## Dlaczego umiejętności nie da się rzucić w `p` (komunikat pod palcem).
func deny_reason(ability: String, p: Vector2) -> String:
	var cfg: Dictionary = m.sim.ability_config(ability, m.me)
	var h := m.sim.hero(m.me)
	if cfg.get("cast_range", 0.0) > 0.0 and h != null and h.pos.distance_to(p) > cfg["cast_range"]:
		return "Poza zasięgiem dowódcy"
	match cfg["kind"]:
		"summon_units":
			if m.sim.team_count[0] >= Cfg.MAX_ARMY:
				return "Limit armii"
			return "Tylko przy ścieżce" if cfg.get("cast_range", 0.0) > 0.0 else "Tylko przy ścieżce, na Twojej połowie"
		"zone":
			return "Nie tutaj"
		"summon_building":
			return "Brak miejsca"
		"demolish":
			return "Wskaż budynek wroga"
		"pull":
			return "Brak celu (Wódz odporny)"
		"leap":
			return "Tylko na ląd"
	return "Jeszcze nie"


func deny(at: Vector2) -> void:
	m.float_text(at, "Brak złota", Main.TEAM_COLORS[1])
	m.sfx.play("error", 0.1)


func cancel() -> void:
	m.mode = ""
	m.selected = null
	m.hero_selected = false
	dragging = false


func select_mode(key: String) -> void:
	m.mode = "" if m.mode == key else key
	m.selected = null
	m.hero_selected = false


func toggle_stance() -> void:
	var me := m.sim.players[m.me]
	m.send({"type": "set_stance", "stance": "defend" if me.stance == "attack" else "attack"})
	m.banner("Atak!" if me.stance == "attack" else "Obrona", "")
	m.banner_life = 1.2


func cycle_speed() -> void:
	if m.net != null:
		return  # R4: w sieci zawsze x1
	m.speed_mult = m.speed_mult % 3 + 1


func toggle_mute() -> void:
	m.sfx.muted = not m.sfx.muted


func upgrade_selected() -> void:
	if m.selected == null or m.selected.team != 0 or m.selected.owner != m.me:
		return  # budynek partnera: tylko podgląd
	var cost := m.sim.upgrade_cost(m.selected)
	if cost > 0 and m.sim.players[m.me].gold < cost:
		deny(m.selected.pos)
		return
	if not m.send({"type": "upgrade", "at": m.selected.pos}) and m.sim.upgrade_cost(m.selected) > 0:
		deny(m.selected.pos)


func sell_selected() -> void:
	if m.selected != null and m.selected.team == 0 and m.selected.owner == m.me and m.send({"type": "sell", "at": m.selected.pos}):
		m.selected = null


func set_selected_lane(lane: int) -> void:
	if m.selected != null and m.selected.owner == m.me and m.send({"type": "set_lane", "at": m.selected.pos, "lane": lane}):
		m.float_text(m.selected.pos + Vector2(0, -26), "→ %s" % m.sim.lanes[lane].name, Main.LANE_COLORS[lane])
