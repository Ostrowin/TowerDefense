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
## Budowle tymczasowe (umiejętności `summon_building`, R7): stawia je umiejętność, nie gracz — poza
## BUILD_ORDER, bez zaznaczania, sprzedaży, ulepszeń, nagród i liczenia do obrony ścieżek.
##   heal, pulse   — co `pulse` s leczy własne jednostki w `range` o `heal` HP (totem pulsu)
##   repel, pulse  — co `pulse` s cofa wrogów naziemnych w `range` o `repel` px wzdłuż ścieżki
const TEMP_BUILDINGS := {
	"drill_turret": {"name": "Wiertło-wieżyczka", "temporary": true, "hp": 250.0,
		"range": 150.0, "dmg": 12.0, "cd": 0.6, "projectile": "arrow"},
	"volcano": {"name": "Wulkan", "temporary": true, "hp": 300.0,
		"range": 170.0, "dmg": 30.0, "cd": 3.0, "projectile": "rock", "splash": 60.0},
	"totem_turret": {"name": "Totem-wieżyczka", "temporary": true, "hp": 280.0,
		"range": 160.0, "dmg": 14.0, "cd": 0.8, "projectile": "arrow"},
	"pulse_totem": {"name": "Totem pulsu", "temporary": true, "hp": 250.0,
		"range": 130.0, "heal": 20.0, "pulse": 2.0},
	"repeller": {"name": "Odpychacz", "temporary": true, "hp": 300.0,
		"range": 90.0, "repel": 50.0, "pulse": 3.0},
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

# ---------------------------------------------------------------- umiejętności
# Umiejętność = typ efektu (`kind`) + liczby. Sim obsługuje typy, nie konkretne umiejętności,
# więc nowa umiejętność tego samego typu to sam wpis tutaj. Każdy typ działa dla obu drużyn.
#   strike        — salwy w obszar (radius, dmg, dmg_type, volleys, interval); trafia też latających
#   summon_units  — jednostki przy ścieżce (unit, count, max_lane_dist), na swojej połowie mapy
#   global        — leczy budynki i bazę rzucającego (heal = ułamek max HP, base_heal)
# Typy z dowódców (kod w Sim od T6 i dalej — do tego czasu wpis to tylko dane):
#   zone          — strefa trwała: mina (dmg, trigger = "enter") albo obrażenia co sekundę (dps); radius, duration
#   summon_building — tymczasowa budowla z BUILDINGS (building, duration)
#   buff          — wzmocnienie własnych jednostek w promieniu (stat, mult, duration; radius 0 = cała armia,
#                   "lane": true = jednostki na wskazanej ścieżce, "self": true = sam dowódca)
#   line          — przebicie wzdłuż linii od dowódcy (length, width, dmg, dmg_type)
#   execute       — dobija najsilniejszego wroga w promieniu (dmg; poniżej threshold HP — śmierć; boss tylko dmg)
#   demolish      — ładunek na budynek wroga (building_dmg; nie bije bazy)
#   burrow        — jednostki na wskazanej ścieżce pod ziemią (duration, speed_mult, quake_dmg, quake_radius)
#   raise_dead    — wrogowie ginący w promieniu wstają po naszej stronie (radius, duration)
#   weaken        — wrogowie w promieniu dostają więcej obrażeń (mult, duration; dmg — opcjonalny cios)
#   pull          — przyciąga najsilniejszego wroga do dowódcy (radius)
#   taunt         — wrogowie w promieniu biją dowódcę (radius, duration)
#   repel         — cofa wrogów w obszarze/na linii (distance; radius albo length + width)
#   leap          — skok dowódcy do punktu z uderzeniem (radius, dmg; repel — opcjonalne odrzucenie)
#   bounty_buff   — zabójstwa dają więcej złota (mult, duration)
# target: czy trzeba wskazać miejsce na mapie. Cooldown liczy się od startu partii.
# cast_range: zasięg rzucania od dowódcy (0 = bez ograniczenia: rasowe, global, rzucane bez dowódcy).
# Liczby umiejętności dowódców to punkt startowy — strojenie botami od T9.

const ABILITIES := {
	# --- dzisiejsze (dowódca-zastępca „Weteran")
	"arrows": {"name": "Deszcz strzał", "short": "Strzały", "kind": "strike", "cooldown": 40.0, "target": true,
		"cast_range": 0.0, "radius": 90.0, "dmg": 26.0, "dmg_type": "arrow", "volleys": 3, "interval": 0.45},
	"levy": {"name": "Pobór", "short": "Pobór", "kind": "summon_units", "cooldown": 60.0, "target": true,
		"cast_range": 0.0, "count": 4, "unit": "soldier", "max_lane_dist": 90.0},
	"repair": {"name": "Naprawa", "short": "Naprawa", "kind": "global", "cooldown": 55.0, "target": false,
		"cast_range": 0.0, "heal": 0.4, "base_heal": 80.0},

	# --- krety: Saper
	"minefield": {"name": "Pole minowe", "short": "Miny", "kind": "zone", "cooldown": 30.0, "target": true,
		"cast_range": 220.0, "radius": 50.0, "dmg": 60.0, "dmg_type": "blast", "trigger": "enter", "duration": 25.0},
	"drill_turret": {"name": "Wiertło-wieżyczka", "short": "Wiertło", "kind": "summon_building", "cooldown": 45.0,
		"target": true, "cast_range": 180.0, "building": "drill_turret", "duration": 20.0},
	"demo_charge": {"name": "Ładunek burzący", "short": "Ładunek", "kind": "demolish", "cooldown": 50.0, "target": true,
		"cast_range": 160.0, "building_dmg": 300.0},
	# --- krety: Snajper
	"snipe": {"name": "Strzał snajperski", "short": "Snajper", "kind": "execute", "cooldown": 25.0, "target": true,
		"cast_range": 360.0, "radius": 40.0, "dmg": 200.0, "threshold": 0.25, "dmg_type": "arrow"},
	"railshot": {"name": "Przebicie", "short": "Przebicie", "kind": "line", "cooldown": 30.0, "target": true,
		"cast_range": 320.0, "length": 320.0, "width": 24.0, "dmg": 90.0, "dmg_type": "arrow"},
	"barrage": {"name": "Ostrzał", "short": "Ostrzał", "kind": "strike", "cooldown": 40.0, "target": true,
		"cast_range": 300.0, "radius": 90.0, "dmg": 26.0, "dmg_type": "arrow", "volleys": 3, "interval": 0.45},
	# --- krety: Magma
	"magma_bolt": {"name": "Pocisk magmy", "short": "Magma", "kind": "strike", "cooldown": 18.0, "target": true,
		"cast_range": 240.0, "radius": 60.0, "dmg": 70.0, "dmg_type": "blast", "volleys": 1, "interval": 0.0},
	"lava_pool": {"name": "Kałuża lawy", "short": "Lawa", "kind": "zone", "cooldown": 35.0, "target": true,
		"cast_range": 220.0, "radius": 60.0, "dps": 18.0, "dmg_type": "fire", "trigger": "tick", "duration": 10.0},
	"volcano": {"name": "Wulkan", "short": "Wulkan", "kind": "summon_building", "cooldown": 60.0, "target": true,
		"cast_range": 200.0, "building": "volcano", "duration": 18.0},

	# --- gibony: Żelazny Chwyt
	"grip": {"name": "Chwyt", "short": "Chwyt", "kind": "pull", "cooldown": 25.0, "target": true,
		"cast_range": 200.0, "radius": 60.0},
	"war_roar": {"name": "Ryk wojenny", "short": "Ryk", "kind": "taunt", "cooldown": 35.0, "target": false,
		"cast_range": 0.0, "radius": 140.0, "duration": 5.0},
	"ground_slam": {"name": "Uderzenie o ziemię", "short": "Uderzenie", "kind": "strike", "cooldown": 20.0, "target": false,
		"cast_range": 0.0, "radius": 80.0, "dmg": 50.0, "dmg_type": "blast", "volleys": 1, "interval": 0.0, "stun": 1.0},
	# --- gibony: Niszczyciel
	"ram": {"name": "Taran", "short": "Taran", "kind": "demolish", "cooldown": 40.0, "target": true,
		"cast_range": 120.0, "building_dmg": 400.0},
	"shockwave": {"name": "Fala uderzeniowa", "short": "Fala", "kind": "repel", "cooldown": 30.0, "target": true,
		"cast_range": 260.0, "length": 260.0, "width": 40.0, "distance": 120.0, "dmg": 30.0},
	"swing": {"name": "Zamach", "short": "Zamach", "kind": "strike", "cooldown": 15.0, "target": false,
		"cast_range": 0.0, "radius": 70.0, "dmg": 60.0, "dmg_type": "blast", "volleys": 1, "interval": 0.0},
	# --- gibony: Bojowy Rytm
	"drumroll": {"name": "Werble", "short": "Werble", "kind": "buff", "cooldown": 35.0, "target": true,
		"cast_range": 200.0, "radius": 120.0, "stat": "attack_speed", "mult": 1.4, "duration": 10.0},
	"march_beat": {"name": "Rytm marszu", "short": "Marsz", "kind": "buff", "cooldown": 40.0, "target": true,
		"cast_range": 0.0, "lane": true, "stat": "speed", "mult": 1.5, "duration": 12.0},
	"thunder": {"name": "Grzmot", "short": "Grzmot", "kind": "strike", "cooldown": 30.0, "target": true,
		"cast_range": 220.0, "radius": 80.0, "dmg": 40.0, "dmg_type": "blast", "volleys": 1, "interval": 0.0, "stun": 1.5},

	# --- hieny: Nekromanta
	"raise": {"name": "Wskrzeszenie", "short": "Wskrzesz.", "kind": "raise_dead", "cooldown": 50.0, "target": true,
		"cast_range": 220.0, "radius": 110.0, "duration": 10.0},
	"grave_call": {"name": "Zew grobu", "short": "Zew", "kind": "summon_units", "cooldown": 55.0, "target": true,
		"cast_range": 240.0, "count": 4, "unit": "soldier", "max_lane_dist": 90.0},
	"curse": {"name": "Klątwa", "short": "Klątwa", "kind": "weaken", "cooldown": 30.0, "target": true,
		"cast_range": 240.0, "radius": 90.0, "mult": 1.3, "duration": 8.0},
	# --- hieny: Padlinożerca
	"feast": {"name": "Uczta", "short": "Uczta", "kind": "buff", "cooldown": 40.0, "target": false,
		"cast_range": 0.0, "radius": 140.0, "stat": "lifesteal", "mult": 0.3, "duration": 10.0},
	"finish_off": {"name": "Dobicie", "short": "Dobicie", "kind": "execute", "cooldown": 25.0, "target": true,
		"cast_range": 140.0, "radius": 40.0, "dmg": 120.0, "threshold": 0.35, "dmg_type": "blast"},
	"maul": {"name": "Rozszarpanie", "short": "Rozszarp.", "kind": "strike", "cooldown": 15.0, "target": false,
		"cast_range": 0.0, "radius": 70.0, "dmg": 55.0, "dmg_type": "blast", "volleys": 1, "interval": 0.0},
	# --- hieny: Rechot
	"pounce": {"name": "Skok", "short": "Skok", "kind": "leap", "cooldown": 20.0, "target": true,
		"cast_range": 220.0, "radius": 60.0, "dmg": 50.0},
	"cackle": {"name": "Rechot", "short": "Rechot", "kind": "weaken", "cooldown": 30.0, "target": false,
		"cast_range": 0.0, "radius": 120.0, "mult": 1.25, "duration": 6.0, "dmg": 25.0},
	"frenzy": {"name": "Szał żerowania", "short": "Szał", "kind": "buff", "cooldown": 35.0, "target": false,
		"cast_range": 0.0, "self": true, "stat": "attack_speed", "mult": 1.8, "duration": 8.0},

	# --- dziki: Inżynier Totemów
	"totem_turret": {"name": "Totem-wieżyczka", "short": "Totem", "kind": "summon_building", "cooldown": 40.0,
		"target": true, "cast_range": 180.0, "building": "totem_turret", "duration": 20.0},
	"pulse_totem": {"name": "Totem pulsu", "short": "Puls", "kind": "summon_building", "cooldown": 50.0,
		"target": true, "cast_range": 180.0, "building": "pulse_totem", "duration": 20.0},
	"repeller": {"name": "Odpychacz", "short": "Odpych.", "kind": "summon_building", "cooldown": 45.0,
		"target": true, "cast_range": 180.0, "building": "repeller", "duration": 15.0},
	# --- dziki: Stratowanie
	"boar_charge": {"name": "Szarża dowódcy", "short": "Szarża", "kind": "leap", "cooldown": 22.0, "target": true,
		"cast_range": 240.0, "radius": 70.0, "dmg": 45.0, "repel": 80.0},
	"herd": {"name": "Tabun", "short": "Tabun", "kind": "summon_units", "cooldown": 50.0, "target": true,
		"cast_range": 260.0, "count": 5, "unit": "soldier", "max_lane_dist": 90.0, "lifetime": 15.0},
	"thick_hide": {"name": "Twarda skóra", "short": "Skóra", "kind": "buff", "cooldown": 40.0, "target": true,
		"cast_range": 200.0, "radius": 120.0, "stat": "armor", "mult": 0.4, "duration": 10.0},
	# --- dziki: Kły
	"gore": {"name": "Rozpruwacz", "short": "Rozpruw.", "kind": "strike", "cooldown": 14.0, "target": false,
		"cast_range": 0.0, "radius": 70.0, "dmg": 70.0, "dmg_type": "blast", "volleys": 1, "interval": 0.0},
	"spikes": {"name": "Kolce w ziemi", "short": "Kolce", "kind": "zone", "cooldown": 35.0, "target": true,
		"cast_range": 200.0, "radius": 60.0, "dps": 12.0, "slow": 0.4, "dmg_type": "blast", "trigger": "tick", "duration": 10.0},
	"boar_fury": {"name": "Furia odyńca", "short": "Furia", "kind": "buff", "cooldown": 40.0, "target": false,
		"cast_range": 0.0, "self": true, "stat": "dmg", "mult": 1.6, "duration": 10.0},

	# --- umiejętności ras (bez zasięgu)
	"dig_in": {"name": "Podkop", "short": "Podkop", "kind": "burrow", "cooldown": 60.0, "target": true,
		"cast_range": 0.0, "duration": 6.0, "speed_mult": 1.3, "quake_dmg": 40.0, "quake_radius": 70.0},
	"song": {"name": "Pieśń", "short": "Pieśń", "kind": "buff", "cooldown": 60.0, "target": false,
		"cast_range": 0.0, "radius": 0.0, "stat": "speed", "mult": 1.25, "dmg_mult": 1.2, "duration": 8.0},
	"carrion": {"name": "Padlina", "short": "Padlina", "kind": "bounty_buff", "cooldown": 60.0, "target": false,
		"cast_range": 0.0, "mult": 1.5, "duration": 15.0},
	"stampede": {"name": "Szarża", "short": "Szarża", "kind": "buff", "cooldown": 60.0, "target": true,
		"cast_range": 0.0, "lane": true, "stat": "speed", "mult": 1.4, "knockback": 40.0, "duration": 10.0},
}
## Zestaw bez dowódcy (i dowódcy-zastępcy „Weteran") — dzisiejsza gra.
const ABILITY_ORDER: Array[String] = ["arrows", "levy", "repair"]
## Typy efektów, które Sim już obsługuje. Dowódca jest grywalny (`ready`), gdy wszystkie jego
## umiejętności i umiejętność rasy mają typ z tej listy — rośnie z T6/T9–T11b.
const IMPLEMENTED_KINDS: Array[String] = ["strike", "summon_units", "global", "zone", "summon_building",
	"buff", "line", "execute", "demolish", "burrow", "pull", "taunt", "repel",
	"weaken", "leap", "raise_dead", "bounty_buff"]
## Umiejętności `zone` i `summon_building` nie dalej niż tyle od bazy przeciwnika (R2).
const NO_CAST_NEAR_BASE := 150.0
## `demolish`: w jakim promieniu od wskazanego punktu szuka budynku wroga.
const DEMOLISH_PICK := 50.0
## Najwyższy pancerz po wzmocnieniach (`buff` pancerza) — nigdy pełna odporność.
const MAX_ARMOR := 0.85

# ---------------------------------------------------------------- dowódcy
# Postać na mapie sterowana przez gracza (R4 w docs/designs/dowodcy-ras.md). Klucze:
#   race       — id rasy z Races ("" = każda rasa: zastępca)
#   name, role — nazwa i rola w menu
#   hp, dmg, range, cd, speed, r — jak jednostka; armor jak w UNITS (blokuje strzały)
#   projectile — "" = wręcz; anti_air — czy trafia latających
#   building_mult — mnożnik obrażeń w budynki (domyślnie COMMANDER_BUILDING_MULT)
#   abilities  — 3 umiejętności z ABILITIES (kolejność = przyciski Q/E/R)
# Odrodzenie jest wspólne dla wszystkich (commander_respawn), bez pola per dowódca.

const COMMANDERS := {
	"veteran": {"race": "", "name": "Weteran", "role": "stary wyga, zna każdą sztuczkę",
		"hp": 420.0, "dmg": 18.0, "range": 24.0, "cd": 0.9, "speed": 70.0, "r": 12.0, "armor": 0.2,
		"projectile": "", "anti_air": false, "abilities": ["arrows", "levy", "repair"]},

	"sapper": {"race": "mole", "name": "Saper", "role": "kontrola ścieżki pułapkami",
		"hp": 450.0, "dmg": 20.0, "range": 24.0, "cd": 0.9, "speed": 72.0, "r": 12.0, "armor": 0.2,
		"projectile": "", "anti_air": false, "abilities": ["minefield", "drill_turret", "demo_charge"]},
	"sniper": {"race": "mole", "name": "Snajper", "role": "zabija grube cele z daleka",
		"hp": 280.0, "dmg": 30.0, "range": 200.0, "cd": 1.6, "speed": 66.0, "r": 11.0, "armor": 0.0,
		"projectile": "arrow", "anti_air": true, "abilities": ["snipe", "railshot", "barrage"]},
	"magma": {"race": "mole", "name": "Magma", "role": "obszarowe obrażenia w czasie",
		"hp": 340.0, "dmg": 18.0, "range": 140.0, "cd": 1.4, "speed": 66.0, "r": 11.0, "armor": 0.0,
		"projectile": "rock", "anti_air": false, "splash": 40.0, "abilities": ["magma_bolt", "lava_pool", "volcano"]},

	"iron_grip": {"race": "gibbon", "name": "Żelazny Chwyt", "role": "tank, łapie i trzyma wrogów",
		"hp": 650.0, "dmg": 18.0, "range": 26.0, "cd": 1.0, "speed": 64.0, "r": 14.0, "armor": 0.5,
		"projectile": "", "anti_air": false, "abilities": ["grip", "war_roar", "ground_slam"]},
	"wrecker": {"race": "gibbon", "name": "Niszczyciel", "role": "burzy wieże, rozbija szyki",
		"hp": 520.0, "dmg": 24.0, "range": 26.0, "cd": 1.1, "speed": 66.0, "r": 14.0, "armor": 0.3,
		"projectile": "", "anti_air": false, "building_mult": 1.0, "abilities": ["ram", "shockwave", "swing"]},
	"warbeat": {"race": "gibbon", "name": "Bojowy Rytm", "role": "wspiera armię bębnami",
		"hp": 360.0, "dmg": 12.0, "range": 24.0, "cd": 0.9, "speed": 70.0, "r": 12.0, "armor": 0.1,
		"projectile": "", "anti_air": false, "abilities": ["drumroll", "march_beat", "thunder"]},

	"necromancer": {"race": "hyena", "name": "Nekromanta", "role": "zamienia fale wroga we własną armię",
		"hp": 300.0, "dmg": 16.0, "range": 150.0, "cd": 1.3, "speed": 64.0, "r": 11.0, "armor": 0.0,
		"projectile": "arrow", "anti_air": true, "abilities": ["raise", "grave_call", "curse"]},
	"scavenger": {"race": "hyena", "name": "Padlinożerca", "role": "dobija rannych, żyje z zabójstw",
		"hp": 460.0, "dmg": 22.0, "range": 24.0, "cd": 0.9, "speed": 74.0, "r": 12.0, "armor": 0.1,
		"projectile": "", "anti_air": false, "abilities": ["feast", "finish_off", "maul"]},
	"cackle": {"race": "hyena", "name": "Rechot", "role": "szybki zabójca, osłabia hordę",
		"hp": 380.0, "dmg": 20.0, "range": 22.0, "cd": 0.6, "speed": 90.0, "r": 11.0, "armor": 0.0,
		"projectile": "", "anti_air": false, "abilities": ["pounce", "cackle", "frenzy"]},

	"totem_engineer": {"race": "boar", "name": "Inżynier Totemów", "role": "stawia tymczasowe totemy",
		"hp": 440.0, "dmg": 16.0, "range": 24.0, "cd": 0.9, "speed": 68.0, "r": 12.0, "armor": 0.2,
		"projectile": "", "anti_air": false, "abilities": ["totem_turret", "pulse_totem", "repeller"]},
	"stampede": {"race": "boar", "name": "Stratowanie", "role": "przełamuje linie wroga",
		"hp": 620.0, "dmg": 18.0, "range": 26.0, "cd": 1.0, "speed": 76.0, "r": 14.0, "armor": 0.4,
		"projectile": "", "anti_air": false, "abilities": ["boar_charge", "herd", "thick_hide"]},
	"tusks": {"race": "boar", "name": "Kły", "role": "czyste obrażenia wręcz",
		"hp": 480.0, "dmg": 32.0, "range": 24.0, "cd": 1.0, "speed": 72.0, "r": 13.0, "armor": 0.2,
		"projectile": "", "anti_air": false, "abilities": ["gore", "spikes", "boar_fury"]},
}
## Kolejność w menu (w obrębie rasy).
const COMMANDER_ORDER: Array[String] = ["sapper", "sniper", "magma", "iron_grip", "wrecker", "warbeat",
	"necromancer", "scavenger", "cackle", "totem_engineer", "stampede", "tusks", "veteran"]
## Umiejętność rasy: id rasy → id z ABILITIES. Działa zawsze, także po śmierci dowódcy.
const RACIAL := {"mole": "dig_in", "gibbon": "song", "hyena": "carrion", "boar": "stampede"}

## Odrodzenie dowódcy: COMMANDER_RESPAWN s + COMMANDER_RESPAWN_PER_WAVE na falę, najwyżej COMMANDER_RESPAWN_MAX.
const COMMANDER_RESPAWN := 20.0
const COMMANDER_RESPAWN_PER_WAVE := 2.0
const COMMANDER_RESPAWN_MAX := 40.0
## Nietykalność po odrodzeniu (s).
const COMMANDER_INVULNERABLE := 2.0
## Jak daleko od punktu postoju dowódca goni wroga.
const COMMANDER_LEASH := 120.0
## Dowódca bije budynki słabiej niż jednostki; bazy nie bije wcale.
const COMMANDER_BUILDING_MULT := 0.5

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


## Dane budynku gracza albo budowli tymczasowej.
static func building(kind: String) -> Dictionary:
	return BUILDINGS[kind] if BUILDINGS.has(kind) else TEMP_BUILDINGS[kind]


## Czy budynek strzela (wieże gracza i wroga, strzelające budowle tymczasowe).
static func is_shooter(kind: String) -> bool:
	return is_tower(kind) or (TEMP_BUILDINGS.has(kind) and TEMP_BUILDINGS[kind].has("dmg"))


static func is_tower(kind: String) -> bool:
	return kind == "tower" or kind == "cannon" or kind == "frost"


static func is_flying(kind: String) -> bool:
	return UNITS[kind].get("flying", false)


static func is_production(kind: String) -> bool:
	return BUILDINGS.has(kind) and BUILDINGS[kind].has("unit")


## Czas odrodzenia dowódcy w fali `wave` — jedna formuła dla wszystkich (R4).
static func commander_respawn(wave: int) -> float:
	return minf(COMMANDER_RESPAWN + COMMANDER_RESPAWN_PER_WAVE * wave, COMMANDER_RESPAWN_MAX)


## Umiejętności na pasku: 3 dowódcy + rasowa (jeśli rasa ją ma). Bez dowódcy — ABILITY_ORDER.
static func commander_abilities(commander: String) -> Array[String]:
	var out: Array[String] = []
	if commander == "":
		out.assign(ABILITY_ORDER)
		return out
	var c: Dictionary = COMMANDERS[commander]
	out.assign(c["abilities"])
	if RACIAL.has(c["race"]):
		out.append(RACIAL[c["race"]])
	return out


## Czy dowódca jest grywalny: Sim obsługuje typy wszystkich jego umiejętności (także rasowej).
static func commander_ready(commander: String) -> bool:
	for a in commander_abilities(commander):
		if not IMPLEMENTED_KINDS.has(ABILITIES[a]["kind"]):
			return false
	return true
