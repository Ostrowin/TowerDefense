class_name WorldView
extends RefCounted
## Render świata: statyczny teren (osobna warstwa `terrain`, przerysowywana przy zmianie mapy),
## podświetlenia ścieżek (Line2D) i wszystko, co się rusza — rysowane co klatkę przez `pen`
## (Painter: cały świat jednym wywołaniem rysowania) na płótnie main (`draw` z `main._draw`).

## Kolor nawierzchni ścieżki. Podświetlenia ścieżek mieszają go z kolorem (bez przezroczystości —
## półprzezroczysta gruba linia nakłada się sama na siebie na ostrych zakrętach i robi kreski).
const PATH_COLOR := Color(0.45, 0.38, 0.27)
const PLANK_COLOR := Color(0.42, 0.32, 0.22)
const RAIL_COLOR := Color(0.22, 0.17, 0.12)
## Duże dekoracje terenu (w miejscach dawnych drzew) — losowane z pozycji, stałe dla mapy.
const BIG_DECO: Array[String] = ["deco_tree", "deco_tree", "deco_tree_dead", "deco_tree", "deco_stump",
	"deco_wreck", "deco_tree", "deco_tree_dead", "deco_tree", "deco_bones", "deco_tree", "deco_rock_big",
	"deco_tree", "deco_crystal", "deco_tree", "deco_stump", "deco_tree"]
## Powyżej tylu jednostek (przy widoku całej mapy) rysujemy je uproszczone.
const LOD_UNITS := 120
## Rodzaj jednostki → [sprite rasy (`<rasa>_<nazwa>` w atlasie), skala]. Fale wroga (Ork, Goblin, Ogr,
## Wódz, tarczownicy, latające) to armia rasy rywala — te same sylwetki co armia gracza tej rasy.
const UNIT_ART := {"soldier": ["soldier", 1.0], "grunt": ["soldier", 1.0], "runner": ["soldier", 0.8],
	"archer": ["archer", 1.0], "catapult": ["siege", 1.0], "shield": ["shield", 1.0], "brute": ["brute", 1.0],
	"warlord": ["brute", 1.45], "bat": ["flyer", 1.0]}
## Kolory pocisków rasy: [poświata, rdzeń].
const SHOT_COLORS := {"hyena": [Color(1.0, 0.35, 0.21), Color(1.0, 0.85, 0.69)],
	"gibbon": [Color(0.37, 0.95, 1.0), Color(0.9, 1.0, 1.0)],
	"mole": [Color(1.0, 0.76, 0.2), Color(1.0, 0.95, 0.75)],
	"boar": [Color(1.0, 0.6, 0.24), Color(1.0, 0.88, 0.63)],
	"hare": [Color(0.55, 0.85, 1.0), Color(0.95, 1.0, 1.0)],
	"otter": [Color(0.25, 0.8, 0.75), Color(0.85, 1.0, 0.97)],
	"bear": [Color(0.72, 0.45, 1.0), Color(0.95, 0.88, 1.0)],
	"wolf": [Color(0.55, 0.75, 1.0), Color(0.92, 0.96, 1.0)],
	"hedgehog": [Color(0.75, 0.95, 0.35), Color(0.97, 1.0, 0.85)]}
## Miejsce osadzenia obrotowej lufy (`b_<rodzaj>_gun`) względem stóp budynku.
const GUN_MOUNT := {"tower": Vector2(0, -26.6), "cannon": Vector2(0, -16.6), "drill_turret": Vector2(0, -18.0),
	"sentry": Vector2(0, -16.0)}
## Stopy budynku względem środka pola budowy (rzut 3/4: podstawa trochę niżej).
const BUILDING_FEET := Vector2(0, 12)
## Kafel terenu: tyle pikseli świata na powtórzenie tekstury.
const TILE := 256.0

## Uproszczone rysowanie jednostek w dużej bitwie (ustawiane co klatkę w _draw).
var low_detail := false
## Wolne pola budowy — liczone tylko, gdy zmieni się układ budynków (`sim.layout_version`).
var _build_cells := PackedVector2Array()
var _build_cells_version := -1
var lane_points: Array[PackedVector2Array] = []
var river_points := PackedVector2Array()
var bridge_planks := PackedVector2Array()  ## pary punktów dla draw_multiline
var bridge_rails := PackedVector2Array()
var grass: Array[Vector3] = []  ## x, y, rodzaj
var trees: Array[Vector3] = []  ## x, y, promień
## Świat rysowany co klatkę (_draw) — patrz Painter: wszystko jednym wywołaniem rysowania.
var pen := Painter.new()
var grass_batch := Painter.new()  ## trawa, kwiatki i kamienie (pod ścieżkami)
var tree_batch := Painter.new()  ## drzewa (nad ścieżkami)
var terrain: Node2D  ## warstwa statycznego terenu, przerysowywana przy zmianie mapy
var lane_strips: Array[Array] = []  ## per ścieżka: [trójkąty, UV] pasa nawierzchni
var river_strip: Array = []
var warn_lines: Array[Node2D] = []  ## podświetlenie ścieżki nadchodzącej fali (per ścieżka)
var pick_lines: Array[Node2D] = []  ## podświetlenie wybranej ścieżki produkcji (per ścieżka)
## Sprite'y jednostek per drużyna: rodzaj → [nazwa, skala, wysokość] (z UNIT_ART i ras drużyn).
var unit_art: Array[Dictionary] = [{}, {}]
var _art_key := -1  ## rasy, dla których policzono unit_art (zmiana = przeliczenie)
var _hero_art := {}  ## id dowódcy → [nazwa, skala, wysokość]
## Budynki od góry do dołu (rzut 3/4: niższy zasłania wyższy) — sortowane po zmianie układu.
var _buildings_sorted: Array[Sim.Building] = []
var _buildings_key := Vector2i(-1, -1)

var m: Main


func _init(main: Main) -> void:
	m = main
	for p in [pen, grass_batch, tree_batch]:
		(p as Painter).use_atlas(Art.atlas, Art.META.WHITE)
	terrain = Node2D.new()
	terrain.z_index = -1  # pod wszystkim, co rysuje main
	terrain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # kafle terenu
	terrain.draw.connect(draw_terrain)
	m.add_child(terrain)


