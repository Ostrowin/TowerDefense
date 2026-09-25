class_name Settings
extends RefCounted
## Ustawienia gracza (głośność, rozmiar interfejsu, licznik FPS), zapis w ConfigFile.
## Głośności działają przez szyny audio „SFX" i „Music" tworzone w `apply_audio`.

const UI_SCALES: Array[float] = [1.0, 1.15, 1.3]
const UI_SCALE_NAMES: Array[String] = ["Normalny", "Duży", "Bardzo duży"]

static var path := "user://settings.cfg"
static var sfx_volume := 0.8
static var music_volume := 0.5
## Na telefonie domyślnie największy interfejs: ekran ma ~7 cm wysokości, a HUD liczony jest
## na 720 px — przy ×1 napisy mają ~1,5 mm.
static var ui_scale_index := 2 if OS.has_feature("mobile") else 0
static var show_perf := false


static func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	ui_scale_index = clampi(cfg.get_value("ui", "scale", ui_scale_index), 0, UI_SCALES.size() - 1)
	show_perf = cfg.get_value("ui", "perf", show_perf)


static func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("ui", "scale", ui_scale_index)
	cfg.set_value("ui", "perf", show_perf)
	cfg.save(path)


static func ui_scale() -> float:
	return UI_SCALES[ui_scale_index]


## Tworzy (raz) szyny „SFX" i „Music" i ustawia ich głośność.
static func apply_audio() -> void:
	for bus in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_set_bus("SFX", sfx_volume)
	_set_bus("Music", music_volume)


static func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)
