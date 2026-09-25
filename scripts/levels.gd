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
	for i in ALL.size():
		if ALL[i]["id"] == id:
			return i
	return -1
