# Architecture — TowerDefense (Godot)

## Pliki

```
project.godot            ekran wirtualny 1280×720, stretch canvas_items/expand, GL Compatibility, dotyk → mysz,
                         Android: poziomo (obie strony), „Wstecz” obsługuje gra (quit_on_go_back = false)
export_presets.cfg       preset „Android”: APK bez Gradle, arm64-v8a, pl.towerdefense.game (bez haseł — klucz z env)
main.tscn                jeden węzeł Node2D ze skryptem scripts/main.gd
scripts/cfg.gd           Cfg      — balans: jednostki, budynki, umiejętności, fale, trudności, stałe wspólne dla map
scripts/levels.gd        Levels   — mapy jako dane (ścieżki, bazy, rzeka, złoża, sloty wież wroga, strefa budowy)
scripts/races.gd         Races    — 12 ras świata (id, nazwa, kolor, hasło, grywalna?) + kto z kim walczy
scripts/sim.gd           Sim      — logika gry: stan, rozkazy gracza, step(dt), zdarzenia. Zero węzłów i rysowania.
scripts/main.gd          widok: kamera, render (_draw + warstwa terenu), HUD, minimapa, menu, nakładki, samouczek
scripts/painter.gd       Painter  — kształty (koła, łuki, linie, wielokąty) sklejane w jedno wywołanie rysowania
scripts/sfx.gd           Sfx      — efekty i muzyka syntezowane w kodzie (bez plików audio), szyny SFX/Music
scripts/progress.gd      Progress — rekordy i gwiazdki per mapa × trudność, stan samouczka (user://progress.cfg)
scripts/settings.gd      Settings — głośności, skala interfejsu (user://settings.cfg)
tests/bot_test.gd        testy mechanik + geometrii map + mecze botów (`-- --mechanics`, `-- --balance`)
tests/ui_smoke_test.gd   odpala prawdziwą scenę, steruje nią zdarzeniami wejścia, gra do końca partii
tests/perf_test.gd       benchmark późnej gry: prawdziwa scena + bot, czas rzeczywisty, czasy klatki i faz
                         (w APK — `tools/android.ps1 -Bench` odpala go na telefonie)
tests/render_probe.gd    koszt warstw renderu (teren / świat / HUD / rozdzielczość) — wywołania rysowania, FPS
                         (benchmarki to węzły uruchamiane przez grę: `-- --bench <skrypt>`)
tools/android.ps1        eksport APK + adb install + start / log / benchmark na telefonie
```

## Zasada podziału

**Sim nie wie nic o renderze.** `main.gd` czyta stan Sim i wywołuje jej rozkazy
(`build`, `build_extractor`, `upgrade`, `sell`, `set_lane`, `set_stance`, `use_ability`).
Sim komunikuje „co się stało" przez listę `events` (strzał, trafienie, śmierć, złoto, fala,
salwa, atak na budynek…), którą widok opróżnia co klatkę i zamienia na cząsteczki, napisy,
drgania ekranu i dźwięk. Dzięki temu całą grę da się puścić headless (boty, testy).

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
- Umiejętności: `ability_cd` (cooldowny), `strikes` (trwające salwy Deszczu strzał).

## Krok symulacji (`Sim.step`)

```
dochód → umiejętności (cooldowny, salwy)
       → fale wroga (ścieżki ważone słabością obrony, każda ścieżka spawnuje równolegle,
                     dopływ orków, budowa wież co 4 fale, limity populacji,
                     od fali 40 „furia": HP i obrażenia nowych wrogów rosną)
       → siatka przestrzenna
       → budynki (regeneracja, wieże/działka strzelają, produkcja na swoją ścieżkę)
       → jednostki (decyzja niżej) → pociski (lot, trafienie, obszar, spowolnienie)
       → sprzątanie martwych → warunek końca
```

Decyzja jednostki naziemnej (pierwsza pasująca reguła wygrywa):

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

## Widok (main.gd)

Stany ekranu + nakładki (`overlay`: ustawienia, jak grać) — widoczność warstw HUD
wynika co klatkę ze stanu, nie jest przełączana ręcznie:

```
MENU ──(rasa + mapa + trudność)──▶ PLAY ⇄ PAUSED (Esc/Wstecz/P/II, auto-pauza w tle na Androidzie)
                             │ sim.result != 0
                             ▼
                           OVER ──▶ PLAY (Jeszcze raz) / MENU (też Esc/Wstecz)
```

Esc i androidowe „Wstecz” idą przez `_back()`: nakładka → tryb/zaznaczenie → pauza ⇄ gra →
koniec → menu; „Wstecz” w menu głównym zamyka grę.

Widok: stretch `expand` — wysokość zawsze 720 px wirtualnych, szerokość wg proporcji ekranu
(`view_size`: 1280 przy 16:9, ~1600 na telefonie 20:9 — bez czarnych pasów). Zmiana rozmiaru
okna (`size_changed`) przelicza kamerę i przebudowuje HUD.

Kamera: `Camera2D`, domyślnie cała mapa (zoom 0,8), zoom do 2×. Mapowanie ekran↔świat
liczone wprost (`_to_world` / `_to_screen`). HUD żyje w `CanvasLayer` skalowanym przez
`Settings.ui_scale()` (na telefonie domyślnie ×1,3); układ liczony od `screen = view_size / skala`,
zmiana skali przebudowuje HUD.

```
wciśnij ─┬─ tryb budowy/umiejętności ──▶ podgląd pod palcem ── puść ──▶ buduj / użyj
         └─ inaczej ──┬─ ruch > TAP_SLOP ──▶ przesuwanie mapy
                      └─ puść w miejscu ───▶ klik (złoże / zaznaczenie)
dwa palce = szczypanie + przesuwanie · kółko = zoom · WASD/strzałki = przesuwanie
```

Samouczek: lista kroków w `TUTORIAL`, każdy kończy się warunkiem sprawdzanym co klatkę
(postawiony wydobywacz, produkcja, wieża, zaznaczenie, ruch kamery, użyta umiejętność).

## Kierunek dalszego rozbicia (gdy przyjdzie czas)

- Konfiguracja jednostek/budynków jako `Resource` (.tres) — edytowalne w edytorze.
- Mapy z `Levels.ALL` jako pliki Resource — dane już są w tym kształcie.
- Render jednostek przez MultiMesh, jeśli telefon nie wyrobi przy dużych bitwach.
- HUD jako osobna scena Control, gdy urośnie.
