class_name Cfg
extends RefCounted
## Cała konfiguracja gry w jednym miejscu — tu się stroi balans.
## Drużyny: 0 = gracz (lewo), 1 = wróg (prawo).

# ---------------------------------------------------------------- mapa (wspólne)
# Kształt map (ścieżki, bazy, złoża, sloty wież wroga) — w scripts/levels.gd.
# Świat jest większy niż ekran (VIEW) — kamera domyślnie pokazuje całość, oddaloną.

const VIEW := Vector2(1280, 720)
const GRID := 40.0
const BASE_R := 42.0
## HP baz [gracz, wróg]. Forteca wroga jest grubsza — wygrana ma wymagać
## oblężenia, a nie jednego wczesnego rusha.
const BASE_HP: Array[float] = [600.0, 2500.0]
const PATH_HALF := 24.0
## Minimalna odległość środka pola budowy od osi ścieżki.
const PATH_CLEARANCE := PATH_HALF + GRID / 2 + 2.0
const RIVER_HALF := 24.0
## O ile dalej niż własny zasięg jednostka „widzi" wroga i do niego podchodzi.
const AGGRO := 70.0
## Jak daleko poza własnym zasięgiem jednostka „widzi" budynek wroga przy ścieżce.
const BUILDING_AGGRO := 50.0
## Budynek nietrafiany od REGEN_DELAY s odzyskuje REGEN_RATE maks. HP na sekundę.
const REGEN_DELAY := 6.0
const REGEN_RATE := 0.03
## Odsunięcie wieży wroga od osi ścieżki (sloty z levels.gd).
const ENEMY_TOWER_OFFSET := 64.0
## Co ile fal wróg stawia/odbudowuje wieżę w wolnym slocie.
const ENEMY_BUILD_EVERY := 4

# ---------------------------------------------------------------- ekonomia

const PASSIVE_INCOME := 3.0
## Limity populacji. Bez nich w długiej partii jednostek przybywało bez końca
## (fala 50: ~2800) i gra się zatykała. Armia gracza na limicie = produkcja czeka;
## wrogowie na limicie = reszta fali czeka w bramie.
## Strojone botami: gracz musi mieć wyższy limit niż wróg (na Przesmyku przy 150
## nie przełamywał mostu), a kolejka krótka — przy 150 czekających baza wroga miała
## niekończące się posiłki na miejscu i Trudny był nie do wygrania.
const MAX_ARMY := 200
const MAX_ENEMIES := 150
const MAX_SPAWN_QUEUE := 40
const SELL_REFUND := 0.6
const MAX_LEVEL := 3

const DIFFICULTIES: Array[Dictionary] = [
	{"name": "Łatwy", "start_gold": 220, "enemy_hp": 0.8, "wave_interval": 1.15, "first_wave": 30.0},
	{"name": "Normalny", "start_gold": 160, "enemy_hp": 1.0, "wave_interval": 1.0, "first_wave": 22.0},
	{"name": "Trudny", "start_gold": 130, "enemy_hp": 1.25, "wave_interval": 0.85, "first_wave": 18.0},
]

# ---------------------------------------------------------------- jednostki
# projectile: "" = cios wręcz, inaczej rodzaj pocisku (arrow / rock).
# siege: celuje w budynki i bazę, zadaje im building_dmg.
# splash: promień obrażeń obszarowych pocisku.
# flying: leci prosto do bazy nad mapą, ignoruje ścieżki i jednostki; trafiają go
#         tylko pociski z ANTI_AIR (strzały, mróz) — nie wręcz, nie armaty, nie katapulty.
# armor: jaką część obrażeń od strzał blokuje (armaty, mróz i wręcz przechodzą w całości).

