class_name Levels
extends RefCounted
## Mapy gry jako dane. Wszystko, co zależy od kształtu mapy (strefa budowy, sloty
## wież wroga, linie zbiórki, mosty, plan bota), Sim i widok wyliczają z tych danych.
##
## Klucze mapy:
##   id, name, desc      — identyfikator (zapis postępu), nazwa i opis do menu
##   size                — rozmiar świata
##   p_base, e_base      — bazy gracza i wroga (pierwszy/ostatni punkt każdej ścieżki)
##   lanes               — ścieżki: {"name", "points"} od bazy gracza do bazy wroga
##   river               — punkty kontrolne rzeki ([] = brak rzeki). Sim liczy z nich krzywą i mosty
##                         (odcinki ścieżek nad wodą); woda blokuje ruch dowódcy poza mostami
##   nodes, richness     — złoża i mnożnik ich wydobycia (>1 = „sporne", przy ścieżce wroga)
##   enemy_slots         — sloty wież wroga: (ścieżka, odległość od bazy wroga, strona ±1)
##   enemy_start_towers  — ile pierwszych slotów jest zajętych od startu
##   build_rect          — prostokąt, w którym mogą leżeć środki pól budowy
##   rally_s             — linia zbiórki (postawa „Obrona"), odległość od bazy gracza wzdłuż ścieżki
##
## Każda mapa ma 3 ścieżki (Północ/Środek/Południe liczone od strony gracza).
## Po zmianie punktów odpal tests/bot_test.gd — sprawdza, czy złoża i sloty nie leżą
## na ścieżkach, a zakręty jednej ścieżki nie nachodzą na siebie.

