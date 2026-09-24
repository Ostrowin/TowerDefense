class_name Progress
extends RefCounted
## Postęp gracza: najlepsze czasy wygranych per mapa × trudność, gwiazdki, samouczek.
## Zapis w ConfigFile pod `path` (testy podmieniają ścieżkę, żeby nie ruszać
## prawdziwego zapisu gracza).
##
##   [trzy_drogi]
##   best_0 = 191.2     ← najlepszy czas wygranej na Łatwym (s)
##   [meta]
##   tutorial_done = true

static var path := "user://progress.cfg"
static var _cfg: ConfigFile = null


static func _data() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(path)  # brak pliku = pusty postęp
	return _cfg


static func _save() -> void:
	_data().save(path)


## Zapisuje wygraną. Zwraca true, gdy to nowy rekord (albo pierwsza wygrana).
static func record_win(map_id: String, difficulty: int, time_s: float) -> bool:
	var key := "best_%d" % difficulty
	var prev: float = _data().get_value(map_id, key, INF)
	if time_s >= prev:
		return false
	_data().set_value(map_id, key, time_s)
	_save()
	return true


## Najlepszy czas wygranej (s) albo -1, gdy jeszcze nie wygrana.
static func best(map_id: String, difficulty: int) -> float:
	var t: float = _data().get_value(map_id, "best_%d" % difficulty, INF)
	return -1.0 if is_inf(t) else t


## Gwiazdki mapy = liczba poziomów trudności, na których ją wygrano (0–3).
static func stars(map_id: String) -> int:
	var n := 0
	for d in Cfg.DIFFICULTIES.size():
		if best(map_id, d) >= 0:
			n += 1
	return n


static func tutorial_done() -> bool:
	return _data().get_value("meta", "tutorial_done", false)


static func set_tutorial_done(done: bool) -> void:
	_data().set_value("meta", "tutorial_done", done)
	_save()


## Do testów: zapomina wczytane dane (następny odczyt sięgnie do `path`).
static func reset_cache() -> void:
	_cfg = null
