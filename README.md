# TowerDefense

Ekonomiczny lane-pusher: **tower defense + strategia**. Rozbudowujesz ekonomię, stawiasz budynki produkujące armię, która **sama** maszeruje jedną z trzech krętych ścieżek do fortecy wroga, i bronisz się wieżami. Serce zabawy = **ekonomia, build-order i wybór ścieżki natarcia**.

> Cel: **fajna gra**. Silnik: **Godot 4.7 + GDScript**. Cel wysyłki: **Android**.

## Status

**Grywalny prototyp**: 3 mapy, 3 poziomy trudności, 4 grywalne rasy z 12 dowódcami, rekordy i gwiazdki, 6 budynków bojowych i produkcyjnych, 7 rodzajów wrogów, samouczek, ustawienia, muzyka i efekty syntezowane w kodzie. Grafika z prymitywów. Balans wstępnie strojony botami.

## Core loop

```
złoto (pasywne + wydobywacze; sporne złoża przy ścieżkach wroga dają więcej)
   →  koszary / strzelnice / warsztaty — każdy wysyła jednostki wybraną ścieżką
   →  wieże, armaty i mróz bronią ścieżek, którymi nadciągają zapowiedziane fale
   →  Twój dowódca walczy tam, gdzie go poślesz, i rzuca umiejętności (3 swoje + 1 rasy)
   →  katapulty burzą wieże wroga, armia szturmuje fortecę
   →  zniszcz fortecę wroga = WYGRANA / wróg zniszczy Twoją bazę = PRZEGRANA
```

## Rasy

Świat wspólny z innymi grami: 12 ras (niedźwiedzie, wilki, lisy, zające, krety, jeże, nietoperze, gibony,
szczury, dziki, wydry, hieny). Grywalne: **krety, gibony, hieny i dziki** — wybierasz jedną w menu, przeciwnik
jest losowany spośród pozostałych, reszta ras czeka jako „Wkrótce”. Rasy dzielą budynki i jednostki — różni je
**dowódca** (3 do wyboru na rasę) i **umiejętność rasy** ([projekt](docs/designs/dowodcy-ras.md), [katalog](docs/designs/dowodcy-katalog.md)).

| Rasa | Umiejętność rasy | Dowódcy |
|---|---|---|
| Krety | **Podkop** — armia na ścieżce pod ziemią, nietykalna, wynurza się ze wstrząsem | Saper (miny, wiertło, ładunek) · Snajper (dobicie, przebicie, ostrzał) · Magma (pocisk, lawa, wulkan) |
| Gibony | **Pieśń** — cała armia szybsza i mocniejsza | Żelazny Chwyt (chwyt, ryk, uderzenie) · Niszczyciel (taran, fala uderzeniowa, zamach) · Bojowy Rytm (werble, marsz, grzmot) |
| Hieny | **Padlina** — więcej złota za zabicia | Nekromanta (wskrzeszenie, zew grobu, klątwa) · Padlinożerca (uczta, dobicie, rozszarpanie) · Rechot (skok, rechot, szał) |
| Dziki | **Szarża** — ścieżka szybsza, pierwszy cios odrzuca | Inżynier Totemów (3 totemy) · Stratowanie (szarża, tabun, twarda skóra) · Kły (rozpruwacz, kolce, furia) |

Dowódca to jedyna postać, którą sterujesz: stuknij go (albo portret), potem miejsce na mapie — pójdzie tam
(rzekę przechodzi mostem), sam walczy i wraca na swój punkt; po śmierci odradza się przy bazie. Jego umiejętności
rzucasz w zasięgu od niego; umiejętność rasy działa zawsze.

## Mapy

| Mapa | Charakter |
|---|---|
| Trzy drogi | trzy kręte ścieżki przez rzekę — klasyka na początek |
| Przesmyk | wszystkie ścieżki zbiegają się na jednym moście i zamieniają stronami |
| Serpentyna | krótki Środek, bardzo długa zygzakowata Północ — wieże w zakolach biją kilka pętli |

## Budynki i umiejętności

| Budynek | Koszt | Rola |
|---|---|---|
| Wydobywacz | 60 | na złożu, +2,5 / 4 / 5,5 zł/s (sporne złoże ×1,6) |
| Wieża | 80 | szybkie strzały w pojedynczy cel, trafia latających |
| Armata | 130 | wolna, obrażenia obszarowe, przebija pancerz — nie trafia latających |
| Mróz | 110 | spowalnia w obszarze, trafia latających |
| Koszary | 120 | piechur (wręcz) |
| Strzelnica | 150 | łucznik (dystans, trafia latających) |
| Warsztat | 200 | katapulta — burzy wieże i fortecę wroga |

Każdy budynek ma 3 poziomy; sprzedaż zwraca 60% włożonego złota; uszkodzone budynki regenerują się poza walką.

Wrogowie: ork, goblin (szybki), ogr (gruby), tarczownik (blokuje 60% obrażeń od strzał), nietoperz (leci na skróty nad mapą), **wódz** co 10 fal. Limity populacji: Twoja armia do 200, wrogów na mapie do 150. Od fali 40 wróg wpada w **furię** — każda fala silniejsza, więc długa obrona w końcu przegrywa. Fale idą zapowiedzianymi ścieżkami — chętniej słabo bronionymi; od fali 6 dzielą się na dwie, od 12 idą wszystkimi. Co 4 fale wróg stawia lub odbudowuje wieże.

## Sterowanie

- **Klik w złoże (●)** — wydobywacz.
- **Przycisk budynku → klik/przeciągnij i puść** na swojej połowie (podświetlone pola = wolne). PPM/Esc anuluje.
- **Klik w swój budynek** — panel: ulepsz / sprzedaj / **ścieżka produkcji**.
- **Dowódca**: klik w niego (albo portret nad paskiem, `H`) → klik w teren = marsz; klik w budynek/złoże albo `Esc` odznacza.
- **Umiejętność → klik na mapie** w zasięgu dowódcy (okrąg pokazuje, dokąd sięga); umiejętności bez celu działają od razu.
- **Mapa**: przeciągnij, żeby przesunąć · kółko albo dwa palce, żeby przybliżyć · „Mapa” wraca do całości · minimapa po przybliżeniu.
- Skróty: `1`–`6` budowa · `Q`/`E`/`R` umiejętności dowódcy · `T` rasy · `H` dowódca · `Spacja` postawa · `U` ulepsz · `Del` sprzedaj · `Tab` ścieżka · `F` prędkość · `WASD` przesuwanie · `+`/`−` zoom · `C` cała mapa · `M` dźwięk · `F3` licznik FPS · `Esc`/`P` pauza.

## Uruchamianie i testy

Otwórz folder w edytorze Godot 4.7 (F5) albo:

```bash
godot --path .
```

```bash
godot --headless --path . --script res://tests/bot_test.gd -- --mechanics
```

Android (telefon z debugowaniem USB podłączony kablem): eksport APK, instalacja i start gry:

```powershell
.\tools\android.ps1
```

Godot z wingeta nie trafia do PATH — pełna ścieżka i reszta komend w [CLAUDE.md](CLAUDE.md).

## Dokumenty

- [DECISIONS.md](DECISIONS.md) — log decyzji
- [ARCHITECTURE.md](ARCHITECTURE.md) — jak zbudowany jest kod
- [TODO.md](TODO.md) — roadmapa