const ALL: Array[Dictionary] = [
	{
		"id": "trzy_drogi",
		"name": "Trzy drogi",
		"desc": "Trzy kręte ścieżki przez rzekę. Klasyka na początek.",
		"size": Vector2(1600, 900),
		"p_base": Vector2(90, 450),
		"e_base": Vector2(1510, 450),
		"lanes": [
			{"name": "Północ", "points": [
				Vector2(90, 450), Vector2(170, 380), Vector2(230, 290), Vector2(330, 220), Vector2(470, 200),
				Vector2(590, 260), Vector2(700, 300), Vector2(820, 240), Vector2(940, 180), Vector2(1080, 190),
				Vector2(1200, 250), Vector2(1320, 320), Vector2(1430, 390), Vector2(1510, 450)]},
			{"name": "Środek", "points": [
				Vector2(90, 450), Vector2(200, 450), Vector2(320, 500), Vector2(450, 430), Vector2(580, 500),
				Vector2(710, 430), Vector2(850, 500), Vector2(990, 420), Vector2(1130, 490), Vector2(1260, 420),
				Vector2(1400, 460), Vector2(1510, 450)]},
			{"name": "Południe", "points": [
				Vector2(90, 450), Vector2(170, 520), Vector2(230, 610), Vector2(330, 680), Vector2(470, 700),
				Vector2(590, 640), Vector2(700, 600), Vector2(820, 660), Vector2(940, 720), Vector2(1080, 710),
				Vector2(1200, 650), Vector2(1320, 580), Vector2(1430, 510), Vector2(1510, 450)]},
		],
		"river": [Vector2(850, -40), Vector2(880, 140), Vector2(830, 320), Vector2(885, 500), Vector2(835, 700), Vector2(870, 940)],
		"nodes": [Vector2(240, 150), Vector2(440, 320), Vector2(440, 580), Vector2(240, 750), Vector2(640, 215), Vector2(640, 685)],
		"richness": [1.0, 1.0, 1.0, 1.0, 1.6, 1.6],
		"enemy_slots": [
			Vector3(0, 430, -1), Vector3(1, 420, -1), Vector3(2, 430, 1),
			Vector3(0, 230, 1), Vector3(1, 250, 1), Vector3(2, 230, -1)],
		"enemy_start_towers": 3,
		"build_rect": Rect2(40, 140, 700, 640),
		"rally_s": 300.0,
	},
	{
		"id": "przesmyk",
		"name": "Przesmyk",
		"desc": "Wszystkie ścieżki zbiegają się na jednym moście i zamieniają stronami.",
		"size": Vector2(1600, 900),
		"p_base": Vector2(90, 450),
		"e_base": Vector2(1510, 450),
		"lanes": [
			{"name": "Północ", "points": [
				Vector2(90, 450), Vector2(160, 360), Vector2(230, 250), Vector2(350, 170), Vector2(490, 190),
				Vector2(580, 290), Vector2(630, 400), Vector2(680, 450), Vector2(740, 450), Vector2(800, 450),
				Vector2(860, 450), Vector2(920, 450), Vector2(990, 540), Vector2(1070, 660), Vector2(1180, 730),
				Vector2(1310, 710), Vector2(1420, 610), Vector2(1480, 520), Vector2(1510, 450)]},
			{"name": "Środek", "points": [
				Vector2(90, 450), Vector2(200, 440), Vector2(300, 510), Vector2(420, 540), Vector2(540, 480),
				Vector2(620, 440), Vector2(680, 450), Vector2(740, 450), Vector2(800, 450), Vector2(860, 450),
				Vector2(920, 450), Vector2(1000, 450), Vector2(1100, 405), Vector2(1220, 440), Vector2(1340, 480),
				Vector2(1440, 460), Vector2(1510, 450)]},
			{"name": "Południe", "points": [
				Vector2(90, 450), Vector2(160, 540), Vector2(230, 650), Vector2(350, 730), Vector2(490, 710),
				Vector2(580, 610), Vector2(630, 500), Vector2(680, 450), Vector2(740, 450), Vector2(800, 450),
				Vector2(860, 450), Vector2(920, 450), Vector2(990, 360), Vector2(1070, 240), Vector2(1180, 170),
				Vector2(1310, 190), Vector2(1420, 290), Vector2(1480, 380), Vector2(1510, 450)]},
		],
		"river": [Vector2(800, -40), Vector2(830, 150), Vector2(785, 330), Vector2(800, 450), Vector2(825, 600), Vector2(790, 760), Vector2(810, 940)],
		"nodes": [Vector2(240, 130), Vector2(410, 320), Vector2(410, 650), Vector2(240, 770), Vector2(735, 385), Vector2(735, 515)],
		"richness": [1.0, 1.0, 1.0, 1.0, 1.6, 1.6],
		"enemy_slots": [
			Vector3(1, 380, 1), Vector3(0, 300, 1), Vector3(2, 300, -1),
			Vector3(1, 250, -1), Vector3(0, 520, -1), Vector3(2, 520, 1)],
		"enemy_start_towers": 3,
		"build_rect": Rect2(40, 100, 700, 700),
		"rally_s": 300.0,
	},
	{
		"id": "serpentyna",
		"name": "Serpentyna",
		"desc": "Krótki Środek, bardzo długa kręta Północ. Wieże w zakolach biją kilka pętli naraz.",
		"size": Vector2(1600, 900),
		"p_base": Vector2(90, 450),
		"e_base": Vector2(1510, 450),
		"lanes": [
			{"name": "Północ", "points": [
				Vector2(90, 450), Vector2(150, 330), Vector2(210, 200), Vector2(300, 120), Vector2(400, 310),
				Vector2(500, 120), Vector2(600, 310), Vector2(700, 120), Vector2(800, 310), Vector2(900, 120),
				Vector2(1000, 310), Vector2(1100, 120), Vector2(1200, 310), Vector2(1300, 120), Vector2(1400, 300),
				Vector2(1510, 450)]},
			{"name": "Środek", "points": [
				Vector2(90, 450), Vector2(260, 440), Vector2(430, 470), Vector2(600, 445), Vector2(780, 460),
				Vector2(960, 440), Vector2(1140, 460), Vector2(1320, 445), Vector2(1510, 450)]},
			{"name": "Południe", "points": [
				Vector2(90, 450), Vector2(160, 560), Vector2(260, 650), Vector2(400, 700), Vector2(540, 640),
				Vector2(680, 720), Vector2(820, 650), Vector2(960, 730), Vector2(1100, 660), Vector2(1240, 730),
				Vector2(1380, 640), Vector2(1470, 540), Vector2(1510, 450)]},
		],
		"river": [],
		"nodes": [Vector2(70, 250), Vector2(330, 570), Vector2(560, 570), Vector2(70, 650), Vector2(600, 190), Vector2(800, 190)],
		"richness": [1.0, 1.0, 1.0, 1.0, 1.6, 1.6],
		"enemy_slots": [
			Vector3(1, 260, 1), Vector3(1, 260, -1), Vector3(1, 520, 1),
			Vector3(0, 200, 1), Vector3(2, 320, 1), Vector3(1, 520, -1)],
		"enemy_start_towers": 3,
		"build_rect": Rect2(40, 100, 700, 700),
		"rally_s": 300.0,
	},
]


