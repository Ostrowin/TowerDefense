# TODO — TowerDefense (Godot)

## Milestones

- [x] **P0 — prototyp**: jedna mapa, złoto + wydobywacze, koszary/strzelnica/wieża, skryptowane fale wroga, win/loss.
- [x] **P1 — czy to jest fajne?**: tak — werdykt gracza po partiach na telefonie (2026-09-25). Szczegółowe pytania do strojenia niżej zostają otwarte.
- [x] **P2 — Android smoke test**: szablony eksportu (tylko Android), preset, `tools/android.ps1` (build / instalacja / log / benchmark na telefonie), realme 8i (Helio G96, Mali-G57): pełny ekran 20:9, dotyk i HUD ×1,3 sprawdzone graniem, „Wstecz” jak Esc, ★/●/→/— z fontu OK, **duża bitwa: mediana 17,6 ms, p95 22,9 ms** (Trudny x3, do ~240 jednostek; wcześniej 60 ms). APK krąży też poza projektem (sideload).
- [x] **P3 — głębia**: ulepszenia i sprzedaż, armata, mróz, warsztat + katapulta, postawa, umiejętności, nietoperze i tarczownicy, sprytny wybór ścieżek.
- [x] **P4 — treść**: 3 mapy (Trzy drogi, Przesmyk, Serpentyna) jako dane w `Levels`, wybór w menu, rekordy i gwiazdki.
- [~] **P5 — oprawa**: ✔ dźwięki i muzyka (synteza), efekty, menu/ustawienia/samouczek, teren. ✘ sprite'y CC0, ikona aplikacji (teraz domyślna Godota).

## Sesja 7 (2026-09-25) — dowódcy: projekt i fundamenty

/office-hours → projekt dowódców ras ([docs/designs/dowodcy-ras.md](docs/designs/dowodcy-ras.md), D24) · Etap 0: rzeka i mosty w `Sim`,
nawigacja dowódcy (A* przez mosty, test „żadna trasa nie wchodzi w wodę” na każdej mapie), umiejętności jako typy efektów dla obu drużyn ·
hieny i dziki grywalne, przeciwnik losowany przy starcie · katalog 12 dowódców z WebSlashera.

## Sesja 6 (2026-09-25) — rasy

Wybór rasy w menu: 12 ras wspólnych z innymi grami (`Races`), grywalne Krety i Gibony (gibony zastąpiły goryle), reszta „Wkrótce” ·
nazwy ras nad fortecami, rasa gracza na ekranie końca. Bez wpływu na statystyki — czeka na lore.

## Sesja 5 (2026-09-24) — Android

Szablony eksportu (tylko pliki Androida, 230 MB z 1,28 GB) · preset + `tools/android.ps1` · stretch `expand` (pełny ekran 20:9) ·
„Wstecz” jak Esc · interfejs ×1,3 domyślnie na telefonie · benchmarki jako węzły (`-- --bench`) · `tests/render_probe.gd` ·
`Painter`: świat jednym wywołaniem rysowania (było ~600) — telefon: pusta gra 45 → 60 FPS, duża bitwa 60 → ~18 ms/klatkę.

## Sesja 4 (2026-09-24) — wydajność późnej gry

Przyczyna „wieszania się" pod koniec partii: liczba jednostek rosła bez końca (fala 50: ~2800) + spirala kroków przy x3.
Limity populacji (gracz 200, wróg 150, kolejka 40) · furia wroga od fali 40 (koniec patów) · sim 30 Hz z interpolacją ·
budżet 10 ms na kroki w klatce · uproszczone rysowanie dużych bitew · limity efektów · Line2D dla podświetleń ścieżek ·
licznik F3 · benchmark `tests/perf_test.gd`. Wynik: klatka ~7 ms przez całą 10-min partię na Trudnym (było do 130 ms).

## Sesja 3 (2026-09-24) — mapy, umiejętności, postęp

