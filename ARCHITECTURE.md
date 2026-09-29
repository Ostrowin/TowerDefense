# Architecture — TowerDefense (Godot)

## Pliki

```
project.godot            ekran wirtualny 1280×720, stretch canvas_items/expand, GL Compatibility, dotyk → mysz,
                         Android: poziomo (obie strony), „Wstecz” obsługuje gra (quit_on_go_back = false)
export_presets.cfg       preset „Android”: APK bez Gradle, arm64-v8a, pl.towerdefense.game (bez haseł — klucz z env)
main.tscn                jeden węzeł Node2D ze skryptem scripts/main.gd
scripts/cfg.gd           Cfg      — balans: jednostki, budynki (też tymczasowe), umiejętności, dowódcy, umiejętności ras,
                         fale, trudności, stałe wspólne dla map
scripts/levels.gd        Levels   — mapy jako dane (ścieżki, bazy, rzeka, złoża, sloty wież wroga, strefa budowy)
scripts/races.gd         Races    — 12 ras świata (id, nazwa, kolor, hasło, grywalna?) + losowanie przeciwnika,
                         dowódcy rasy (`commanders`) i jej umiejętność (`racial`)
scripts/sim.gd           Sim      — logika gry: stan, rozkazy gracza, step(dt), zdarzenia. Zero węzłów i rysowania.
scripts/enemy_commander.gd EnemyCommander — AI dowódcy wroga (Trudny): gdzie stoi, co rzuca; wołane z Sim.step
scripts/ability_rules.gd AbilityRules — kiedy i gdzie rzucić umiejętność (po typie efektu, dla obu drużyn);
                         używa go AI wroga i bot gracza w testach
scripts/main.gd          Main     — scena: przebieg gry (stany), pętla sima, zdarzenia → efekty i dźwięk, samouczek, kamera
scripts/world_view.gd    WorldView — render świata: teren (warstwa `terrain`), podświetlenia ścieżek, `draw()` przez `pen`
scripts/hud.gd           Hud      — HUD, minimapa, baner, menu i nakładki (Control budowany w kodzie)
scripts/controls.gd      Controls — input (mysz, dotyk, gesty, klawisze), klik w mapę, dowódca, budowa, umiejętności
scripts/painter.gd       Painter  — kształty (koła, łuki, linie, wielokąty, elipsy) i sprite'y z atlasu sklejane
                         w jedno wywołanie rysowania (z teksturą: UV każdego wierzchołka)
scripts/art.gd           Art      — atlas sprite'ów i kafle terenu: ładowanie (mipmapy), `Art.draw` (stopy, lustro,
                         obrót, rozciągnięcie, rozjaśnienie, nakładka drużyny)
art/svg/*.svg            źródła grafiki (D30) — `.gdignore`, gra ich nie widzi; część generuje tools/svg_gen
art/atlas.png            wypalony atlas + art/atlas_meta.gd (prostokąty, stopy, skala) — generowane, nie edytuj
art/ground|dirt|water.png  bezszwowe kafle terenu (też z wypalania)
scripts/sfx.gd           Sfx      — efekty i muzyka syntezowane w kodzie (bez plików audio), szyny SFX/Music
scripts/progress.gd      Progress — rekordy i gwiazdki per mapa × trudność, stan samouczka (user://progress.cfg)
scripts/settings.gd      Settings — głośności, skala interfejsu (user://settings.cfg)
tests/bot_test.gd        testy mechanik + geometrii map + mecze botów (`-- --mechanics`, `-- --balance [--commander id]`);
                         bot gra też dowódcą (R9); tabela meczów bez dowódcy porównywana z tests/bot_baseline.txt
tests/ui_smoke_test.gd   odpala prawdziwą scenę, steruje nią zdarzeniami wejścia, gra do końca partii
tests/perf_test.gd       benchmark późnej gry: prawdziwa scena + bot, czas rzeczywisty, czasy klatki i faz
                         (`--commander id --stress` — dowódca rzuca każdą gotową umiejętność)
                         (w APK — `tools/android.ps1 -Bench` odpala go na telefonie)
tests/render_probe.gd    koszt warstw renderu (teren / świat / HUD / rozdzielczość) — wywołania rysowania, FPS
                         (benchmarki to węzły uruchamiane przez grę: `-- --bench <skrypt>`)
tests/screenshot.gd      zrzuty prawdziwej sceny (cała mapa, zbliżenia) do oceny grafiki — okno, nie headless
tools/android.ps1        eksport APK + adb install + start / log / benchmark na telefonie
tools/bake_art.gd        wypalanie: art/svg → atlas z brudem i nakładką drużyny + kafle terenu
tools/art_sheet.gd       arkusz podglądu sprite'ów z atlasu (obie drużyny)
tools/make_icon.gd       ikona aplikacji: art/icon/*.svg (z tools/svg_gen/icon.py) → PNG dla projektu i Androida
tools/svg_gen/*.py       generator SVG ras, budynków, dekoracji i dowódców (wspólne części = spójne rasy)
```