func make_terrain() -> void:
	lane_points.clear()
	river_points = PackedVector2Array()
	bridge_planks = PackedVector2Array()
	bridge_rails = PackedVector2Array()
	grass.clear()
	trees.clear()
	lane_strips.clear()
	for lane in m.sim.lanes:
		lane_points.append(lane.curve.get_baked_points())
		lane_strips.append(make_strip(lane_points[-1], Cfg.PATH_HALF))
	river_strip = []
	if m.sim.river != null:
		river_points = m.sim.river.get_baked_points()
		river_strip = make_strip(river_points, Cfg.RIVER_HALF)

	# mosty (odcinki ścieżek nad rzeką liczy Sim): deski w poprzek, poręcze wzdłuż
	for br in m.sim.bridges:
		var lane := m.sim.lanes[br["lane"]]
		var prev_l := Vector2.ZERO
		var prev_r := Vector2.ZERO
		var s: float = br["s0"]
		while s <= br["s1"] + 0.01:
			var p := lane.point_at(s)
			var n := lane.normal_at(s)
			var l := p + n * (Cfg.PATH_HALF + 5.0)
			var r := p - n * (Cfg.PATH_HALF + 5.0)
			bridge_planks.append(l)
			bridge_planks.append(r)
			if s > br["s0"]:
				for q in [prev_l, l, prev_r, r]:
					bridge_rails.append(q)
			prev_l = l
			prev_r = r
			s += Sim.BRIDGE_STEP

	# trawa i kwiatki tam, gdzie nie ma ścieżek; drzewa poza strefą budowy i ścieżkami
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 7 + m.sim.level_index
	while grass.size() < 260:
		var p := Vector2(rnd.randf_range(10, m.sim.size.x - 10), rnd.randf_range(10, m.sim.size.y - 10))
		if clear_of_paths(p, Cfg.PATH_HALF + 6.0):
			grass.append(Vector3(p.x, p.y, rnd.randi_range(0, 5)))
	var slots: Array[Vector2] = []
	for i in m.sim.enemy_slot_count():
		slots.append(m.sim.enemy_slot_pos(i))
	var zone := m.sim.build_rect.grow(30.0)
	var tries := 0
	while trees.size() < 70 and tries < 5000:
		tries += 1
		var p := Vector2(rnd.randf_range(0, m.sim.size.x), rnd.randf_range(0, m.sim.size.y))
		if zone.has_point(p) or not clear_of_paths(p, Cfg.PATH_HALF + 26.0):
			continue
		if p.distance_to(m.sim.e_base) < 110 or near_any(p, m.sim.nodes, 50.0) or near_any(p, slots, 50.0):
			continue
		trees.append(Vector3(p.x, p.y, rnd.randf_range(12, 22)))

	grass_batch.clear()
	for g in grass:
		var p := Vector2(g.x, g.y)
		var kind := int(g.z)
		var deco: String = ["deco_tuft", "deco_tuft", "deco_tuft2", "deco_flowers", "deco_pebbles", "deco_rock"][kind]
		if Art.has(deco):
			Art.draw(grass_batch, deco, p, 0.8 + fmod(g.x * 0.37, 0.4), fmod(g.y, 2.0) < 1.0)
			continue
		match kind:
			0, 1, 2:
				grass_batch.line(p, p + Vector2(-2, -6), Color(0.22, 0.32, 0.19), 2.0)
				grass_batch.line(p, p + Vector2(2, -7), Color(0.22, 0.32, 0.19), 2.0)
			3:
				grass_batch.circle(p, 2.5, Color(0.9, 0.85, 0.5, 0.6))
			4:
				grass_batch.circle(p, 2.5, Color(0.85, 0.6, 0.8, 0.6))
			5:
				grass_batch.circle(p, 5.0, Color(0.3, 0.33, 0.3))
	tree_batch.clear()
	# drzewa i większe dekoracje od góry do dołu (rzut 3/4: niższe zasłaniają wyższe)
	trees.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	for t in trees:
		var p := Vector2(t.x, t.y)
		var deco: String = BIG_DECO[posmod(int(t.x * 7.3) + int(t.y * 13.7) + int(t.z * 31.0), BIG_DECO.size())]
		if Art.has(deco):
			tree_batch.ellipse(p + Vector2(3, 1), Vector2(t.z * 0.9, t.z * 0.35), Color(0, 0, 0, 0.3))
			Art.draw(tree_batch, deco, p, t.z / 17.0, int(t.x) % 2 == 0)
			continue
		tree_batch.circle(p + Vector2(4, 6), t.z, Color(0, 0, 0, 0.22))
		tree_batch.circle(p, t.z, Color(0.12, 0.26, 0.13))
		tree_batch.circle(p + Vector2(-t.z * 0.3, -t.z * 0.3), t.z * 0.65, Color(0.17, 0.34, 0.17))
	terrain.queue_redraw()

	# podświetlenia ścieżek (ostrzeżenie fali, wybrana ścieżka produkcji) jako Line2D —
	# geometria liczona raz tutaj; co klatkę zmieniamy tylko widoczność i jasność
	for line in warn_lines + pick_lines:
		line.queue_free()
	warn_lines.clear()
	pick_lines.clear()
	for i in lane_points.size():
		warn_lines.append(lane_line(i, Color(1.3, 0.92, 0.8)))
	for i in lane_points.size():
		pick_lines.append(lane_line(i, Color(1, 1, 1).lerp(Main.LANE_COLORS[i], 0.5) * 1.35))


## Podświetlenie ścieżki: ten sam pas nawierzchni co w terenie, zabarwiony (nieprzezroczysty —
## półprzezroczysta nakładka robiła kreski na zakrętach, gdzie pas zachodzi sam na siebie).
func lane_line(i: int, tint: Color) -> Node2D:
	var node := Node2D.new()
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	node.z_index = -1  # nad terenem (dodany później), pod wszystkim z main._draw
	node.visible = false
	var strip: Array = lane_strips[i]
	node.draw.connect(func() -> void: draw_strip(node, strip, Art.dirt, tint))
	m.add_child(node)
	return node


## Pas wzdłuż łamanej (trójkąty + UV w przestrzeni świata, więc kafel płynnie ciągnie się po mapie),
## z okrągłymi końcami. Zwraca [punkty, uv].
func make_strip(pts: PackedVector2Array, half: float) -> Array:
	var tri := PackedVector2Array()
	var n := pts.size()
	if n < 2:
		return [tri, PackedVector2Array()]
	var normals := PackedVector2Array()
	for i in n:
		var d := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		normals.append(d.orthogonal().normalized() * half)
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		tri.append_array([a + normals[i], b + normals[i + 1], b - normals[i + 1],
			a + normals[i], b - normals[i + 1], a - normals[i]])
	for c in [pts[0], pts[n - 1]]:
		for k in 16:
			tri.append_array([c, c + Vector2.from_angle(TAU * k / 16.0) * half, c + Vector2.from_angle(TAU * (k + 1) / 16.0) * half])
	var uv := PackedVector2Array()
	uv.resize(tri.size())
	for i in tri.size():
		uv[i] = tri[i] / TILE
	return [tri, uv]