1. Mapy jako dane (`scripts/levels.gd`) + wybór mapy w menu (tło menu pokazuje wybraną mapę).
2. Mapa „Przesmyk": trzy ścieżki zbiegają się na jednym moście i zamieniają stronami.
3. Mapa „Serpentyna": prosty Środek, zygzakowata Północ (~3000 px), wieże w zakolach biją kilka pętli.
4. Postęp: rekordy czasu i gwiazdki per mapa × trudność (`Progress`, user://progress.cfg).
5. Umiejętności: Deszcz strzał (Q, obszar), Pobór (E, posiłki przy ścieżce), Naprawa (R) — cooldowny.
6. Nowi wrogowie: nietoperze (lecą na skróty, trafiają je tylko strzały/mróz), tarczownicy (pancerz 60% vs strzały).
7. Wieża mrozu: obszarowe spowolnienie (45%→61%), trafia też latających.
8. Sprytny wróg: fale częściej idą słabo bronioną ścieżką.
9. Ustawienia (głośność efektów/muzyki, rozmiar interfejsu ×1/×1,15/×1,3) + muzyka proceduralna.
10. Samouczek: 7 kontekstowych kroków przy pierwszej grze, „Pomiń", włączany ponownie w ustawieniach.
+ Wydajność: siatka przestrzenna, pola zamiast słowników, statyczna warstwa terenu — sim 11 → 2 ms, render 7,8 → 5,5 ms.

## Sesja 2 (2026-09-24) — ścieżki i mapa

Mapa 1600×900 + kamera · 3 kręte ścieżki (Curve2D) · rzeka z mostami · ścieżka produkcji w panelu ·
fale na różnych ścieżkach z zapowiedzią · strefa budowy od ścieżek · ataki na budynki + regeneracja ·
sporne złoża · minimapa · boty/testy pod ścieżki.

## Sesja 1 (2026-09-24)

Refaktor Sim/widok/Cfg · testy headless i boty · ulepszenia i sprzedaż · armata · warsztat + katapulta ·
postawa Atak/Obrona · goblin, wódz · efekty · dźwięk · menu/pauza/koniec + dotyk.

## Do strojenia (otwarte pytania z P1)

- Bot „balanced" (kupuje wszystko natychmiast, używa umiejętności) wygrywa wszędzie: Łatwy ~3–3,5 min, Normalny ~5–6,5 min, Trudny ~6–7 min. Czy Trudny nie jest za łatwy dla dobrego gracza?
- Czy nietoperze i tarczownicy zmuszają do mieszania wież, czy da się je zignorować?
- Czy sprytny wybór ścieżek jest czytelny (gracz rozumie, czemu fala idzie tam), czy frustruje?
- Czy Przesmyk nie sprowadza się do „wszystko na most"?
- Czy umiejętności mają dobry rytm (cooldown 40–60 s)?

## P6 — dowódcy ras (projekt: [docs/designs/dowodcy-ras.md](docs/designs/dowodcy-ras.md))

3 dowódców na rasę (krety: Saper, Snajper, Magma; gibony: do zaprojektowania), sterowani przez gracza (jak commander w Supreme Commander / 40k),
3 umiejętności dowódcy + 1 umiejętność rasy, umiejętności jako dane z typów efektów (dla obu drużyn). Wróg na razie bez dowódcy.

**Rozstrzygnięte:** Podkop = efekt dla całej armii · gibony = kopia goryli z WebSlashera (brakujące wymyślamy po drodze) ·
grywalne też hieny i dziki, przeciwnik losowy · katalog 12 dowódców: [docs/designs/dowodcy-katalog.md](docs/designs/dowodcy-katalog.md).
**Eng review (D1–D9):** 12 dowódców w iteracji · bohater = `class Hero extends Unit` (poza limitami armii i obroną ścieżek) · wróg bez bossa, AI dowódcy wroga w backlogu · po rozkazie dowódca zostaje zaznaczony, budynek/złoże = normalna akcja · dane w `cfg.gd` · kontrakt regresji: gra bez dowódcy = tabela botów z 8d8fa4c.
**Otwarte:** komu Pobór i Naprawa (blokuje usunięcie „Weterana”) · szczegóły Etapu 4 (uwagi recenzenta w projekcie) → przegląd + `/plan-design-review` przed T14.

- [x] **Etap 0 — fundamenty:** T1 rzeka i mosty w `Sim` · T2 nawigacja (`AStarGrid2D`, `Sim.path_to`) · T3 umiejętności jako typy efektów z `team` — mecze botów bez zmian
- [x] **Etap 1 — dowódca gracza:** ~~T4 dane dowódców~~ ✅ · ~~T5 bohater w `Sim`~~ ✅ · ~~T6 nowe typy efektów~~ ✅ · ~~T7 widok, dotyk, samouczek~~ ✅ · ~~T8 menu~~ ✅ · ~~T9 Saper + Podkop + bot + balans~~ ✅ → **gra na telefonie**
- [x] **Etap 2 — reszta dowódców:** ~~T10 Snajper, Magma~~ ✅ · ~~T11 gibony~~ ✅ · ~~T11b hieny i dziki~~ ✅
- [x] **Etap 3 — domknięcie:** ~~T12 boss rywala~~ (usunięte, D5) · ~~T13 balans całości, kontrakt regresji, perf, dokumentacja~~ ✅ (telefon: p95 20,3 ms w późnej grze z Saperem, 2026-09-26)
- [ ] **Seria wydajności wszystkich dowódców na telefonie (~1 h):** jedno uruchomienie `-Bench`, które samo przechodzi przez 12 dowódców z `--stress` (dziś każdy = osobny eksport). Argumenty podawać przez `pwsh -Command "& ./tools/android.ps1 -Bench -BenchArgs ..."` — `pwsh -File` skleja listę `-BenchArgs` w jeden napis i benchmark rusza z domyślnymi.
- [ ] **Etap 4 — rozbudowa (CEO review):** ~~T14 awans dowódcy w partii~~ ✅ · ~~T15 tryb przetrwania~~ ✅ · ~~T16 wyzwanie dnia z modyfikatorami~~ ✅ · T17 pojedynek 2 graczy na jednym telefonie (największe ryzyko: symetryczna ekonomia wroga)

## Lore i rasy (do przemyślenia)

- Lore świata wspólne z innymi grami — kto z kim walczy i dlaczego (pierwsze grywalne: krety i gibony).
- Czy rasy dostają własne jednostki/mechaniki (asymetria), czy zostają tożsamością? Od tego zależy skala roboty.
- Wrogowie w kodzie nadal nazywają się ork/goblin/ogr/wódz (`Cfg.UNITS`) — przemianować pod lore.
- Styl grafiki (P5) wybieramy dopiero po lore.

## Backlog (świadomie odroczone)

- AI dowódcy wroga — samo decyduje, na której ścieżce dowódca wroga się przyda (eng review 2026-09-25, D5; umiejętności już działają dla obu drużyn)
- Podział `main.gd` (~2000 linii): HUD i sterowanie dowódcą do osobnych plików, najlepiej przed większymi zmianami widoku (eng review, D9)

- Multiplayer / netcode
- Asymetryczne rasy (różne jednostki i mechaniki — wybór ras w menu już jest, patrz „Lore i rasy”)
- Prawdziwe AI wroga (teraz skrypt fal + ważony wybór ścieżek)
- Zapis/wczytanie trwającej partii
- iOS (wymaga Maca)
- Kampania świata ras: mapa bitew z warunkami, linie fabularne ras (lore), odblokowywanie dowódców — po dowódcach i lore (CEO review 2026-09-25, D2)