## Zasada podziału

**Sim nie wie nic o renderze.** `main.gd` czyta stan Sim i wywołuje jej rozkazy
(`build`, `build_extractor`, `upgrade`, `sell`, `set_lane`, `set_stance`, `use_ability`).
Sim komunikuje „co się stało" przez listę `events` (strzał, trafienie, śmierć, złoto, fala,
salwa, atak na budynek…), którą widok opróżnia co klatkę i zamienia na cząsteczki, napisy,
drgania ekranu i dźwięk. Dzięki temu całą grę da się puścić headless (boty, testy).

**Gracze (multiplayer, docs/designs/multiplayer.md).** `Sim.players` — `Sim.Player` ma drużynę, złoto,
dowódcę, pasek umiejętności (odnowienia, ulepszenia z awansu), oferty awansu, postawę i łupy. Jednostki
i budynki mają `owner` (indeks gracza). Indeksy: 0 = gracz drużyny 0, 1 = strona drużyny 1 (fale i dowódca
wroga, w PvP drugi gracz), 2+ = kolejni gracze kooperacji (`add_player`). Rozkazy i zapytania o umiejętności
biorą numer gracza (`use_ability(id, at, player)`, `build(kind, cell, player)`…); efekty celują w jego drużynę.
Widok pokazuje gracza `Main.me`. Gra solo to gracze 0 i 1 — tabela botów bez zmian.

**Komendy.** Rozkazy wchodzą do Sim tylko przez `Sim.apply(cmd)` — słownik prostych wartości
`{player, type, …}` (budynek wskazany pozycją `at`), więc da się go wysłać siecią. Widok wysyła je przez
`Main.send` (dopisuje `player = me`), boty testów i AI dowódcy wroga (`AbilityRules`, `EnemyCommander`) też
przez `apply`. Metody rozkazów (`build`, `upgrade`, `use_ability`…) zostają implementacją komend; testy mechanik
wołają je wprost. Komenda z błędnym graczem, brakującym polem czy złym typem = false bez zmian stanu.

**Determinizm.** `Sim.checksum()` — suma stanu z jawnej listy pól czytanych przez symulację (liczby
zaokrąglone do 0,01; pola tylko dla renderu jak `face`/`flash`/`aim` poza nią). W lockstepie telefony porównują
ją co 30 kroków. Nowe pole stanu w Sim = dopisz je do `checksum()`. `bot_test` gra całą partię na dwóch Sim
z tym samym strumieniem komend i porównuje sumy (`_test_checksum`). `Main.lossless` = pętla nie porzuca
zaległych kroków (gra sieciowa); w solo porzucanie zostaje.

**Sieć (`NetSession`, scripts/net_session.gd).** ENet w Wi-Fi, gwiazda: host zbiera paczki komend wszystkich
graczy na turę N i rozsyła je jako „turę N”; krok N rusza dopiero, gdy tura jest znana (czeka, nie porzuca).
Komenda idzie na turę bieżący krok + `DELAY` (3). Host wpisuje numer gracza z połączenia (R5); host = gracz 0,
goście 2, 3… Co 30 kroków suma kontrolna — różna = koniec „Rozjazd gry (krok N)”; zerwanie = koniec. W `Main`:
`net != null` → `send` idzie przez sesję, a pętla kroków przez `net.try_step()`. Odkrywanie gier:
`NetSession.Discovery` (rozgłaszanie UDP). Test: `tests/net_test.gd`.

