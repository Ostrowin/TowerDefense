# CLAUDE.md — TowerDefense (Godot)

Gra **tower defense + strategia** (ekonomiczny lane-pusher). Cel: **fajna gra** (nie nauka). Silnik: **Godot 4.7 + GDScript**. Cel wysyłki: **Android**. Historia decyzji: [DECISIONS.md](DECISIONS.md) (D15–D25; D15–D16 zastępują ustalenia z ery MonoGame). Budowa kodu: [ARCHITECTURE.md](ARCHITECTURE.md).

## Struktura
- `scripts/cfg.gd` (`Cfg`) — balans i konfiguracja (jednostki, budynki, umiejętności, fale). Strojenie = zmiana liczb tutaj.
- `scripts/levels.gd` (`Levels`) — mapy jako dane (ścieżki, złoża, sloty). Nowa mapa = nowy wpis + pełny bot_test.
- `scripts/races.gd` (`Races`) — rasy wspólne z innymi grami tego świata (id i kolory jak tam). Na razie tożsamość (nazwa, kolor, hasło, przeciwnik), bez statystyk; grywalne `playable`, reszta „Wkrótce".
- `scripts/progress.gd`, `scripts/settings.gd` — zapis w `user://`; testy podmieniają `path`, żeby nie ruszać danych gracza.
- `scripts/sim.gd` (`Sim`) — logika gry, **bez węzłów i rysowania**. Nowa mechanika trafia tu, z testem. Zna też rzekę i mosty (`river`, `bridges`) oraz trasę po mapie dla dowódcy (`path_to`, A* omijający wodę).
- `scripts/main.gd` — widok: render przez `_draw`, HUD z Control budowany w kodzie, input, efekty. Nie wkładaj tu reguł gry.
- `scripts/sfx.gd` (`Sfx`) — dźwięki syntezowane.

## Uruchamianie i testy
Godot z wingeta (nie ma go w PATH):
`C:\Users\lucci\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- gra: `--path .`
- import (po dodaniu `class_name`/plików): `--headless --import --path .`
- testy Sim + boty: `--headless --path . --script res://tests/bot_test.gd` (kod wyjścia 1 = błąd; ~4 min)
- same mechaniki (~20 s — głównie testy limitów populacji): `... bot_test.gd -- --mechanics`
- same mecze botów (strojenie): `--headless --path . --script res://tests/bot_test.gd -- --balance`
- smoke widoku: `--headless --path . --fixed-fps 60 --script res://tests/ui_smoke_test.gd` (szukaj `SCRIPT ERROR`)
- wydajność późnej gry: `--headless --path . -- --bench res://tests/perf_test.gd --map 2 --minutes 10` (bez `--fixed-fps` — mierzy prawdziwy czas klatki; pusta scena headless to ~7 ms, to narzut silnika)
- benchmarki (`perf_test`, `render_probe`) to węzły uruchamiane przez grę parametrem `-- --bench <skrypt>` — eksportowany Godot ignoruje `--script`
- w grze: F3 = licznik FPS i czasów (sim / rysowanie / HUD); włączony licznik co 5 s trafia też do logu (`[perf]`)

Android (`tools/android.ps1`, PowerShell): eksport APK (release, podpis kluczem debug) → `adb install` → start gry.
`-NoInstall` sam eksport do `export/`, `-Log` log gry z telefonu, `-Bench` odpala `tests/perf_test.gd` NA TELEFONIE (wynik w logu; `-BenchScript res://tests/render_probe.gd` = koszt warstw renderu), `-DebugBuild` szablon debug.
Szablony eksportu: tylko pliki Androida w `%APPDATA%\Godot\export_templates\4.7.2.stable\`. SDK: `C:\Program Files (x86)\Android\android-sdk`, JDK 21: `C:\Program Files\Android\openjdk\jdk-21.0.8` (oba z Visual Studio).
Uwaga: powłoka Bash w Claude Code jest w piaskownicy — zapisy poza projektem (np. `%APPDATA%`) rób przez PowerShell.

Po zmianie balansu odpal `-- --balance` i porównaj tabelę wyników. Pełny bot_test porównuje mecze botów (gra bez dowódcy) z `tests/bot_baseline.txt` — różnica = błąd; wzorzec nadpisuje się tylko świadomie: `bot_test.gd -- --write-baseline`. Po zmianie mapy (`Levels`) odpal pełny bot_test — sprawdza, czy nic nie ląduje na ścieżce, a pętle ścieżki nie nachodzą na siebie.
Wydajność mierz na TRWAJĄCEJ partii (`sim.result == 0`) — skończona partia nie liczy kroków i daje fałszywie niskie czasy.
Nie odpalaj dwóch `bot_test` naraz (np. na dwóch kopiach repo) — dzielą `user://test_progress.cfg` i testy rekordów się wysypią.
Smoke test wstrzykuje zdarzenia przez `root.push_input(e, true)` — okno headless ma 64×64, bez `true` pozycje się rozjeżdżają.

## Konwencje
- Statyczne typy w GDScript (`var x: float`, jawny typ gdy RHS to Variant).
- Współrzędne: ekran wirtualny o wysokości 720, szerokość wg proporcji ekranu (stretch `canvas_items`/`expand` → `view_size`: 1280 przy 16:9, ~1600 na telefonie 20:9), świat 1600×900 pod `Camera2D`; ekran↔świat przez `_to_world`/`_to_screen`. Dotyk emulowany jako mysz + gesty dwoma palcami.
- Grafika na razie prymitywy; assety CC0 później.
- Umiejętności to dane: `Cfg.ABILITIES` z typem efektu (`kind`: strike / summon_units / global), `Sim` obsługuje typy, każdy dla obu drużyn (`use_ability(id, at, team)`). Nowa umiejętność istniejącego typu = wpis w `Cfg`; nowy typ = kod w `Sim` + test dla team 0 i team 1.
- Rysowanie świata w `main.gd` idzie przez `pen` (`Painter`: `pen.circle(...)` zamiast `draw_circle(...)`, te same argumenty) — cały świat to jedno wywołanie rysowania. Gołe `draw_circle`/`draw_arc`/`draw_colored_polygon` w pętli po jednostkach = setki wywołań i spadek FPS na telefonie (Mali). HUD (Control) i minimapa rysują normalnie.
- Zakres pod dyscypliną — najpierw zabawa rdzenia, potem treść.
- Commity robi użytkownik — nie commituj sam.