static func index_of(id: String) -> int:
	for i in count():
		if level(i)["id"] == id:
			return i
	return -1


## Wszystkie mapy: najpierw solo (`ALL`), potem coop (`COOP`) — indeks mapy w Sim i w zapisie.
static func count() -> int:
	return ALL.size() + COOP.size()


static func level(i: int) -> Dictionary:
	return ALL[i] if i < ALL.size() else COOP[i - ALL.size()]


static func coop_indices() -> Array[int]:
	var out: Array[int] = []
	for i in COOP.size():
		out.append(ALL.size() + i)
	return out


# ================================================================ mapy coop (gra ze znajomym)
## Dwie bazy graczy po lewej (góra i dół), jedna forteca wroga po prawej, łącznik między bazami.
## Rysowana jest górna połowa (baza A, jej 2 ścieżki, złoża, strefa budowy); dolna to lustro (y → H − y),
## więc obaj mają te same warunki. Dodatkowe klucze względem map solo:
##   coop           — true (menu solo i wyzwanie dnia ich nie pokazują)
##   p_bases        — bazy graczy [A, B] (A = gracz 0, B = gracz 2 — pierwszy gość)
##   lanes[].home   — czyja to ścieżka: 0 = baza A, 1 = baza B
##   build_rects    — strefa budowy każdego gracza [A, B]
##   connectors     — łączniki baz {a, b, points}: gdy baza padnie, wrogowie z jej ścieżek idą nim do żywej
##   players        — ilu graczy (lobby startuje przy komplecie)
##   fortress_mult  — (opcjonalnie) dodatkowy mnożnik HP fortecy wroga
## Sloty wież wroga: indeksy ścieżek jak w `lanes` (A: 0, 1; B: 2, 3).

const COOP_SIZE := Vector2(1900, 1250)
const COOP_E_BASE := Vector2(1800, 625)