**Lobby (`Lobby`, scripts/lobby.gd).** Menu „Ze znajomym”: host tworzy grę (ogłasza ją w Wi-Fi), gość wybiera
ją z listy albo wpisuje IP; każdy wybiera rasę i dowódcę na tej samej stronie co w solo (gość wysyła wybór
pakietem „pick”). Host wybiera mapę i trudność — `Lobby.start` składa ustawienia (ziarno, mapa, dowódcy, rasa
wroga), `Main.start_net` buduje z nich ten sam Sim u obu. W sieci: tylko Bitwa, prędkość x1, bez rekordów solo,
pauza wspólna (pakiet poza turami), zerwanie = ekran końca z komunikatem. Widok sprawdza złoto i cel przed
wysłaniem rozkazu (wynik z Sim przychodzi po DELAY krokach); budynki i dowódca partnera mają błękitny znacznik.
Test od menu do końca: `tests/net_ui_test.gd`.

```
 input ──▶ main.gd ──(rozkazy)──▶ Sim.step(1/30) ──▶ stan (units, buildings, shots, gold…)
              ▲                        │
              │                        └──▶ events ──▶ main.gd: efekty + Sfx
              └──────────── _draw() czyta stan ◀────────┘
```

Pętla ma **stały krok 1/30 s** z akumulatorem (x1/x2/x3 = więcej kroków na klatkę).
Render interpoluje pozycje jednostek i pocisków między krokami (`prev_pos` → `pos`,
`render_alpha`). Kroki w klatce mają **budżet 10 ms** — po przekroczeniu zaległości
przepadają (gra chwilowo zwalnia zamiast wpaść w spiralę śmierci).

## Wydajność

Najgorszy przypadek jest ograniczony **limitami populacji** (`Cfg.MAX_ARMY` 200,
`Cfg.MAX_ENEMIES` 150, `MAX_SPAWN_QUEUE` 40) — bez nich w długiej partii jednostek
przybywało bez końca (fala 50: ~2800) i to było przyczyną „wieszania się" pod koniec gry.

- Sim: cele szukane przez siatkę przestrzenną (`_grid`/`_bgrid`, komórki 150 px,
  przebudowa raz na krok) zamiast O(n²); statystyki jednostki skopiowane do pól przy
  spawnie; `slot_at` to jedno `sample_baked_with_rotation`; jednostka na ścieżce
  (`on_path`) nie sprawdza co krok, czy z niej zeszła. Profil faz: `sim.profile = true`.
- Render: **wywołania rysowania to główny koszt na telefonie** (Mali-G57: ~600 wywołań/klatkę
  = 35–45 FPS nawet w pustej grze). Każde `draw_circle`/`draw_arc`/`draw_colored_polygon` to
  osobne wywołanie, więc świat rysuje `Painter` (`pen`): wszystkie kształty w jednej liście
  trójkątów (wierzchołki kół liczy C++ przez `Transform2D * kształt`), napisy na wierzchu —
  świat = 1 wywołanie + napisy. Koła terenu (trawa, drzewa) to dwa gotowe `Painter` liczone
  przy zmianie mapy. Pomiar warstw: `tests/render_probe.gd`.
- Render (dalej): statyczny teren na osobnej warstwie (`terrain`) rysowanej przy zmianie mapy;
  podświetlenia ścieżek to węzły `Line2D` (geometria raz, co klatkę tylko widoczność);
  wolne pola budowy liczone po zmianie `sim.layout_version`; obiekty poza kadrem
  pomijane; powyżej `LOD_UNITS` jednostek (widok całej mapy) rysunek uproszczony;
  limity iskier, napisów i efektów trafień na klatkę.
- Pomiar: `tests/perf_test.gd` (prawdziwa scena, bot, Trudny, x3, czas rzeczywisty)
  i licznik F3 w grze. Pusta scena headless to ~7 ms/klatkę — narzut silnika, nie gry.