func draw_strip(item: CanvasItem, strip: Array, tex: Texture2D, tint := Color.WHITE) -> void:
	var pts: PackedVector2Array = strip[0]
	if pts.is_empty():
		return
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(tint)
	RenderingServer.canvas_item_add_triangle_array(item.get_canvas_item(), PackedInt32Array(), pts, cols,
		strip[1], PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


func update_lane_fx() -> void:
	var warn := warn_lanes()
	var pulse := 0.85 + 0.15 * sin(m.time * 6.0)
	var pick := -1
	if m.selected != null and m.selected.team == 0 and Cfg.is_production(m.selected.kind) and m.sim.is_alive(m.selected):
		pick = m.selected.lane
	elif m.controls.is_build_mode() and Cfg.is_production(m.mode) and (m.controls.pointer_active or m.controls.dragging) and m.state == Main.State.PLAY:
		pick = m.sim.nearest_lane(Cfg.snap(m.to_world(m.controls.pointer_screen)))
	for i in warn_lines.size():
		warn_lines[i].visible = warn.has(i)
		warn_lines[i].modulate = Color(pulse, pulse, pulse)
		pick_lines[i].visible = i == pick


func clear_of_paths(p: Vector2, margin: float) -> bool:
	for lane in m.sim.lanes:
		if lane.distance_to(p) < margin:
			return false
	return m.sim.river_distance(p) > Cfg.RIVER_HALF + 6.0


func near_any(p: Vector2, points: Array[Vector2], dist: float) -> bool:
	for q in points:
		if p.distance_to(q) < dist:
			return true
	return false


## Rysowane co klatkę: wszystko, co się rusza. Statyczny teren ma własną warstwę
## (`terrain`, z_index -1), przerysowywaną tylko przy zmianie mapy. Obiekty poza
## kadrem są pomijane.
func draw() -> void:
	pen.clear()
	if _art_key != m.race_index * 100 + m.rival_index:
		refresh_art()
	var view := Rect2(m.to_world(Vector2.ZERO), m.view_size / m.camera.zoom.x).grow(60.0)
	low_detail = m.sim.units.size() > LOD_UNITS and not m.is_zoomed_in()
	draw_overlays()
	draw_zones()
	for n in m.sim.nodes:
		draw_resource_node(n)
	for team in 2:
		draw_base(team)
	for b in sorted_buildings():
		if b.kind != "basegun" and view.has_point(b.pos):
			draw_building(b)
	for u in m.sim.units:
		if not u.flying and view.has_point(u.pos):
			draw_unit(u)
	for s in m.sim.shots:
		if view.has_point(s.pos):
			draw_shot(s)
	for u in m.sim.units:
		if u.flying and view.has_point(u.pos):
			draw_unit(u)  # latające nad resztą
	for st in m.sim.strikes:
		var r: float = st["cfg"]["radius"]
		pen.arc(st["pos"], r, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	for s in m.sparks:
		if not view.has_point(s.pos):
			continue
		var a := s.life / s.max_life
		if s.ring:
			pen.arc(s.pos, s.size * (1.0 - a * 0.6), 0, TAU, 40, Color(s.color, a * 0.8), 3.0)
		elif s.streak:
			pen.line(s.pos, s.pos - s.vel.normalized() * 14.0, Color(s.color, a), 2.0)
		else:
			pen.circle(s.pos, s.size * (0.4 + 0.6 * a), Color(s.color, a))
	for f in m.texts:
		var alpha := clampf(f.life * 2.0, 0.0, 1.0)
		pen.text_outline(m.font, f.pos - Vector2(100, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, 4, Color(0, 0, 0, alpha * 0.8))
		pen.text(m.font, f.pos - Vector2(100, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color(f.color, alpha))
	draw_selection()
	draw_ghost()
	pen.draw_on(m)  # cały świat jednym wywołaniem rysowania + napisy na wierzchu


## Statyczny teren bieżącej mapy — rysowany na warstwie `terrain` tylko przy zmianie mapy.
func draw_terrain() -> void:
	var c := terrain
	var size := m.sim.size
	var outer := Rect2(-400, -400, size.x + 800, size.y + 800)
	c.draw_texture_rect_region(Art.ground, outer, Rect2(outer.position, outer.size))
	# poza mapą przyciemnienie
	var dim := Color(0, 0, 0, 0.45)
	c.draw_rect(Rect2(-400, -400, size.x + 800, 400), dim)
	c.draw_rect(Rect2(-400, size.y, size.x + 800, 400), dim)
	c.draw_rect(Rect2(-400, 0, 400, size.y), dim)
	c.draw_rect(Rect2(size.x, 0, 400, size.y), dim)
	grass_batch.draw_on(c)

	# rzeka: błotnisty brzeg, woda, jaśniejszy nurt
	if not river_points.is_empty():
		c.draw_polyline(river_points, Color(0.2, 0.17, 0.12, 0.8), Cfg.RIVER_HALF * 2 + 12, true)
		draw_strip(c, river_strip, Art.water)
		c.draw_polyline(river_points, Color(0.5, 0.65, 0.65, 0.12), Cfg.RIVER_HALF * 0.7, true)

	# ścieżki: najpierw wszystkie obrzeża, potem nawierzchnie — przy bazach się zlewają
	for pts in lane_points:
		c.draw_polyline(pts, Color(0.16, 0.13, 0.09, 0.55), Cfg.PATH_HALF * 2 + 8, true)
	for strip in lane_strips:
		draw_strip(c, strip, Art.dirt)
	if not bridge_planks.is_empty():  # mapa bez rzeki nie ma mostów (pusta tablica = błąd silnika)
		c.draw_multiline(bridge_planks, PLANK_COLOR, 5.0)
	if not bridge_rails.is_empty():
		c.draw_multiline(bridge_rails, RAIL_COLOR, 3.0)

	# nazwy ścieżek przy bazie gracza
	for i in m.sim.lanes.size():
		var lane := m.sim.lanes[i]
		var at := lane.slot_at(180.0, -(Cfg.PATH_HALF + 16.0))
		c.draw_string_outline(m.font, at - Vector2(50, -5), lane.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, 4, Color(0, 0, 0, 0.6))
		c.draw_string(m.font, at - Vector2(50, -5), lane.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Main.LANE_COLORS[i])

	tree_batch.draw_on(c)


## Zmienne nakładki na terenie: ostrzeżenia fal, wybrana ścieżka, strefa budowy, zbiórka.
func draw_overlays() -> void:
	# ostrzeżenie: ścieżka nadchodzącej fali — samo podświetlenie to Line2D (_update_lane_fx)
	var pulse := 0.5 + 0.5 * sin(m.time * 6.0)
	for i in warn_lanes():
		var lane := m.sim.lanes[i]
		var mark := lane.point_at(lane.length - 150.0)
		pen.circle(mark, 16 + 3 * pulse, Color(Main.WARN_COLOR, 0.9))
		pen.text(m.font, mark + Vector2(-20, 9), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 26, Color.WHITE)

	# linia od zaznaczonego budynku produkcyjnego do jego ścieżki
	if m.selected != null and m.selected.team == 0 and Cfg.is_production(m.selected.kind) and m.sim.is_alive(m.selected):
		var lane := m.sim.lanes[m.selected.lane]
		var entry := lane.point_at(lane.offset_of(m.selected.pos))
		pen.dashed_line(m.selected.pos, entry, Color(Main.LANE_COLORS[m.selected.lane], 0.9), 3.0, 8.0)

	# podświetlenia ścieżek są nieprzezroczyste — mosty dorysowane jeszcze raz na wierzch
	if not bridge_planks.is_empty():
		pen.multiline(bridge_planks, PLANK_COLOR, 5.0)
	if not bridge_rails.is_empty():
		pen.multiline(bridge_rails, RAIL_COLOR, 3.0)

	# strefa budowy: w trybie budowy podświetlone wolne pola (liczone tylko po zmianie budynków)
	if m.controls.is_build_mode():
		if _build_cells_version != m.sim.layout_version:
			_build_cells_version = m.sim.layout_version
			_build_cells.clear()
			var y := Cfg.GRID / 2
			while y <= m.sim.build_rect.end.y:
				var x := Cfg.GRID / 2
				while x <= m.sim.build_rect.end.x:
					if m.sim.can_place(Vector2(x, y)):
						_build_cells.append(Vector2(x, y))
					x += Cfg.GRID
				y += Cfg.GRID
		for c in _build_cells:
			pen.rect(Rect2(c - Vector2(18, 18), Vector2(36, 36)), Color(1, 1, 1, 0.07))

	# linie zbiórki — po jednej na każdej ścieżce
	if m.sim.players[m.me].stance == "defend" and m.state != Main.State.MENU:
		for lane in m.sim.lanes:
			var s := m.sim.rally_s + 14.0
			var n := lane.normal_at(s)
			var p := lane.point_at(s)
			pen.dashed_line(p - n * Cfg.PATH_HALF, p + n * Cfg.PATH_HALF, Color(0.7, 0.85, 1, 0.8), 2.0, 5.0)
			var pole := p + n * Cfg.PATH_HALF
			pen.line(pole, pole + Vector2(0, -24), Color(0.85, 0.85, 0.85), 2.0)
			pen.polygon(PackedVector2Array([pole + Vector2(0, -24), pole + Vector2(15, -19), pole + Vector2(0, -14)]), Main.TEAM_COLORS[0])


## Ścieżki, którymi właśnie idzie fala albo przyjdzie następna (w ciągu WAVE_WARNING s).
func warn_lanes() -> Array[int]:
	var out: Array[int] = []
	if m.state == Main.State.MENU:
		return out
	if not m.sim.spawn_queue.is_empty():
		for e in m.sim.spawn_queue:
			if not out.has(e["lane"]):
				out.append(e["lane"])
	elif m.sim.wave_timer <= Cfg.WAVE_WARNING:
		out = m.sim.next_wave_lanes.duplicate()
	return out


func draw_resource_node(n: Vector2) -> void:
	var idx := m.sim.nodes.find(n)
	var rich := m.sim.richness[idx] > 1.0
	if Art.has("deposit"):
		pen.ellipse(n + Vector2(0, 8), Vector2(24, 9), Color(0, 0, 0, 0.3))
		var glow := 0.08 + 0.05 * sin(m.time * 2.0 + idx)
		pen.circle(n + Vector2(0, -2), 22.0 if rich else 18.0, Color(1.0, 0.85, 0.3, glow * (1.6 if rich else 1.0)))
		Art.draw(pen, "deposit", n + Vector2(0, 9), 1.15 if rich else 1.0)
	else:
		draw_deposit_shape(n, rich)
	if rich:
		for i in 3:
			var a := m.time * 1.5 + TAU * i / 3.0
			pen.circle(n + Vector2.from_angle(a) * 22.0, 2.0, Color(1, 1, 0.8, 0.8))
	if m.sim.extractor_on(idx) == null and m.state == Main.State.PLAY:
		var pulse := 0.3 + 0.2 * sin(m.time * 3.0)
		pen.arc(n, 26, 0, TAU, 32, Color(1, 1, 1, pulse), 2.0)
		if m.sim.players[m.me].gold >= Cfg.BUILDINGS["extractor"]["cost"]:
			pen.text(m.font, n + Vector2(-40, 44), "%d zł" % Cfg.BUILDINGS["extractor"]["cost"],
				HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(1, 1, 1, 0.6))


func draw_deposit_shape(n: Vector2, rich: bool) -> void:
	pen.circle(n + Vector2(0, 4), 20, Color(0, 0, 0, 0.2))
	pen.circle(n + Vector2(-7, 3), 10, Color(0.75, 0.6, 0.15))
	pen.circle(n + Vector2(7, 4), 9, Color(0.85, 0.68, 0.18))
	pen.circle(n + Vector2(0, -5), 11, Color(0.98, 0.83, 0.25) if not rich else Color(1.0, 0.92, 0.45))
	pen.circle(n + Vector2(-3, -8), 3, Color(1, 1, 0.8, 0.8))


func draw_base(team: int) -> void:
	var p := m.sim.base_pos(team)
	var c := Main.TEAM_COLORS[team]
	var r := Cfg.BASE_R
	var body := Rect2(p - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.8))
	if Art.has("b_base"):
		var feet := p + Vector2(0, r * 1.05)
		pen.ellipse(feet + Vector2(4, 0), Vector2(r * 1.4, r * 0.4), Color(0, 0, 0, 0.35))
		var f := 1.0 + m.base_flash[team] * 12.0
		Art.draw(pen, "b_base", feet, 1.0, team == 1, Color(f, f, f), c)
		draw_base_labels(team, feet + Vector2(0, -Art.height("b_base") - 6))
		return
	pen.rect(Rect2(body.position + Vector2(4, 6), body.size), Color(0, 0, 0, 0.25))
	pen.rect(body, c.darkened(0.45))
	for i in 4:
		pen.rect(Rect2(body.position + Vector2(i * r * 0.62, -10), Vector2(r * 0.4, 12)), c.darkened(0.45))
	pen.rect(body, c.darkened(0.1), false, 3.0)
	pen.rect(Rect2(p + Vector2(-10, r * 0.2), Vector2(20, r * 0.8)), Color(0.12, 0.08, 0.05))
	var pole := p + Vector2(0, -r * 0.8 - 10)
	pen.line(pole, pole + Vector2(0, -30), Color(0.85, 0.85, 0.85), 2.0)
	var flutter := sin(m.time * 4.0 + team) * 3.0
	pen.polygon(PackedVector2Array([pole + Vector2(0, -30), pole + Vector2(22 * (1 - 2 * team), -24 + flutter), pole + Vector2(0, -18)]), c)
	if m.base_flash[team] > 0:
		pen.rect(body, Color(1, 1, 1, m.base_flash[team] * 4.0))
	draw_base_labels(team, pole + Vector2(0, -30))


## Nazwa rasy nad fortecą (`top` = wierzch budowli), pasek HP i liczba pod nią.
func draw_base_labels(team: int, top: Vector2) -> void:
	var p := m.sim.base_pos(team)
	var c := Main.TEAM_COLORS[team]
	var r := Cfg.BASE_R
	var race_i := m.race_index if team == 0 else m.rival_index
	if race_i >= 0:  # przeciwnik nieznany w menu — losujemy go przy starcie
		var race: String = Races.ALL[race_i]["name"]
		pen.text_outline(m.font, top + Vector2(-70, -4), race, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, 5, Color(0, 0, 0, 0.7))
		pen.text(m.font, top + Vector2(-70, -4), race, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, c.lightened(0.35))
	var frac := m.sim.base_hp[team] / Cfg.BASE_HP[team]
	hp_bar(p + Vector2(0, r + 18), 100, frac, 8)
	var hp_text := "nie do zburzenia" if team == 1 and m.sim.mode == "survival" else "%d" % int(m.sim.base_hp[team])
	pen.text(m.font, p + Vector2(-80, r + 42), hp_text, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(1, 1, 1, 0.8))


func draw_building(b: Sim.Building) -> void:
	var c := Main.TEAM_COLORS[b.team]
	var sprite := draw_building_shape(b.kind, b.pos, c, b.aim, 1.0, b.flash)
	if b.flash > 0 and not sprite:
		pen.circle(b.pos, 18, Color(1, 1, 1, b.flash * 4.0))
	if Cfg.is_production(b.kind):
		progress(b.pos + Vector2(0, 24), b.timer / m.sim.production_period(b.kind, b.level))
		# plakietka ścieżki, którą idą jednostki
		pen.circle(b.pos + Vector2(16, -16), 6.0, Color(0, 0, 0, 0.6))
		pen.circle(b.pos + Vector2(16, -16), 4.5, Main.LANE_COLORS[b.lane])
	if b.hp < b.max_hp:
		var name := "b_" + b.kind
		var top := BUILDING_FEET.y - Art.height(name) - 4.0 if Art.has(name) else -26.0
		hp_bar(b.pos + Vector2(0, top), 36, b.hp / b.max_hp, 5)
	if b.temporary:
		progress(b.pos + Vector2(0, 24), b.life / b.life_max)
		return
	for i in b.level - 1:
		pen.circle(b.pos + Vector2(-5 + i * 10, 32 if Cfg.is_production(b.kind) else 24), 3.0, Main.GOLD_COLOR)


## Budynek ze sprite'a `b_<rodzaj>` (+ obrotowa lufa `b_<rodzaj>_gun`), inaczej prosty kształt.
## Zwraca true, gdy narysował sprite.
func draw_building_shape(kind: String, p: Vector2, c: Color, aim: float, alpha: float, flash := 0.0) -> bool:
	var name := "b_" + kind
	if Art.has(name):
		var feet := p + BUILDING_FEET
		var f := 1.0 + flash * 6.0
		var tint := Color(f, f, f, alpha)
		if alpha >= 1.0:
			pen.ellipse(feet + Vector2(2, 1), Vector2(22, 8), Color(0, 0, 0, 0.3))
		Art.draw(pen, name, feet, 1.0, false, tint, Color(c, alpha))
		if Art.has(name + "_gun"):
			var d := Vector2.from_angle(aim)
			var flip := d.x < 0.0
			var ang := clampf(atan2(d.y * 0.7, absf(d.x)), -0.6, 0.6)
			Art.draw(pen, name + "_gun", feet + GUN_MOUNT.get(kind, Vector2(0, -26)), 1.0, flip, tint,
				Color(c, alpha), -ang if flip else ang)
		return true
	var dark := Color(c.darkened(0.35), alpha)
	var light := Color(c.lightened(0.2), alpha)
	var shadow := Color(0, 0, 0, 0.25 * alpha)
	match kind:
		"tower":
			pen.circle(p + Vector2(3, 4), 17, shadow)
			pen.circle(p, 17, dark)
			pen.arc(p, 17, 0, TAU, 24, light, 2.0)
			pen.circle(p, 8, light)
			pen.line(p, p + Vector2.from_angle(aim) * 14, Color(1, 1, 1, alpha), 3.0)
		"cannon":
			pen.rect(Rect2(p - Vector2(15, 15) + Vector2(3, 4), Vector2(30, 30)), shadow)
			pen.rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), Color(0.25, 0.25, 0.28, alpha))
			pen.rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), light, false, 2.0)
			pen.line(p, p + Vector2.from_angle(aim) * 22, Color(0.1, 0.1, 0.1, alpha), 8.0)
			pen.circle(p, 8, Color(0.4, 0.4, 0.45, alpha))
		"frost":
			var diamond := PackedVector2Array([p + Vector2(0, -19), p + Vector2(16, 0), p + Vector2(0, 19), p + Vector2(-16, 0)])
			pen.polygon(PackedVector2Array([p + Vector2(3, -15), p + Vector2(19, 4), p + Vector2(3, 23), p + Vector2(-13, 4)]), shadow)
			pen.polygon(diamond, Color(0.2, 0.35, 0.5, alpha))
			diamond.append(diamond[0])
			pen.polyline(diamond, light, 2.0)
			var glow := 0.6 + 0.4 * sin(m.time * 3.0)
			pen.circle(p, 7, Color(Main.FROST_COLOR, alpha * glow))
		"barracks":
			pen.rect(Rect2(p - Vector2(17, 10) + Vector2(3, 4), Vector2(34, 27)), shadow)
			pen.rect(Rect2(p - Vector2(17, 10), Vector2(34, 27)), dark)
			pen.polygon(PackedVector2Array([p + Vector2(-20, -10), p + Vector2(0, -24), p + Vector2(20, -10)]), light)
			pen.rect(Rect2(p + Vector2(-5, 4), Vector2(10, 13)), Color(0.1, 0.07, 0.05, alpha))
		"range":
			pen.polygon(PackedVector2Array([p + Vector2(3, -15), p + Vector2(21, 19), p + Vector2(-15, 19)]), shadow)
			pen.polygon(PackedVector2Array([p + Vector2(0, -19), p + Vector2(18, 15), p + Vector2(-18, 15)]), dark)
			pen.circle(p + Vector2(0, 3), 7, Color(1, 1, 1, alpha))
			pen.circle(p + Vector2(0, 3), 4, Color(0.9, 0.2, 0.2, alpha))
		"workshop":
			var pts := PackedVector2Array()
			for i in 6:
				pts.append(p + Vector2.from_angle(TAU * i / 6.0) * 18)
			pen.polygon(pts, Color(0.45, 0.32, 0.2, alpha))
			pts.append(pts[0])
			pen.polyline(pts, light, 2.0)
			for i in 4:
				var a := m.time * 1.5 + TAU * i / 4.0
				pen.line(p, p + Vector2.from_angle(a) * 10, Color(0.8, 0.8, 0.8, alpha), 3.0)
			pen.circle(p, 4, Color(0.3, 0.3, 0.3, alpha))
		"extractor":
			pen.rect(Rect2(p - Vector2(14, 14), Vector2(28, 28)), Color(0.3, 0.3, 0.34, alpha))
			pen.rect(Rect2(p - Vector2(14, 14), Vector2(28, 28)), light, false, 3.0)
			for i in 4:
				var a := m.time * 3.0 + TAU * i / 4.0
				pen.line(p, p + Vector2.from_angle(a) * 11, Color(0.95, 0.8, 0.3, alpha), 3.0)
			pen.circle(p, 4, Color(0.2, 0.2, 0.2, alpha))
		_:  # budowle tymczasowe (umiejętności) — totem z wierzchołkiem w kolorze drużyny
			pen.polygon(PackedVector2Array([p + Vector2(3, -14), p + Vector2(17, 18), p + Vector2(-11, 18)]), shadow)
			pen.polygon(PackedVector2Array([p + Vector2(0, -18), p + Vector2(14, 14), p + Vector2(-14, 14)]), Color(0.4, 0.33, 0.25, alpha))
			pen.circle(p + Vector2(0, -4), 6, light)
			pen.line(p + Vector2(0, -4), p + Vector2(0, -4) + Vector2.from_angle(aim) * 12, Color(1, 1, 1, alpha), 2.0)
	return false