static var COOP: Array[Dictionary] = [
	_mirror_coop({
		"id": "coop_drogi",
		"name": "Bliźniacze drogi",
		"desc": "Dwie bazy, jedna forteca wroga. Środkowe ścieżki zbiegają się pod fortecą.",
		"base": Vector2(100, 330),
		"lanes": [
			{"name": "Północ", "points": [
				Vector2(100, 330), Vector2(200, 250), Vector2(330, 170), Vector2(500, 140), Vector2(680, 190),
				Vector2(820, 240), Vector2(980, 170), Vector2(1150, 150), Vector2(1330, 210), Vector2(1500, 330),
				Vector2(1650, 470), COOP_E_BASE]},
			{"name": "Środek Pn.", "points": [
				Vector2(100, 330), Vector2(230, 360), Vector2(380, 420), Vector2(530, 380), Vector2(690, 450),
				Vector2(850, 400), Vector2(1010, 480), Vector2(1170, 440), Vector2(1330, 520), Vector2(1500, 560),
				Vector2(1650, 600), COOP_E_BASE]},
		],
		"mirror_names": ["Południe", "Środek Pd."],
		"river": [Vector2(900, -40), Vector2(930, 200), Vector2(880, 420), Vector2(935, 625)],
		"nodes": [Vector2(80, 170), Vector2(330, 290), Vector2(560, 280), Vector2(1000, 300)],
		"richness": [1.0, 1.0, 1.0, 1.6],
		"enemy_slots": [Vector3(0, 430, -1), Vector3(1, 420, -1), Vector3(0, 230, 1), Vector3(1, 250, 1)],
		"build_rect": Rect2(40, 60, 700, 500),
	}),
	_mirror_coop({
		"id": "coop_przesmyk",
		"name": "Wspólny przesmyk",
		"desc": "Wszystkie cztery ścieżki przechodzą przez jeden most i zamieniają się stronami.",
		"base": Vector2(100, 330),
		"lanes": [
			{"name": "Północ", "points": [
				Vector2(100, 330), Vector2(220, 200), Vector2(400, 150), Vector2(580, 250), Vector2(700, 450),
				Vector2(780, 600), Vector2(850, 625), Vector2(950, 625), Vector2(1050, 625), Vector2(1150, 700),
				Vector2(1300, 950), Vector2(1500, 1000), Vector2(1680, 850), COOP_E_BASE]},
			{"name": "Środek Pn.", "points": [
				Vector2(100, 330), Vector2(250, 420), Vector2(430, 470), Vector2(600, 560), Vector2(760, 615),
				Vector2(850, 625), Vector2(950, 625), Vector2(1050, 625), Vector2(1200, 560), Vector2(1400, 500),
				Vector2(1600, 560), COOP_E_BASE]},
		],
		"mirror_names": ["Południe", "Środek Pd."],
		"river": [Vector2(950, -40), Vector2(980, 200), Vector2(930, 420), Vector2(950, 625)],
		"nodes": [Vector2(230, 110), Vector2(400, 300), Vector2(560, 410), Vector2(870, 500)],
		"richness": [1.0, 1.0, 1.0, 1.6],
		"enemy_slots": [Vector3(0, 300, 1), Vector3(1, 300, -1), Vector3(0, 500, -1), Vector3(1, 520, 1)],
		"build_rect": Rect2(40, 60, 700, 500),
	}),
	_mirror_coop({
		"id": "coop_serpentyna",
		"name": "Podwójna serpentyna",
		"desc": "Krótkie środki, bardzo długie kręte skrzydła. Wieże w zakolach biją kilka pętli naraz.",
		"base": Vector2(100, 330),
		"lanes": [
			{"name": "Północ", "points": [
				Vector2(100, 330), Vector2(160, 200), Vector2(260, 110), Vector2(360, 300), Vector2(460, 110),
				Vector2(560, 300), Vector2(660, 110), Vector2(760, 300), Vector2(860, 110), Vector2(960, 300),
				Vector2(1060, 110), Vector2(1160, 300), Vector2(1260, 110), Vector2(1360, 300), Vector2(1460, 110),
				Vector2(1600, 260), Vector2(1720, 450), COOP_E_BASE]},
			{"name": "Środek Pn.", "points": [
				Vector2(100, 330), Vector2(300, 400), Vector2(520, 440), Vector2(760, 470), Vector2(1000, 500),
				Vector2(1240, 540), Vector2(1480, 580), COOP_E_BASE]},
		],
		"mirror_names": ["Południe", "Środek Pd."],
		"river": [],
		"nodes": [Vector2(70, 170), Vector2(440, 350), Vector2(200, 490), Vector2(900, 385)],
		"richness": [1.0, 1.0, 1.0, 1.6],
		"enemy_slots": [Vector3(1, 260, 1), Vector3(1, 520, -1), Vector3(0, 200, 1), Vector3(1, 420, 1)],
		"build_rect": Rect2(40, 60, 700, 500),
	}),
	# --- 3 i 4 graczy: forteca w środku, gracze dookoła (ten sam klin obrócony) ---
	_ring_coop({
		"id": "coop3_trojzab", "name": "Trójząb", "players": 3, "angle": PI,
		"desc": "Trzech graczy wokół fortecy. Proste ścieżki do środka, łączniki po obwodzie.",
		"lanes": RING_STRAIGHT, "nodes": RING_STRAIGHT_NODES,
	}),
	_ring_coop({
		"id": "coop3_wir", "name": "Wir (3)", "players": 3, "angle": PI,
		"desc": "Trzech graczy, ścieżki skręcają jak wir — lewa skrzydłowa jest długa i kręta.",
		"lanes": RING_SWIRL, "nodes": RING_SWIRL_NODES,
	}),
	_ring_coop({
		"id": "coop4_krzyz", "name": "Krzyż", "players": 4, "angle": PI * 1.25,
		"desc": "Czterech graczy w rogach, forteca w środku. Proste ścieżki, łączniki wzdłuż brzegów.",
		"lanes": RING_STRAIGHT, "nodes": RING_STRAIGHT_NODES,
	}),
	_ring_coop({
		"id": "coop4_wir", "name": "Wir (4)", "players": 4, "angle": PI * 1.25,
		"desc": "Czterech graczy, ścieżki skręcają jak wir.",
		"lanes": RING_SWIRL, "nodes": RING_SWIRL_NODES,
	}),
]


