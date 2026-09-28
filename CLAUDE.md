# CLAUDE.md — TowerDefense (Godot)

Gra **tower defense + strategia** (ekonomiczny lane-pusher). Cel: **fajna gra** (nie nauka). Silnik: **Godot 4.7 + GDScript**. Cel wysyłki: **Android**. Historia decyzji: [DECISIONS.md](DECISIONS.md) (D15–D29; D15–D16 zastępują ustalenia z ery MonoGame). Budowa kodu: [ARCHITECTURE.md](ARCHITECTURE.md).

## Struktura
- `scripts/cfg.gd` (`Cfg`) — balans i konfiguracja (jednostki, budynki, umiejętności, fale). Strojenie = zmiana liczb tutaj.
- `scripts/levels.gd` (`Levels`) — mapy jako dane (ścieżki, złoża, sloty). Nowa mapa = nowy wpis + pełny bot_test.
- `scripts/races.gd` (`Races`) — rasy wspólne z innymi grami tego świata (id i kolory jak tam). Na razie tożsamość (nazwa, kolor, hasło, przeciwnik), bez statystyk; grywalne `playable`, reszta „Wkrótce".
- `scripts/progress.gd`, `scripts/settings.gd` — zapis w `user://`; testy podmieniają `path`, żeby nie ruszać danych gracza.
- `scripts/sim.gd` (`Sim`) — logika gry, **bez węzłów i rysowania**. Nowa mechanika trafia tu, z testem. Dowódcą wroga (Trudny) steruje `EnemyCommander`, umiejętności obu stron rzuca `AbilityRules` (reguły po typie efektu — nowy typ efektu = nowa reguła tam). AI bez losowania i bez własnego stanu gry — to warunek lockstepu w multiplayerze. Zna też rzekę i mosty (`river`, `bridges`) oraz trasę po mapie dla dowódcy (`path_to`, A* omijający wodę).
- `scripts/main.gd` (`Main`) — widok: przebieg gry, pętla sima, efekty, samouczek, kamera. Części widoku: `world_view.gd` (`WorldView`, render świata), `hud.gd` (`Hud`, HUD/menu/nakładki z Control w kodzie), `controls.gd` (`Controls`, input i dowódca). Nie wkładaj tu reguł gry.
- `scripts/sfx.gd` (`Sfx`) — dźwięki syntezowane.
- `scripts/art.gd` (`Art`) — sprite'y z atlasu (`Art.draw` przez `Painter`) i kafle terenu. Źródła: `art/svg/*.svg` (D30), część generuje `tools/svg_gen/*.py`.