- Telefon (realme 8i, Helio G96, Mali-G57, 2412×1080), `perf_test` Serpentyna/Trudny/x3/8 min:
  mediana 17,6 ms, p95 22,9 ms; przy ~150–240 jednostkach ~20 ms (sim ~8 ms przy 2 krokach
  na klatkę, rysowanie ~7 ms). Pomiar: `tools/android.ps1 -Bench` (bot, prawdziwy GPU) albo
  licznik FPS z ustawień — włączony wypisuje co 5 s linię `[perf]` do logu (`-Log`).
- Pułapka Androida: gdy wątek gry czeka na GPU, system uznaje go za mało zajęty i zrzuca na
  mały rdzeń z niskim taktowaniem — wtedy zwalnia też sim (×3–4). Mniej wywołań rysowania
  leczy oba objawy naraz.

## Mapy (`Levels`) i ścieżki

Świat ma 1600×900. Każda mapa ma 3 ścieżki (Północ/Środek/Południe liczone od strony
gracza) zapisane jako punkty kontrolne i wygładzane w `Curve2D` (`Cfg.smooth_curve`).
`Sim.Lane` opakowuje krzywą: `point_at(s)`, `normal_at(s)`, `slot_at(s, bok)`,
`offset_of(p)`, `distance_to(p)`.

```
   s = 0 (baza gracza) ─────────── krzywa ───────────▶ s = length (baza wroga)
   gracz: s rośnie                                     wróg: s maleje
   pozycja jednostki = slot_at(s, lane_offset) (szyk w poprzek ścieżki)
```

Wszystko, co zależy od kształtu map, jest **wyliczane** z danych: sloty wież wroga
(ścieżka, odległość od końca, bok), strefa budowy (pole ≥ `PATH_CLEARANCE` od każdej
ścieżki), linie zbiórki (`rally_s`), mosty (odcinki ścieżek nad rzeką), plan bota
(kotwice przy ścieżkach). `bot_test` sprawdza dla każdej mapy, czy złoża i sloty nie
lądują na ścieżkach, a pętle jednej ścieżki nie nachodzą na siebie.

Po walce jednostka wraca na ścieżkę w najbliższym punkcie, ale szukanym tylko ±150 px
wzdłuż ścieżki (`REJOIN_WINDOW`) — na Serpentynie sąsiednia pętla bywa bliżej niż
właściwe miejsce.

## Model danych (Sim)

- Klasy wewnętrzne, zwykłe obiekty (bez węzłów): `Sim.Lane`, `Sim.Unit`, `Sim.Building`, `Sim.Shot`.
- Drużyny: `0` = gracz (lewo), `1` = wróg (prawo). Działka baz to ukryte budynki `basegun`.
- Jednostka: `lane`, `s`, `lane_offset`, `on_path`; latające (`flying`) lecą prosto do bazy.
- Obrażenia mają rodzaj (`arrow`/`melee`/`cannonball`/`rock`/`frost`): pancerz blokuje część
  strzał, w latających trafia tylko `Cfg.ANTI_AIR`, mróz nakłada spowolnienie.