# ---------------------------------------------------------------- mapy promieniste (3–4 graczy)
## Klin gracza w układzie lokalnym: x — od bazy (0) do fortecy w środku (RING_R), y — w bok.
## `_ring_coop` obraca go dla każdego gracza, więc wszyscy mają te same warunki.

const RING_SIZE := Vector2(2600, 2600)
const RING_R := 900.0  ## w jednostkach klina; w świecie × RING_SCALE
const RING_SCALE := 1.3
const RING_STRAIGHT := [
	[Vector2(0, 0), Vector2(150, -90), Vector2(320, -150), Vector2(500, -150), Vector2(660, -100), Vector2(790, -40), Vector2(RING_R, 0)],
	[Vector2(0, 0), Vector2(150, 90), Vector2(320, 150), Vector2(500, 150), Vector2(660, 100), Vector2(790, 40), Vector2(RING_R, 0)],
]
const RING_STRAIGHT_NODES := [[Vector2(170, -200), 1.0], [Vector2(170, 200), 1.0], [Vector2(400, 0), 1.0], [Vector2(620, 0), 1.6]]
const RING_SWIRL := [
	[Vector2(0, 0), Vector2(140, -120), Vector2(320, -230), Vector2(520, -240), Vector2(700, -150), Vector2(830, -50), Vector2(RING_R, 0)],
	[Vector2(0, 0), Vector2(170, 70), Vector2(360, 110), Vector2(560, 90), Vector2(740, 40), Vector2(RING_R, 0)],
]
const RING_SWIRL_NODES := [[Vector2(180, -30), 1.0], [Vector2(170, 190), 1.0], [Vector2(420, -60), 1.0], [Vector2(620, -80), 1.6]]


## Mapa promienista: n baz na okręgu wokół fortecy (środek mapy), każdy klin to samo w obrocie; łączniki
## między sąsiednimi bazami po obwodzie (wypchnięte na zewnątrz). Sloty wież wroga: po jednym na ścieżkę.
static func _ring_coop(d: Dictionary) -> Dictionary:
	var n: int = d["players"]
	var c := RING_SIZE / 2.0
	var bases: Array = []
	var lanes: Array = []
	var nodes: Array = []
	var richness: Array = []
	var slots: Array = []
	var rects: Array = []
	for k in n:
		var dir := Vector2.from_angle(d["angle"] + TAU * k / n)  # od środka do bazy
		var base := c + dir * RING_R * RING_SCALE
		var fwd := -dir * RING_SCALE
		var side := fwd.orthogonal()
		bases.append(base)
		for j in 2:
			var pts: Array = []
			for p: Vector2 in d["lanes"][j]:
				pts.append((base + fwd * p.x + side * p.y).round())
			lanes.append({"name": "%s %d" % [["Lewa", "Prawa"][j], k + 1], "points": pts, "home": k})
			slots.append(Vector3(k * 2 + j, 330, 1 if j == 0 else -1))
	slots.sort_custom(func(x: Vector3, y: Vector3) -> bool: return int(x.x) % 2 < int(y.x) % 2 or (int(x.x) % 2 == int(y.x) % 2 and x.x < y.x))  # startowe wieże: po jednej u każdego
	for k in n:
		var dir := Vector2.from_angle(d["angle"] + TAU * k / n)
		var base: Vector2 = bases[k]
		var fwd := -dir * RING_SCALE
		var side := fwd.orthogonal()
		for nd: Array in d["nodes"]:
			nodes.append((base + fwd * nd[0].x + side * nd[0].y).round())
			richness.append(nd[1])
		var zc := base + fwd * 190.0
		rects.append(Rect2(zc - Vector2(280, 280), Vector2(560, 560)))
	var connectors: Array = []
	for k in n:
		var a: Vector2 = bases[k]
		var b: Vector2 = bases[(k + 1) % n]
		var out := ((a + b) / 2.0 - c).normalized()
		var mid := (a + b) / 2.0 + out * 250.0  # łuk na zewnątrz — z dala od złóż i ścieżek klina
		var ra := a + (a - c).normalized() * 120.0
		var rb := b + (b - c).normalized() * 120.0
		connectors.append({"a": k, "b": (k + 1) % n, "points": [a, ra, ra.lerp(mid, 0.5) + out * 80.0, mid, rb.lerp(mid, 0.5) + out * 80.0, rb, b]})
	return {
		"id": d["id"], "name": d["name"], "desc": d["desc"], "coop": true, "players": n,
		"size": RING_SIZE, "p_base": bases[0], "e_base": c, "p_bases": bases,
		"lanes": lanes, "river": [], "nodes": nodes, "richness": richness,
		"enemy_slots": slots, "enemy_start_towers": n,
		"fortress_mult": 5.0,  # forteca w środku, bita z 6–8 ścieżek naraz — bez tego partia trwa 2 minuty
		"build_rect": rects[0], "build_rects": rects, "rally_s": 300.0, "connectors": connectors,
	}