## Uruchamianie i testy
Godot z wingeta (nie ma go w PATH):
`C:\Users\lucci\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- gra: `--path .`
- import (po dodaniu `class_name`/plików): `--headless --import --path .`
- testy Sim + boty: `--headless --path . --script res://tests/bot_test.gd` (kod wyjścia 1 = błąd; ~8 min — z macierzą dowódców R11 na Normalnym; Łatwy i Trudny przez `--balance --commander`)
- same mechaniki (~20 s — głównie testy limitów populacji): `... bot_test.gd -- --mechanics`
- same mecze botów (strojenie): `--headless --path . --script res://tests/bot_test.gd -- --balance` (`--commander sapper` = bot gra dowódcą według R9; pełny bot_test puszcza macierz R11: każdy grywalny dowódca na Normalnym)
- grafika po zmianie SVG: `--headless --path . --script res://tools/bake_art.gd`, potem **koniecznie** `--headless --import --path .` (inaczej gra czyta stary atlas i sprite'y są przesunięte/niewidoczne)
- podgląd sprite'ów: `--headless --path . --script res://tools/art_sheet.gd -- <plik.png> [prefiks...] [--scale 2]`; zrzuty prawdziwej sceny (okno, nie headless): `--path . -- --bench res://tests/screenshot.gd --out <folder> [--race hyena --rival gibbon --map N]`
- ikona aplikacji po zmianie `tools/svg_gen/icon.py`: `python tools/svg_gen/icon.py`, potem `--headless --path . --script res://tools/make_icon.gd` (PNG w `art/icon/`: projekt + ikona adaptacyjna Androida)
- smoke widoku: `--headless --path . --fixed-fps 60 --script res://tests/ui_smoke_test.gd` (szukaj `SCRIPT ERROR`)
- wydajność późnej gry: `--headless --path . -- --bench res://tests/perf_test.gd --map 2 --minutes 10` (bez `--fixed-fps` — mierzy prawdziwy czas klatki; pusta scena headless to ~7 ms, to narzut silnika)
- benchmarki (`perf_test`, `render_probe`) to węzły uruchamiane przez grę parametrem `-- --bench <skrypt>` — eksportowany Godot ignoruje `--script`
- w grze: F3 = licznik FPS i czasów (sim / rysowanie / HUD); włączony licznik co 5 s trafia też do logu (`[perf]`)

Android (`tools/android.ps1`, PowerShell): eksport APK (release, podpis kluczem debug) → `adb install` → start gry.
`-NoInstall` sam eksport do `export/`, `-Log` log gry z telefonu, `-Bench` odpala `tests/perf_test.gd` NA TELEFONIE (wynik w logu; `-BenchScript res://tests/render_probe.gd` = koszt warstw renderu), `-DebugBuild` szablon debug. Seria wszystkich dowódców na telefonie: `-Bench -BenchArgs '--series','all','--minutes','4','--stress' -BenchTimeout 60` (~40 min, ekran telefonu musi być cały czas włączony; na końcu tabela `[seria]` w logu).
Szablony eksportu: tylko pliki Androida w `%APPDATA%\Godot\export_templates\4.7.2.stable\`. SDK: `C:\Program Files (x86)\Android\android-sdk`, JDK 21: `C:\Program Files\Android\openjdk\jdk-21.0.8` (oba z Visual Studio).
Uwaga: powłoka Bash w Claude Code jest w piaskownicy — zapisy poza projektem (np. `%APPDATA%`) rób przez PowerShell.

Po zmianie balansu odpal `-- --balance` i porównaj tabelę wyników. Pełny bot_test porównuje mecze botów (gra bez dowódcy) z `tests/bot_baseline.txt` — różnica = błąd; wzorzec nadpisuje się tylko świadomie: `bot_test.gd -- --write-baseline`. Po zmianie mapy (`Levels`) odpal pełny bot_test — sprawdza, czy nic nie ląduje na ścieżce, a pętle ścieżki nie nachodzą na siebie.
Wydajność mierz na TRWAJĄCEJ partii (`sim.result == 0`) — skończona partia nie liczy kroków i daje fałszywie niskie czasy.
Nie odpalaj dwóch `bot_test` naraz (np. na dwóch kopiach repo) — dzielą `user://test_progress.cfg` i testy rekordów się wysypią.
Smoke test wstrzykuje zdarzenia przez `root.push_input(e, true)` — okno headless ma 64×64, bez `true` pozycje się rozjeżdżają.

## Konwencje
- Statyczne typy w GDScript (`var x: float`, jawny typ gdy RHS to Variant).
- Współrzędne: ekran wirtualny o wysokości 720, szerokość wg proporcji ekranu (stretch `canvas_items`/`expand` → `view_size`: 1280 przy 16:9, ~1600 na telefonie 20:9), świat 1600×900 pod `Camera2D`; ekran↔świat przez `to_world`/`to_screen`. Dotyk emulowany jako mysz + gesty dwoma palcami.
- Grafika (D30): SVG z wypalonym brudem + ruch z kodu. Rzut 3/4, postać patrzy w prawo, stopy w `data-anchor`; kolor drużyny tylko przez magentę `#RR00RR`; kontur `#1a120c`, światło z lewej-góry. Każdy dowódca jest albo sci-fi, albo fantasy (podział w D30) — trzymaj się go przy nowych postaciach. Nowa jednostka/rasa = SVG (najlepiej przez `tools/svg_gen`, części rasy są tam wspólne) + bake + import; brakujący sprite spada do starego rysunku z kształtów.
- Umiejętności to dane: `Cfg.ABILITIES` z typem efektu (`kind`: strike / summon_units / global), `Sim` obsługuje typy, każdy dla obu drużyn (`use_ability(id, at, team)`). Nowa umiejętność istniejącego typu = wpis w `Cfg`; nowy typ = kod w `Sim` + test dla team 0 i team 1.
- Rozkazy gracza (widok, boty, AI) idą komendą `Sim.apply({player, type, …})` — w widoku przez `Main.send`; nie wołaj `sim.build/upgrade/use_ability…` z widoku (warunek gry sieciowej). Nowy rozkaz = nowy typ w `Sim.apply` + przypadek w `_test_commands`.
- Rysowanie świata w `world_view.gd` idzie przez `pen` (`Painter`: `pen.circle(...)` zamiast `draw_circle(...)`, te same argumenty) — cały świat to jedno wywołanie rysowania. Gołe `draw_circle`/`draw_arc`/`draw_colored_polygon` w pętli po jednostkach = setki wywołań i spadek FPS na telefonie (Mali). HUD (Control) i minimapa rysują normalnie.
- Zakres pod dyscypliną — najpierw zabawa rdzenia, potem treść.
- Commity robi użytkownik — nie commituj sam.