const UNITS := {
	"bat": {"name": "Nietoperz", "hp": 34.0, "dmg": 6.0, "range": 18.0, "cd": 0.7, "speed": 80.0, "r": 8.0,
		"projectile": "", "bounty": 5, "flying": true},
	"shield": {"name": "Tarczownik", "hp": 110.0, "dmg": 8.0, "range": 20.0, "cd": 0.9, "speed": 46.0, "r": 10.0,
		"projectile": "", "bounty": 10, "armor": 0.6},
	"soldier": {"name": "Piechur", "hp": 75.0, "dmg": 9.0, "range": 20.0, "cd": 0.8, "speed": 68.0, "r": 9.0, "projectile": ""},
	"archer": {"name": "Łucznik", "hp": 38.0, "dmg": 8.0, "range": 115.0, "cd": 1.1, "speed": 62.0, "r": 8.0, "projectile": "arrow"},
	"catapult": {"name": "Katapulta", "hp": 70.0, "dmg": 14.0, "range": 210.0, "cd": 3.2, "speed": 40.0, "r": 12.0,
		"projectile": "rock", "siege": true, "building_dmg": 45.0, "splash": 40.0},
	"grunt": {"name": "Ork", "hp": 55.0, "dmg": 7.0, "range": 20.0, "cd": 0.8, "speed": 58.0, "r": 9.0, "projectile": "", "bounty": 6},
	"runner": {"name": "Goblin", "hp": 28.0, "dmg": 5.0, "range": 18.0, "cd": 0.6, "speed": 110.0, "r": 7.0, "projectile": "", "bounty": 4},
	"brute": {"name": "Ogr", "hp": 280.0, "dmg": 20.0, "range": 24.0, "cd": 1.3, "speed": 42.0, "r": 14.0, "projectile": "", "bounty": 30},
	"warlord": {"name": "Wódz", "hp": 1400.0, "dmg": 38.0, "range": 28.0, "cd": 1.4, "speed": 34.0, "r": 19.0, "projectile": "", "bounty": 150},
}
## Mnożniki za poziom budynku produkcyjnego (poziom 1 = ×1).
const UNIT_HP_PER_LEVEL := 0.35
const UNIT_DMG_PER_LEVEL := 0.3

# ---------------------------------------------------------------- budynki
# upgrades: koszt przejścia na poziom 2 i 3.

const BUILDINGS := {
	"tower": {"name": "Wieża", "cost": 80, "upgrades": [70, 140], "hp": 450.0,
		"range": 170.0, "dmg": 14.0, "cd": 0.9, "projectile": "arrow"},
	"cannon": {"name": "Armata", "cost": 130, "upgrades": [110, 200], "hp": 500.0,
		"range": 150.0, "dmg": 24.0, "cd": 2.1, "projectile": "cannonball", "splash": 55.0},
	"frost": {"name": "Mróz", "cost": 110, "upgrades": [90, 160], "hp": 400.0,
		"range": 140.0, "dmg": 5.0, "cd": 1.4, "projectile": "frost", "splash": 55.0, "slow": 0.45, "slow_time": 2.0},
	"barracks": {"name": "Koszary", "cost": 120, "upgrades": [100, 180], "hp": 500.0, "unit": "soldier", "period": 7.0},
	"range": {"name": "Strzelnica", "cost": 150, "upgrades": [120, 200], "hp": 400.0, "unit": "archer", "period": 9.0},
	"workshop": {"name": "Warsztat", "cost": 200, "upgrades": [150, 250], "hp": 450.0, "unit": "catapult", "period": 16.0},
	"extractor": {"name": "Wydobywacz", "cost": 60, "upgrades": [80, 140], "hp": 300.0, "income": [2.5, 4.0, 5.5]},
}
## Kolejność przycisków budowy (i skrótów 1–6).
const BUILD_ORDER: Array[String] = ["tower", "cannon", "frost", "barracks", "range", "workshop"]

## Działko bazy — żeby pojedyncza jednostka nie zdejmowała bazy za darmo.
const BASE_GUN := {"range": 140.0, "dmg": 10.0, "cd": 1.0, "projectile": "arrow"}
## Startowy poziom działka bazy [gracz, wróg]; działko wroga rośnie razem z jego wieżami.
const BASE_GUN_LEVEL: Array[int] = [1, 2]
const TOWER_DMG_PER_LEVEL := 0.45
const TOWER_RANGE_PER_LEVEL := 20.0
const TOWER_CD_PER_LEVEL := 0.1
const PRODUCTION_SPEEDUP_PER_LEVEL := 0.15
const TOWER_KILL_BOUNTY := 50

## Mróz na kolejnych poziomach spowalnia mocniej i dłużej.
const SLOW_PER_LEVEL := 0.08
const SLOW_TIME_PER_LEVEL := 0.5

const PROJECTILE_SPEED := {"arrow": 480.0, "cannonball": 300.0, "rock": 260.0, "frost": 420.0}
## Pociski, które trafiają jednostki latające.
const ANTI_AIR: Array[String] = ["arrow", "frost"]