static func _flip(p: Vector2) -> Vector2:
	return Vector2(p.x, COOP_SIZE.y - p.y)


## Pełna mapa coop z górnej połowy: ścieżki, złoża, sloty i strefa budowy odbite dla bazy B, rzeka dopełniona
## lustrem (jej punkty kończą się na osi), łącznik wzdłuż lewej krawędzi.
static func _mirror_coop(half: Dictionary) -> Dictionary:
	var a: Vector2 = half["base"]
	var b := _flip(a)
	var lanes: Array = []
	for l: Dictionary in half["lanes"]:
		lanes.append({"name": l["name"], "points": l["points"], "home": 0})
	for i in half["lanes"].size():
		var pts: Array = []
		for p: Vector2 in half["lanes"][i]["points"]:
			pts.append(_flip(p))
		lanes.append({"name": half["mirror_names"][i], "points": pts, "home": 1})
	var river: Array = half["river"].duplicate()
	if not river.is_empty():
		for i in range(river.size() - 2, -1, -1):
			river.append(_flip(river[i]))
	var nodes: Array = half["nodes"].duplicate()
	var richness: Array = half["richness"].duplicate()
	for i in half["nodes"].size():
		nodes.append(_flip(half["nodes"][i]))
		richness.append(half["richness"][i])
	var n: int = half["lanes"].size()
	var slots: Array = []
	for s: Vector3 in half["enemy_slots"]:  # przeplatane A, B — startowe wieże po równo
		slots.append(s)
		slots.append(Vector3(s.x + n, s.y, -s.z))
	var ra: Rect2 = half["build_rect"]
	var rb := Rect2(ra.position.x, COOP_SIZE.y - ra.end.y, ra.size.x, ra.size.y)
	var mid := (a + b) / 2.0
	return {
		"id": half["id"], "name": half["name"], "desc": half["desc"], "coop": true,
		"size": COOP_SIZE, "p_base": a, "e_base": COOP_E_BASE, "p_bases": [a, b],
		"lanes": lanes, "river": river, "nodes": nodes, "richness": richness,
		"enemy_slots": slots, "enemy_start_towers": 4,
		"build_rect": ra, "build_rects": [ra, rb], "rally_s": 300.0,
		"players": 2,
		"connectors": [{"a": 0, "b": 1, "points": [a, Vector2(a.x - 30, a.y + (mid.y - a.y) * 0.5), Vector2(a.x - 40, mid.y),
			Vector2(b.x - 30, b.y - (b.y - mid.y) * 0.5), b]}],
	}