- Budynek: `level` (1–3), `invested` (zwrot), `lane` (produkcja), `last_hit` (regeneracja).
- Umiejętności: dane w `Cfg.ABILITIES` z typem efektu (`kind`) i zasięgiem rzucania od dowódcy
  (`cast_range`, 0 = bez ograniczenia); `use_ability(id, at, team)` rozdziela po typie, nie po
  nazwie, `ability_target_ok` sprawdza cel (zasięg, ląd, wolne pole, nie pod bazą wroga). Odnowienia
  per drużyna (`ability_cd[team][id]`); trwające efekty (`strikes`, `zones`, `raises`) niosą swoją
  drużynę i konfigurację — obie strony mogą rzucać naraz. 17 typów, każdy z testem dla obu drużyn:

  | typ | efekt | stan |
  |---|---|---|
  | `strike` | salwy w obszar (bez celu: wokół dowódcy), opcjonalnie `stun` | `strikes` |
  | `summon_units` | jednostki przy ścieżce (opcj. `lifetime`) | `Unit.expire` |
  | `global` | leczy budynki i bazę | — |
  | `zone` | mina (wybuch przy wejściu) albo obrażenia co sekundę (+`slow`) | `zones` |
  | `summon_building` | budowla z `Cfg.TEMP_BUILDINGS` na czas (wieżyczka, totem, odpychacz) | `Building.temporary` |
  | `buff` | wzmocnienie: promień / ścieżka / sam dowódca / cała armia (+`knockback`) | `Unit.buffs` |
  | `weaken` | wrogowie dostają więcej obrażeń | `Unit.buffs["vuln"]` |
  | `line`, `repel` | przebicie / odrzut wzdłuż linii od dowódcy | — |
  | `execute` | dobija najsilniejszego (Wódz i dowódcy odporni) | — |
  | `demolish` | ładunek w budynek wroga | — |
  | `pull`, `taunt`, `leap` | chwyt do dowódcy / prowokacja / skok dowódcy na ląd | `Unit.taunt` |
  | `raise_dead` | polegli wrogowie wstają po naszej stronie (po kroku) | `raises` |
  | `bounty_buff` | wyższe nagrody za zabicie | `bounty_mult/until` |
  | `burrow` | armia na ścieżce pod ziemią: poza siatką celów, nietykalna, wstrząs przy wynurzeniu | `Unit.burrow` |

- Dowódca (`Sim.Hero extends Unit`, `heroes[team]`): w `units` i siatce celów (wieże, pociski i obszar
  widzą go bez przeróbek), ale poza `team_count`, `army_size` i `lane_defense`. Maszyna stanów
  `idle → march` (trasa A*, ignoruje wrogów) `→ idle`; `idle ⇄ fight` (goni do `COMMANDER_LEASH`
  od punktu postoju) `→ back → idle`; `dead` (rekord zostaje w `heroes`, wraca do `units` przy
  odrodzeniu). Rozkaz: `order_hero(pos)`. Umiejętności dowódcy czekają, gdy nie żyje; rasowa działa zawsze.
- Awans (D27): `Hero.xp`/`hero_level`; `_award_xp` przy śmierci wroga i `_award_building_xp` przy zburzeniu
  (promień `HERO_XP_RADIUS`, zabicie osobiste rozpoznaje `_hero_blow` — ustawiany na czas ciosu, pocisku
  `Shot.from_hero`, rzucenia i ticków salw/stref dowódcy). Awans dokłada ofertę do `hero_offers[team]`,
  `choose_upgrade(i)` zmienia kopię konfiguracji w `ability_cfg[team]`; `ability_config(id, team)` —
  jedyne miejsce odczytu konfiguracji umiejętności w Sim i widoku.
- Wyzwanie dnia (D29): `Cfg.daily(data)` liczy zestaw z ziarna daty; `Sim.mods` (id z `Cfg.DAILY_MODS`)
  i `Sim.mod(klucz)` = iloczyn mnożników aktywnych modyfikatorów, czytany w miejscach, których dotyczą
  (dochód, koszt wież `build_cost`, dowódca, odnowienia, złoto startowe, skład i odstęp fal, HP wrogów).
- Tryb (`Sim.mode`): `battle` albo `survival` (D28) — w przetrwaniu `_damage_base` ignoruje fortecę wroga,
  a `enemy_fury` rośnie od `SURVIVAL_FURY_WAVE` o `SURVIVAL_FURY_PER_WAVE` na falę; rekord w `Progress`.
- Grywalność dowódcy wynika z danych: `Cfg.commander_ready` = Sim zna typy wszystkich jego umiejętności
  (`Cfg.IMPLEMENTED_KINDS`). `Sim.new(..., commander)`; bez dowódcy (`""`) gra jest identyczna jak
  przed dowódcami — pilnuje tego tabela wzorcowa w `bot_test` (kontrakt regresji D8).
- Rzeka i mosty: `river` (krzywa z `Levels`, null bez rzeki) i `bridges` (`{lane, s0, s1}` —
  odcinki ścieżek nad wodą). Widok rysuje z nich teren i deski mostów.
- Trasa po mapie: `path_to(a, b)` — `AStarGrid2D` (pola 20 px, woda z zapasem zablokowana,
  pasy mostów przejezdne, bez ścinania rogów), wygładzona jednym przejściem; cel na wodzie →
  najbliższy ląd. Siatka budowana leniwie przy pierwszym zapytaniu (~10 ms), trasa ~2,5 ms.

