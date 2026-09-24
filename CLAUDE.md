# CLAUDE.md — TowerDefense (Godot)

Gra **tower defense + strategia** (ekonomiczny lane-pusher). Cel: **fajna gra** (nie nauka). Silnik: **Godot 4.7 + GDScript**. Cel wysyłki: **Android**. Historia decyzji: [DECISIONS.md](DECISIONS.md) (D15–D19; D15–D16 zastępują ustalenia z ery MonoGame). Budowa kodu: [ARCHITECTURE.md](ARCHITECTURE.md).

## Struktura
- `scripts/cfg.gd` (`Cfg`) — balans i konfiguracja (jednostki, budynki, umiejętności, fale). Strojenie = zmiana liczb tutaj.
- `scripts/levels.gd` (`Levels`) — mapy jako dane (ścieżki, złoża, sloty). Nowa mapa = nowy wpis + pełny bot_test.
- `scripts/progress.gd`, `scripts/settings.gd` — zapis w `user://`; testy podmieniają `path`, żeby nie ruszać danych gracza.
- `scripts/sim.gd` (`Sim`) — logika gry, **bez węzłów i rysowania**. Nowa mechanika trafia tu, z testem.
- `scripts/main.gd` — widok: render przez `_draw`, HUD z Control budowany w kodzie, input, efekty. Nie wkładaj tu reguł gry.
- `scripts/sfx.gd` (`Sfx`) — dźwięki syntezowane.

## Uruchamianie i testy
Godot z wingeta (nie ma go w PATH):
`C:\Users\lucci\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- gra: `--path .`
- import (po dodaniu `class_name`/plików): `--headless --import --path .`
- testy Sim + boty: `--headless --path . --script res://tests/bot_test.gd` (kod wyjścia 1 = błąd; ~4 min)
- same mechaniki (szybko, ~1 s): `... bot_test.gd -- --mechanics`
- same mecze botów (strojenie): `--headless --path . --script res://tests/bot_test.gd -- --balance`
- smoke widoku: `--headless --path . --fixed-fps 60 --script res://tests/ui_smoke_test.gd` (szukaj `SCRIPT ERROR`)

Po zmianie balansu odpal `-- --balance` i porównaj tabelę wyników. Po zmianie mapy (`Levels`) odpal pełny bot_test — sprawdza, czy nic nie ląduje na ścieżce, a pętle ścieżki nie nachodzą na siebie.
Wydajność mierz na TRWAJĄCEJ partii (`sim.result == 0`) — skończona partia nie liczy kroków i daje fałszywie niskie czasy.
Smoke test wstrzykuje zdarzenia przez `root.push_input(e, true)` — okno headless ma 64×64, bez `true` pozycje się rozjeżdżają.

## Konwencje
- Statyczne typy w GDScript (`var x: float`, jawny typ gdy RHS to Variant).
- Współrzędne: ekran wirtualny 1280×720 (stretch `canvas_items`/`keep`), świat 1600×900 pod `Camera2D`; ekran↔świat przez `_to_world`/`_to_screen`. Dotyk emulowany jako mysz + gesty dwoma palcami.
- Grafika na razie prymitywy; assety CC0 później.
- Zakres pod dyscypliną — najpierw zabawa rdzenia, potem treść.
- Commity robi użytkownik — nie commituj sam.