## `low_detail`: w dużej bitwie (widok całej mapy) bez cienia, obrysu, podskoku
## i pasków HP zdrowych jednostek — to połowa wywołań rysowania na jednostkę.
func draw_unit(u: Sim.Unit) -> void:
	if u.is_hero:
		draw_hero(u as Sim.Hero)
		return
	if u.burrow > 0.0:  # Podkop: kopczyk ziemi w kolorze drużyny zamiast jednostki
		var m := u.prev_pos.lerp(u.pos, m.render_alpha)
		pen.circle(m + Vector2(0, 2), u.radius, Color(0.3, 0.22, 0.14))
		pen.circle(m, u.radius * 0.7, Color(0.45, 0.34, 0.22))
		pen.circle(m + Vector2(0, -u.radius * 0.3), 2.5, Main.TEAM_COLORS[u.team])
		return
	var r := u.radius
	var dir := 1.0 if u.team == 0 else -1.0
	var at := u.prev_pos.lerp(u.pos, m.render_alpha)  # interpolacja między krokami sima
	var art: Array = unit_art[u.team].get(u.kind, [])
	if not art.is_empty():
		var top := draw_unit_sprite(u, at, art)
		draw_unit_status(u, at, top)
		return
	var p := at if low_detail else at + Vector2(0, sin(m.time * 12.0 + u.id) * 1.2)
	var c := Main.TEAM_COLORS[u.team]
	if u.flying:
		pen.circle(at + Vector2(8, 18), r * 0.7, Color(0, 0, 0, 0.18))  # cień daleko = wysoko
	elif not low_detail:
		pen.circle(at + Vector2(2, r * 0.7), r * 0.9, Color(0, 0, 0, 0.2))
		pen.circle(p, r + 1.5, Color(0, 0, 0, 0.35))  # obrys (koło jest tańsze niż łuk)
	match u.kind:
		"soldier":
			pen.circle(p, r, c)
			pen.line(p + Vector2(dir * r * 0.4, 0), p + Vector2(dir * r * 1.5, -r * 0.6), Color(0.9, 0.9, 0.95), 2.0)
		"archer":
			pen.circle(p, r, c.lightened(0.15))
			pen.arc(p + Vector2(dir * r * 0.5, 0), r * 0.9, -PI / 2 if dir > 0 else PI / 2, PI / 2 if dir > 0 else 3 * PI / 2, 8, Color(0.6, 0.4, 0.2), 2.0)
		"catapult":
			pen.rect(Rect2(p - Vector2(r, r * 0.5), Vector2(r * 2, r)), Color(0.5, 0.35, 0.2))
			pen.circle(p + Vector2(-r * 0.6, r * 0.5), 4, Color(0.2, 0.15, 0.1))
			pen.circle(p + Vector2(r * 0.6, r * 0.5), 4, Color(0.2, 0.15, 0.1))
			var swing := clampf(u.cd_left / u.cooldown, 0.0, 1.0)
			pen.line(p, p + Vector2.from_angle(-PI / 2 - dir * (0.3 + swing)) * r * 1.4, Color(0.65, 0.5, 0.3), 3.0)
			pen.rect(Rect2(p - Vector2(r, r * 0.5), Vector2(r * 2, r)), c, false, 2.0)
		"grunt":
			pen.circle(p, r, c)
			pen.line(p + Vector2(-4, -r + 2), p + Vector2(-6, -r - 4), Color(0.9, 0.85, 0.7), 2.0)
			pen.line(p + Vector2(4, -r + 2), p + Vector2(6, -r - 4), Color(0.9, 0.85, 0.7), 2.0)
		"runner":
			pen.line(p + Vector2(r, -3), p + Vector2(r + 8, -3), Color(1, 0.7, 0.3, 0.5), 2.0)
			pen.line(p + Vector2(r, 3), p + Vector2(r + 10, 3), Color(1, 0.7, 0.3, 0.5), 2.0)
			pen.circle(p, r, Color(1.0, 0.6, 0.25))
		"shield":
			pen.circle(p, r, c.darkened(0.15))
			pen.rect(Rect2(p + Vector2(dir * r * 0.5 - 3, -r * 0.9), Vector2(6, r * 1.8)), Color(0.72, 0.72, 0.78))
			pen.rect(Rect2(p + Vector2(dir * r * 0.5 - 3, -r * 0.9), Vector2(6, r * 1.8)), Color(0.3, 0.3, 0.35), false, 1.5)
		"bat":
			var flap := sin(m.time * 22.0 + u.id) * 5.0
			var wing := Color(0.35, 0.15, 0.4)
			pen.polygon(PackedVector2Array([p, p + Vector2(-r * 1.9, -4 + flap), p + Vector2(-r * 0.8, 4)]), wing)
			pen.polygon(PackedVector2Array([p, p + Vector2(r * 1.9, -4 + flap), p + Vector2(r * 0.8, 4)]), wing)
			pen.circle(p, r * 0.7, Color(0.5, 0.2, 0.55))
			pen.circle(p + Vector2(-2, -1), 1.3, Main.WARN_COLOR)
			pen.circle(p + Vector2(2, -1), 1.3, Main.WARN_COLOR)
		"brute":
			pen.circle(p, r, c.darkened(0.3))
			pen.arc(p, r, 0, TAU, 24, c.lightened(0.2), 3.0)
		"warlord":
			pen.circle(p, r, Color(0.55, 0.2, 0.6))
			pen.arc(p, r, 0, TAU, 32, Main.GOLD_COLOR, 3.0)
			for i in 3:
				var cx := p + Vector2(-8 + i * 8, -r - 2)
				pen.polygon(PackedVector2Array([cx + Vector2(-4, 0), cx + Vector2(0, -8), cx + Vector2(4, 0)]), Main.GOLD_COLOR)
	if u.flash > 0:
		pen.circle(p, r, Color(1, 1, 1, u.flash * 5.0))
	draw_unit_status(u, p, -r)