## Krok symulacji (`Sim.step`)

```
dochód → umiejętności (cooldowny, salwy) → odrodzenia dowódców
       → fale wroga (ścieżki ważone słabością obrony, każda ścieżka spawnuje równolegle,
                     dopływ orków, budowa wież co 4 fale, limity populacji,
                     od fali 40 „furia": HP i obrażenia nowych wrogów rosną)
       → siatka przestrzenna (bez jednostek pod ziemią) → strefy
       → budynki (regeneracja, wieże/działka strzelają, produkcja, budowle tymczasowe: czas życia, pulsy)
       → jednostki (decyzja niżej; dowódca — własna maszyna stanów) → pociski (lot, trafienie, obszar)
       → sprzątanie martwych → wskrzeszeni wstają → warunek końca
```

Decyzja jednostki naziemnej (pierwsza pasująca reguła wygrywa; wcześniej: znika po `expire`,
ogłuszona stoi, pod ziemią idzie naprzód ścieżką, sprowokowana za wroga uznaje dowódcę przeciwnika):

```
[oblężnicza?] budynek wroga w zasięgu        → strzelaj w budynek
              baza wroga w zasięgu            → strzelaj w bazę
jednostka wroga w zasięgu + AGGRO             → w zasięgu: bij / poza: podejdź
  (latające widzi tylko jednostka z pociskiem ANTI_AIR)
[atak] budynek wroga w zasięgu + B_AGGRO      → w zasięgu: bij / poza: podejdź
[atak] baza wroga w zasięgu                   → bij bazę
[atak] idź ścieżką  |  [obrona] stań w szyku na linii zbiórki swojej ścieżki
```

Wybór ścieżek fali: waga ścieżki = (1 + obrona / 40)⁻², gdzie obrona = siła wież gracza
sięgających ścieżki + jego jednostki na niej. Losowanie bez zwracania, z `rng` sima.

## Widok (main.gd + world_view.gd, hud.gd, controls.gd)

`Main` trzyma stan widoku (stan ekranu, `mode`, `selected`, `hero_selected`, kamera, efekty) i tworzy
trzy pomocnicze obiekty (`RefCounted` z referencją `m` do main): `view` rysuje, `hud` buduje i odświeża
interfejs, `controls` zamienia input na rozkazy Sim. Nowy element HUD → `hud.gd`, nowy gest/skrót →
`controls.gd`, nowy rysunek w świecie → `world_view.gd` (przez `pen`).

Stany ekranu + nakładki (`overlay`: ustawienia, jak grać) — widoczność warstw HUD
wynika co klatkę ze stanu, nie jest przełączana ręcznie:

```
MENU ──(rasa + dowódca + tryb + mapa + trudność)──▶ PLAY ⇄ PAUSED (Esc/Wstecz/P/II, auto-pauza w tle na Androidzie)
                             │ sim.result != 0
                             ▼
                           OVER ──▶ PLAY (Jeszcze raz) / MENU (też Esc/Wstecz)
```

Esc i androidowe „Wstecz” idą przez `back()`: nakładka → tryb/zaznaczenie → pauza ⇄ gra →
koniec → menu; „Wstecz” w menu głównym zamyka grę.

Widok: stretch `expand` — wysokość zawsze 720 px wirtualnych, szerokość wg proporcji ekranu
(`view_size`: 1280 przy 16:9, ~1600 na telefonie 20:9 — bez czarnych pasów). Zmiana rozmiaru
okna (`size_changed`) przelicza kamerę i przebudowuje HUD.

Kamera: `Camera2D`, domyślnie cała mapa (zoom 0,8), zoom do 2×. Mapowanie ekran↔świat
liczone wprost (`to_world` / `to_screen`). HUD żyje w `CanvasLayer` skalowanym przez
`Settings.ui_scale()` (na telefonie domyślnie ×1,3); układ liczony od `screen = view_size / skala`,
zmiana skali przebudowuje HUD.

