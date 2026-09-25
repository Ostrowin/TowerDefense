class_name Races
extends RefCounted
## Rasy (frakcje) wspólne dla gier z tego samego świata — id i kolory jak w pozostałych grach.
## Na razie to tożsamość: nazwa, kolor i hasło w menu — bez wpływu na statystyki. Grywalne mają
## `playable`; reszta widnieje w menu jako „Wkrótce". Przeciwnik gracza to losowa inna grywalna rasa.
##
## Klucze rasy:
##   id        — stały identyfikator (wspólny z innymi grami)
##   name      — nazwa w liczbie mnogiej (menu, banery, podpis bazy)
##   color     — kolor rasy (karta w menu; na mapie zostają czytelne barwy drużyn)
##   blurb     — hasło w menu
##   playable  — czy można nią grać

const ALL: Array[Dictionary] = [
	{"id": "bear", "name": "Niedźwiedzie", "color": Color("#8b5a2b"), "blurb": "Wielkie. Wściekłe. Wszystko przyjmą na klatę.", "playable": false},
	{"id": "wolf", "name": "Wilki", "color": Color("#9aa5b1"), "blurb": "Szybkie ciosy, instynkt stada.", "playable": false},
	{"id": "fox", "name": "Lisy", "color": Color("#ff7a29"), "blurb": "Biją rzadko, ale mocno.", "playable": false},
	{"id": "hare", "name": "Zające", "color": Color("#f5f5f5"), "blurb": "Za szybkie, żeby zginąć. Zazwyczaj.", "playable": false},
	{"id": "mole", "name": "Krety", "color": Color("#5d4037"), "blurb": "Inżynierowie podziemi.", "playable": true},
	{"id": "hedgehog", "name": "Jeże", "color": Color("#8a9a5b"), "blurb": "Dotknij, a pożałujesz.", "playable": false},
	{"id": "bat", "name": "Nietoperze", "color": Color("#8e44ad"), "blurb": "Nocni łowcy, przyszłe wampiry.", "playable": false},
	# gibony zastąpiły goryle (2026-09-25)
	{"id": "gibbon", "name": "Gibony", "color": Color("#d9c29c"), "blurb": "Długie ręce. Głośny śpiew.", "playable": true},
	{"id": "rat", "name": "Szczury", "color": Color("#b6d94c"), "blurb": "Choroba na czterech łapach.", "playable": false},
	{"id": "boar", "name": "Dziki", "color": Color("#9c3b1e"), "blurb": "Pełen gaz. Bez hamulców.", "playable": true},
	{"id": "otter", "name": "Wydry", "color": Color("#3fa7a0"), "blurb": "Trzymają drużynę przy życiu.", "playable": false},
	{"id": "hyena", "name": "Hieny", "color": Color("#c9a227"), "blurb": "Śmieją się z rannych.", "playable": true},
]


static func first_playable() -> int:
	for i in ALL.size():
		if ALL[i]["playable"]:
			return i
	return 0


## Dowódcy rasy (id z Cfg.COMMANDERS) w kolejności menu. Dopóki żaden nie jest grywalny,
## na końcu jest zastępca „Weteran" — rasa zostaje grywalna (R10).
static func commanders(index: int) -> Array[String]:
	var race: String = ALL[index]["id"]
	var out: Array[String] = []
	var any_ready := false
	for c in Cfg.COMMANDER_ORDER:
		if Cfg.COMMANDERS[c]["race"] == race:
			out.append(c)
			any_ready = any_ready or Cfg.commander_ready(c)
	if not any_ready:
		out.append("veteran")
	return out


## Umiejętność rasy (id z Cfg.ABILITIES) albo "" — rasa bez własnej umiejętności.
static func racial(index: int) -> String:
	return Cfg.RACIAL.get(ALL[index]["id"], "")


## Przeciwnik gracza: losowo jedna z pozostałych grywalnych ras (losowana przy starcie partii).
static func random_rival(index: int, rng: RandomNumberGenerator) -> int:
	var others: Array[int] = []
	for i in ALL.size():
		if i != index and ALL[i]["playable"]:
			others.append(i)
	return index if others.is_empty() else others[rng.randi_range(0, others.size() - 1)]