## Stany nad jednostką: mróz, osłabienie, ogłuszenie, poziom, pasek HP. `top` = wierzch postaci
## względem `p` (ujemny = wyżej).
func draw_unit_status(u: Sim.Unit, p: Vector2, top: float) -> void:
	var r := u.radius
	if u.slow_timer > 0:
		pen.ellipse(p + Vector2(0, r * 0.9), Vector2(r * 1.3, r * 0.5), Color(Main.FROST_COLOR, 0.45))
		pen.arc(p, r + 3, 0, TAU, 12 if low_detail else 20, Color(Main.FROST_COLOR, 0.9), 2.0)
	if u.vuln > 1.0:
		pen.arc(p, r + 2, 0, TAU, 12 if low_detail else 16, Color(Main.CURSE_COLOR, 0.85), 2.0)
	if u.buffs.has("thorns"):  # kolce (jeże): jasny pierścień
		pen.arc(p, r + 4, 0, TAU, 12, Color(0.9, 0.85, 0.55, 0.8), 2.5)
	if u.stun > 0:  # ogłuszenie: krążące gwiazdki nad głową
		for i in 2:
			pen.circle(p + Vector2.from_angle(m.time * 6.0 + PI * i) * Vector2(r, r * 0.4) + Vector2(0, top - 3), 2.0, Main.GOLD_COLOR)
	if low_detail:
		if u.hp < u.max_hp * 0.6:
			hp_bar(p + Vector2(0, top - 4), maxf(r * 2.4, 18.0), u.hp / u.max_hp, 4)
		return
	for i in u.level - 1:
		pen.circle(p + Vector2(-3 + i * 6, top - 9), 2.0, Main.GOLD_COLOR)
	if u.hp < u.max_hp:
		hp_bar(p + Vector2(0, top - 4), maxf(r * 2.4, 18.0), u.hp / u.max_hp, 4)