# ---------------------------------------------------------------- umiejętności gracza
# target: czy trzeba wskazać miejsce na mapie. Cooldown liczy się od startu partii.

const ABILITIES := {
	"arrows": {"name": "Deszcz strzał", "short": "Strzały", "cooldown": 40.0, "target": true,
		"radius": 90.0, "dmg": 26.0, "volleys": 3, "interval": 0.45},
	"levy": {"name": "Pobór", "short": "Pobór", "cooldown": 60.0, "target": true,
		"count": 4, "unit": "soldier", "max_lane_dist": 90.0},
	"repair": {"name": "Naprawa", "short": "Naprawa", "cooldown": 55.0, "target": false,
		"heal": 0.4, "base_heal": 80.0},
}
const ABILITY_ORDER: Array[String] = ["arrows", "levy", "repair"]

# ---------------------------------------------------------------- sprytny wróg
## Fala częściej wybiera słabo bronioną ścieżkę: waga ścieżki = 1 / (1 + obrona / LANE_DEFENSE_SCALE).
## Obrona = suma „siły" wież gracza w zasięgu ścieżki + jego jednostek na niej.
const LANE_DEFENSE_SCALE := 40.0

# ---------------------------------------------------------------- fale wroga

const FIRST_WAVE_INTERVAL := 22.0
const MIN_WAVE_INTERVAL := 12.0
const WAVE_INTERVAL_DECAY := 0.5
const ENEMY_HP_PER_WAVE := 0.07
## „Furia" wroga w późnej grze: od fali ENEMY_FURY_WAVE każda fala dokłada tyle do HP
## i obrażeń nowych wrogów. Przy limitach populacji partia potrafiła utknąć w pacie na
## setki fal — furia ją rozstrzyga, nie ruszając balansu wczesnej i środkowej gry.
const ENEMY_FURY_WAVE := 40
const ENEMY_FURY_PER_WAVE := 0.06
## Odstęp między jednostkami wychodzącymi na tę samą ścieżkę; maleje z każdą falą.
const SPAWN_GAP := 0.6
const SPAWN_GAP_DECAY := 0.01
const MIN_SPAWN_GAP := 0.25
## Na ile ścieżek dzieli się fala: 1, od fali WAVE_SPLIT_2 — 2, od WAVE_SPLIT_3 — 3.
const WAVE_SPLIT_2 := 6
const WAVE_SPLIT_3 := 12
## Na ile sekund przed falą widać, którą ścieżką przyjdzie.
const WAVE_WARNING := 10.0
## Między falami (od 1. fali) wróg wystawia pojedynczego orka co tyle sekund.
const ENEMY_TRICKLE := 8.0
const BOSS_EVERY := 10


## Skład fali n (od 1). Kolejność = kolejność wyjścia z bazy.
@warning_ignore("integer_division")
static func wave_composition(n: int) -> Array[String]:
	var out: Array[String] = []
	for i in 2 + n:
		out.append("grunt")
	if n >= 3:
		for i in n / 2:
			out.append("runner")
	for i in n / 4:
		out.append("brute")
	if n >= 4:
		for i in n / 3:
			out.append("shield")
	if n >= 5:
		for i in (n - 3) / 2:
			out.append("bat")
	if n % BOSS_EVERY == 0:
		out.append("warlord")
	return out


## Gładka krzywa przez punkty kontrolne (styczne jak w splajnie Catmulla-Roma).
static func smooth_curve(points: Array, bake_interval := 4.0) -> Curve2D:
	var c := Curve2D.new()
	c.bake_interval = bake_interval
	for i in points.size():
		var prev: Vector2 = points[maxi(i - 1, 0)]
		var next: Vector2 = points[mini(i + 1, points.size() - 1)]
		var t := (next - prev) * 0.2
		c.add_point(points[i], -t, t)
	return c


## Środek pola siatki, w które wpada punkt.
static func snap(p: Vector2) -> Vector2:
	return (p / GRID).floor() * GRID + Vector2(GRID, GRID) / 2


static func is_tower(kind: String) -> bool:
	return kind == "tower" or kind == "cannon" or kind == "frost"


static func is_flying(kind: String) -> bool:
	return UNITS[kind].get("flying", false)


static func is_production(kind: String) -> bool:
	return BUILDINGS.has(kind) and BUILDINGS[kind].has("unit")