```
wciśnij ─┬─ tryb budowy/umiejętności ──▶ podgląd pod palcem ── puść ──▶ buduj / użyj
         └─ inaczej ──┬─ ruch > TAP_SLOP ──▶ przesuwanie mapy
                      └─ puść w miejscu ───▶ klik (złoże / zaznaczenie)
dwa palce = szczypanie + przesuwanie · kółko = zoom · WASD/strzałki = przesuwanie
```

Dowódca w widoku (R6/D6): stuknięcie w dowódcę (28 px ekranu) albo portret nad paskiem (H) zaznacza
go; przy zaznaczonym stuknięcie w pusty teren = `order_hero` (zostaje zaznaczony), w budynek,
złoże albo wieżę wroga = zwykła akcja i odznaczenie; Esc/Wstecz odznacza. Pasek: 6 budynków +
Q/E/R (dowódca) + T (rasa); celowanie pokazuje zasięg rzucania wokół dowódcy, odmowa podaje powód.
Menu: po rasie karty jej dowódców (niegrywalni — „Wkrótce”).

Samouczek: lista kroków w `TUTORIAL`, każdy kończy się warunkiem sprawdzanym co klatkę
(postawiony wydobywacz, produkcja, wieża, zaznaczenie, ruch kamery, rozkaz dla dowódcy, użyta umiejętność).

## Grafika (D30)

```
art/svg/*.svg ──tools/bake_art.gd──▶ art/atlas.png + art/atlas_meta.gd ──--import──▶ gra (Art.load_all)
   (python tools/svg_gen/*.py)        art/ground|dirt|water.png
```

- **Wypalanie** (`Image.load_svg_from_string` w Godocie): SVG → obraz w skali `data-scale`, brud (plamy szumu,
  błoto od dołu, rysy na metalu, odpryski), przycięcie, pakowanie półkowe do atlasu 2048 px (odstępy 6 px,
  `fix_alpha_edges` pod mipmapy), biały blok 16×16 na kształty bez tekstury.
- **Kolor drużyny**: wypełnienia `#RR00RR` (magenta, RR = jasność). Wypalanie renderuje SVG trzy razy (magenta →
  czarny / biały / szary odcień) i z różnic robi szarą nakładkę: pokrycie × odcień. Gra rysuje nakładkę drugim
  czworokątem w kolorze drużyny — ten sam atlas, to samo wywołanie.
- **Atrybuty SVG**: `data-anchor` (stopy — tam trafia pozycja), `data-world` (px świata na jednostkę SVG),
  `data-scale` (rozdzielczość wypalenia), `data-grime` (siła brudu).
- **Nazwy**: jednostki `<rasa>_<soldier|archer|shield|brute|siege|flyer>` (`UNIT_ART` mapuje na nie też fale
  wroga), dowódcy `cmd_<id>`, budynki `b_<rodzaj>` + obrotowa lufa `b_<rodzaj>_gun` (`GUN_MOUNT`), teren `deco_*`,
  złoże `deposit`. Brak sprite'a = stary rysunek z kształtów (nowa treść może dochodzić stopniowo).
- **Ruch z kodu** (`_draw_unit_sprite`): zwrot z kierunku ruchu (`Unit.face`), podskok/kołysanie/sprężystość
  chodu, oddech w miejscu, wypad przy ciosie wręcz i odrzut przy strzale (z `cd_left`), unoszenie latających,
  błysk trafienia (kolor > 1). Budynki sortowane po y przy zmianie układu.
- **Teren**: kafel trawy powtarzany po całej mapie, ścieżki i rzeka jako pasy trójkątów z UV w przestrzeni
  świata (`_strip`), podświetlenia ścieżek to ten sam pas zabarwiony; dekoracje ze sprite'ów w dwóch
  `Painter` liczonych przy zmianie mapy.

## Kierunek dalszego rozbicia (gdy przyjdzie czas)

- Konfiguracja jednostek/budynków jako `Resource` (.tres) — edytowalne w edytorze.
- Mapy z `Levels.ALL` jako pliki Resource — dane już są w tym kształcie.
- Render jednostek przez MultiMesh, jeśli telefon nie wyrobi przy dużych bitwach.
- HUD jako osobna scena Control, gdy urośnie.