## Postać ze sprite'a + ruch z kodu: chód (podskok, kołysanie, sprężystość), wypad przy ciosie wręcz,
## odrzut przy strzale, unoszenie latających, błysk trafienia. Zwraca wierzch postaci względem `at`.
func draw_unit_sprite(u: Sim.Unit, at: Vector2, art: Array) -> float:
	var r := u.radius
	var dx := u.pos.x - u.prev_pos.x
	if absf(dx) > 0.05:
		u.face = signf(dx)
	var moving := u.pos.distance_squared_to(u.prev_pos) > 0.0004 and u.stun <= 0.0
	var feet := at + Vector2(0, r * 0.9)
	var lift := 0.0
	var rot := 0.0
	var squash := Vector2.ONE
	var ph := m.time * 11.0 + u.id * 1.7
	if u.flying:
		lift = r * 2.2 + sin(m.time * 5.0 + u.id) * 2.0
		rot = sin(m.time * 3.0 + u.id) * 0.06
		pen.ellipse(feet + Vector2(5, 2), Vector2(r * 0.9, r * 0.35), Color(0, 0, 0, 0.2))
	else:
		if not low_detail:
			pen.ellipse(feet, Vector2(r * 1.15, r * 0.42), Color(0, 0, 0, 0.32))
		if moving:
			var st := absf(sin(ph))
			lift = st * r * 0.22
			rot = sin(ph) * 0.07
			squash = Vector2(1.0 - st * 0.04, 1.0 + st * 0.05)
		else:  # oddech w miejscu
			squash = Vector2(1.0, 1.0 + sin(m.time * 3.0 + u.id) * 0.015)
	# cios / strzał: świeżo po ataku cd_left jest bliski pełnego czasu odnowienia
	var full := u.cooldown / maxf(u.attack_speed, 0.01)
	if full > 0.0 and u.cd_left > full * 0.7:
		var k := (u.cd_left / full - 0.7) / 0.3
		if u.melee:
			rot += u.face * 0.28 * k
			feet.x += u.face * r * 0.35 * k
		else:
			feet.x -= u.face * r * 0.15 * k
	var tint := Color.WHITE
	if u.flash > 0.0:
		var f := 1.0 + u.flash * 8.0
		tint = Color(f, f, f)
	Art.draw(pen, art[0], feet - Vector2(0, lift), art[1], u.face < 0.0, tint, Main.TEAM_COLORS[u.team], rot, squash)
	return r * 0.9 - lift - float(art[2]) * squash.y


func sorted_buildings() -> Array[Sim.Building]:
	var key := Vector2i(m.sim.layout_version, m.sim.buildings.size())
	if key != _buildings_key or (not _buildings_sorted.is_empty() and not m.sim.buildings.has(_buildings_sorted[0])):
		_buildings_key = key
		_buildings_sorted = m.sim.buildings.duplicate()
		_buildings_sorted.sort_custom(func(a: Sim.Building, b: Sim.Building) -> bool: return a.pos.y < b.pos.y)
	return _buildings_sorted


## Rasa drużyny (id z Races). W menu rywal nie jest jeszcze wylosowany — pierwsza inna grywalna.
func team_race(team: int) -> String:
	var i := m.race_index if team == 0 else m.rival_index
	if i < 0:
		for j in Races.ALL.size():
			if j != m.race_index and Races.ALL[j]["playable"]:
				i = j
				break
	return Races.ALL[maxi(i, 0)]["id"]


func refresh_art() -> void:
	_art_key = m.race_index * 100 + m.rival_index
	_hero_art.clear()
	for team in 2:
		var race := team_race(team)
		var m := {}
		for kind in UNIT_ART:
			var a: Array = UNIT_ART[kind]
			var name := "%s_%s" % [race, a[0]]
			if Art.has(name):
				m[kind] = [name, a[1], Art.height(name, a[1])]
		unit_art[team] = m


## Sprite dowódcy: `cmd_<id>`, a bez niego piechur jego rasy w powiększeniu. Pusty = stary rysunek.
func hero_sprite(h: Sim.Hero) -> Array:
	if _hero_art.has(h.commander):
		return _hero_art[h.commander]
	var out := []
	var name := "cmd_" + h.commander
	if Art.has(name):
		out = [name, 1.0, Art.height(name)]
	else:
		var soldier: Array = unit_art[h.team].get("soldier", [])
		if not soldier.is_empty():
			out = [soldier[0], 1.35, Art.height(soldier[0], 1.35)]
	_hero_art[h.commander] = out
	return out


## Dowódca: większy, ze złotą obwódką i inicjałem — zawsze w pełnej szczegółowości (jest jeden).
func draw_hero(h: Sim.Hero) -> void:
	var r := h.radius
	var at := h.prev_pos.lerp(h.pos, m.render_alpha)
	var art := hero_sprite(h)
	if not art.is_empty():
		var ring := Main.HERO_COLOR if h.team == 0 else Main.TEAM_COLORS[1].lightened(0.4)
		pen.ellipse(at + Vector2(0, r * 0.9), Vector2(r * 1.5, r * 0.6), Color(ring, 0.35))
		pen.ellipse(at + Vector2(0, r * 0.9), Vector2(r * 1.2, r * 0.45), Color(0, 0, 0, 0.3))
		if h.invulnerable > 0.0:
			pen.circle(at, r + 7, Color(1, 1, 1, 0.15 + 0.15 * sin(m.time * 20.0)))
		var top := draw_unit_sprite(h, at, art)
		if h.slow_timer > 0:
			pen.arc(at, r + 4, 0, TAU, 20, Color(Main.FROST_COLOR, 0.9), 2.0)
		hp_bar(at + Vector2(0, top - 5), 34, h.hp / h.max_hp, 5)
		return
	var bob := 0.0 if h.state == "idle" else sin(m.time * 14.0) * 1.5
	var p := at + Vector2(0, bob)
	var c := Main.TEAM_COLORS[h.team]
	pen.circle(at + Vector2(2, r * 0.7), r, Color(0, 0, 0, 0.25))
	if h.invulnerable > 0.0:
		pen.circle(p, r + 7, Color(1, 1, 1, 0.25 + 0.2 * sin(m.time * 20.0)))
	pen.circle(p, r + 2.5, Main.HERO_COLOR if h.team == 0 else Main.TEAM_COLORS[1].lightened(0.4))
	pen.circle(p, r, c.darkened(0.2))
	var initial: String = Cfg.COMMANDERS[h.commander]["name"].left(1)
	pen.text(m.font, p + Vector2(-r, r * 0.45), initial, HORIZONTAL_ALIGNMENT_CENTER, r * 2, int(r * 1.3), Color.WHITE)
	if h.slow_timer > 0:
		pen.arc(p, r + 4, 0, TAU, 20, Color(Main.FROST_COLOR, 0.9), 2.0)
	if h.flash > 0:
		pen.circle(p, r, Color(1, 1, 1, h.flash * 5.0))
	hp_bar(p + Vector2(0, -r - 8), 34, h.hp / h.max_hp, 5)


## Strefy (`zone`): mina — mały znacznik, strefa obrażeń — pulsujący krąg.
func draw_zones() -> void:
	for r in m.sim.raises:
		var a := 0.12 + 0.05 * sin(m.time * 4.0)
		pen.circle(r["pos"], r["radius"], Color(Main.CURSE_COLOR, a))
		pen.arc(r["pos"], r["radius"], 0, TAU, 40, Color(Main.CURSE_COLOR, 0.6), 2.0)
	for z in m.sim.zones:
		var cfg: Dictionary = z["cfg"]
		var pos: Vector2 = z["pos"]
		var r: float = cfg["radius"]
		var tc := Main.TEAM_COLORS[z["team"]]
		if cfg["trigger"] == "enter":
			pen.arc(pos, r, 0, TAU, 32, Color(tc, 0.25), 1.5)
			pen.circle(pos, 6, Color(0.25, 0.25, 0.25))
			pen.circle(pos, 2.5, Color(Main.WARN_COLOR, 0.5 + 0.5 * sin(m.time * 8.0)))
		else:
			var hot := Color(1.0, 0.45, 0.15) if cfg.get("dmg_type", "") == "fire" else Color(0.75, 0.7, 0.55)
			pen.circle(pos, r, Color(hot, 0.18 + 0.06 * sin(m.time * 5.0)))
			pen.arc(pos, r, 0, TAU, 40, Color(hot, 0.7), 2.0)


## Pociski w stylu rasy strzelca (D30): hieny — lasery, gibony — fale soniczne, krety — rozżarzone
## nity i pociski moździerza, dziki — oszczepy i głazy z runami, zające — lekkie strzałki i kule wiatru,
## wydry — harpuny i bańki wody. Armata to plazma, mróz — lodowy odłamek.
func draw_shot(s: Sim.Shot) -> void:
	var at := s.prev_pos.lerp(s.pos, m.render_alpha)
	var race := team_race(s.team)
	var col: Array = SHOT_COLORS.get(race, SHOT_COLORS["hyena"])
	var glow: Color = col[0]
	var core: Color = col[1]
	match s.kind:
		"arrow":
			var d := (s.target_pos - at).normalized()
			match race:
				"boar":  # oszczep z żarzącym się grotem
					pen.line(at - d * 12.0, at, Color(0.45, 0.32, 0.2), 2.5)
					pen.circle(at, 2.2, glow)
				"mole":  # rozgrzany nit ze smugą
					pen.line(at - d * 10.0, at, Color(glow, 0.45), 3.0)
					pen.line(at - d * 4.0, at, Color(0.8, 0.8, 0.82), 2.0)
				"gibbon":  # fala soniczna: dwa łuki w poprzek lotu
					var a := d.angle()
					pen.arc(at, 5.0, a - 1.0, a + 1.0, 6, Color(glow, 0.9), 2.0)
					pen.arc(at - d * 5.0, 4.0, a - 1.0, a + 1.0, 6, Color(glow, 0.5), 1.5)
				"otter":  # harpun z kroplami
					pen.line(at - d * 12.0, at, Color(0.55, 0.45, 0.32), 2.5)
					pen.circle(at - d * 15.0, 1.8, Color(glow, 0.6))
					pen.circle(at, 2.0, core)
				_:  # laser
					pen.line(at - d * 14.0, at, Color(glow, 0.45), 4.0)
					pen.line(at - d * 12.0, at, core, 1.5)
		"frost":
			var d := (s.target_pos - at).normalized()
			pen.circle(at, 7.0, Color(Main.FROST_COLOR, 0.3))
			pen.polygon(PackedVector2Array([at + d * 6.0, at + d.orthogonal() * 3.0, at - d * 6.0, at - d.orthogonal() * 3.0]), Color(0.85, 0.96, 1.0))
		_:
			var total := s.start.distance_to(s.target_pos)
			var f := 1.0 - at.distance_to(s.target_pos) / maxf(total, 1.0)
			var h := sin(PI * clampf(f, 0.0, 1.0)) * minf(70.0, total * 0.35)
			var top := at - Vector2(0, h)
			pen.ellipse(at, Vector2(4.0, 1.8), Color(0, 0, 0, 0.3))
			if s.kind == "cannonball":  # pocisk plazmowy
				pen.circle(top, 7.0, Color(1.0, 0.55, 0.15, 0.3))
				pen.circle(top, 4.0, Color(1.0, 0.6, 0.2))
				pen.circle(top, 2.0, Color(1.0, 0.95, 0.7))
				return
			match race:
				"hyena":  # kamień dusz
					pen.circle(top, 7.0, Color(glow, 0.25))
					pen.circle(top, 4.5, Color(0.16, 0.22, 0.16))
					pen.circle(top, 2.2, glow)
				"gibbon":  # skupiona fala dźwięku
					pen.circle(top, 7.0, Color(glow, 0.25))
					pen.arc(top, 5.0, 0, TAU, 12, glow, 2.0)
				"mole":  # pocisk moździerza
					pen.circle(top, 4.5, Color(0.2, 0.2, 0.22))
					pen.circle(top + Vector2(-1.5, -1.5), 1.5, Color(0.6, 0.6, 0.62))
				"hare":  # kula energii wiatru
					pen.circle(top, 7.0, Color(glow, 0.3))
					pen.circle(top, 3.5, core)
				"otter":  # bańka wody
					pen.circle(top, 6.0, Color(glow, 0.45))
					pen.arc(top, 6.0, 0, TAU, 12, core, 1.5)
				_:  # głaz z runą
					pen.circle(top, 5.5, Color(0.42, 0.4, 0.37))
					pen.circle(top, 2.0, glow)


func draw_selection() -> void:
	draw_hero_selection()
	if m.selected == null or not m.sim.is_alive(m.selected):
		return
	var pulse := 0.6 + 0.4 * sin(m.time * 6.0)
	pen.arc(m.selected.pos, 24, 0, TAU, 32, Color(1, 1, 1, pulse), 2.0)
	if Cfg.is_tower(m.selected.kind):
		var rng_: float = m.sim.tower_stats(m.selected.kind, m.selected.level)["range"]
		pen.circle(m.selected.pos, rng_, Color(1, 1, 1, 0.05))
		pen.arc(m.selected.pos, rng_, 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0)


## Zaznaczony dowódca: pulsujący krąg, trasa marszu i chorągiewka punktu postoju.
func draw_hero_selection() -> void:
	var h := m.sim.hero(m.me)
	if h == null or not m.sim.hero_alive(m.me) or m.state != Main.State.PLAY:
		return
	if h.state == "march" or h.state == "back":
		var pts := PackedVector2Array([h.pos])
		for i in range(h.path_i, h.path.size()):
			pts.append(h.path[i])
		for i in pts.size() - 1:
			pen.dashed_line(pts[i], pts[i + 1], Color(Main.HERO_COLOR, 0.6 if m.hero_selected else 0.3), 2.0, 7.0)
	if not m.hero_selected:
		return
	var pulse := 0.6 + 0.4 * sin(m.time * 6.0)
	pen.arc(h.pos, h.radius + 9, 0, TAU, 32, Color(Main.HERO_COLOR, pulse), 2.5)
	var flag := h.post
	pen.line(flag, flag + Vector2(0, -22), Color(0.9, 0.9, 0.9), 2.0)
	pen.polygon(PackedVector2Array([flag + Vector2(0, -22), flag + Vector2(13, -18), flag + Vector2(0, -13)]), Main.HERO_COLOR)
	pen.arc(flag, Cfg.COMMANDER_LEASH, 0, TAU, 48, Color(Main.HERO_COLOR, 0.15), 1.5)


func draw_ghost() -> void:
	if m.mode == "" or m.state != Main.State.PLAY:
		return
	var ability := m.controls.ability_mode()
	# zasięg rzucania wokół dowódcy — widoczny przez całe celowanie, także bez kursora (dotyk)
	var cast_range: float = m.sim.ability_config(ability, m.me).get("cast_range", 0.0) if ability != "" else 0.0
	if cast_range > 0.0 and m.sim.hero_alive(m.me):
		var hp := m.sim.hero(m.me).pos
		pen.circle(hp, cast_range, Color(Main.HERO_COLOR, 0.05))
		pen.arc(hp, cast_range, 0, TAU, 64, Color(Main.HERO_COLOR, 0.55), 2.0)
	if not (m.controls.pointer_active or m.controls.dragging):
		return
	var world := m.to_world(m.controls.pointer_screen)
	if ability != "":
		var ok := m.sim.ability_target_ok(ability, world, m.me)
		var tint := Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3)
		var r: float = m.sim.ability_config(ability, m.me).get("radius", 40.0)
		pen.circle(world, r, Color(tint, 0.12))
		pen.arc(world, r, 0, TAU, 48, Color(tint, 0.8), 2.0)
		return
	var cell := Cfg.snap(world)
	var ok := m.sim.can_place(cell)
	var tint := Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3)
	pen.rect(Rect2(cell - Vector2(Cfg.GRID, Cfg.GRID) / 2, Vector2(Cfg.GRID, Cfg.GRID)), Color(tint, 0.25))
	pen.rect(Rect2(cell - Vector2(Cfg.GRID, Cfg.GRID) / 2, Vector2(Cfg.GRID, Cfg.GRID)), Color(tint, 0.7), false, 2.0)
	draw_building_shape(m.mode, cell, Main.TEAM_COLORS[0], 0.0, 0.55)
	if Cfg.is_tower(m.mode):
		pen.arc(cell, m.sim.tower_stats(m.mode, 1)["range"], 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0)


func hp_bar(center: Vector2, width: float, frac: float, height := 5.0) -> void:
	var tl := center - Vector2(width / 2, height / 2)
	pen.rect(Rect2(tl - Vector2(1, 1), Vector2(width + 2, height + 2)), Color(0, 0, 0, 0.6))
	var col := Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.25, 0.2), 1.0 - clampf(frac, 0, 1))
	pen.rect(Rect2(tl, Vector2(width * clampf(frac, 0, 1), height)), col)


func progress(center: Vector2, frac: float) -> void:
	var tl := center - Vector2(17, 2)
	pen.rect(Rect2(tl, Vector2(34, 4)), Color(0, 0, 0, 0.5))
	pen.rect(Rect2(tl, Vector2(34 * clampf(frac, 0, 1), 4)), Color(1, 1, 1, 0.8))
