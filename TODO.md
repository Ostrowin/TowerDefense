# TODO — TowerDefense (Godot)

## Milestones

- [x] **P0 — prototyp**: jedna mapa, złoto + wydobywacze, koszary/strzelnica/wieża, skryptowane fale wroga, win/loss.
- [ ] **P1 — czy to jest fajne?**: kilka rund na każdej mapie, strojenie liczb, notatki co nudzi.
- [ ] **P2 — Android smoke test**: szablony eksportu, APK sideload na telefon, dotyk (szczypanie, przeciąganie, celowanie umiejętności), czytelność HUD (skala interfejsu), **pomiar fps w dużej bitwie** (desktop: ~2 ms sim + ~5,5 ms render przy ~275 jednostkach), czy ★/●/→ renderują się z systemowego fontu.
- [x] **P3 — głębia**: ulepszenia i sprzedaż, armata, mróz, warsztat + katapulta, postawa, umiejętności, nietoperze i tarczownicy, sprytny wybór ścieżek.
- [x] **P4 — treść**: 3 mapy (Trzy drogi, Przesmyk, Serpentyna) jako dane w `Levels`, wybór w menu, rekordy i gwiazdki.
- [~] **P5 — oprawa**: ✔ dźwięki i muzyka (synteza), efekty, menu/ustawienia/samouczek, teren. ✘ sprite'y CC0.

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

## Pomysły do sprawdzenia w P1

- Bot „balanced" (kupuje wszystko natychmiast, używa umiejętności) wygrywa wszędzie: Łatwy ~3–3,5 min, Normalny ~5–6,5 min, Trudny ~7–9,5 min. Czy Trudny nie jest za łatwy dla dobrego gracza?
- Czy nietoperze i tarczownicy zmuszają do mieszania wież, czy da się je zignorować?
- Czy sprytny wybór ścieżek jest czytelny (gracz rozumie, czemu fala idzie tam), czy frustruje?
- Czy Przesmyk nie sprowadza się do „wszystko na most"?
- Czy umiejętności mają dobry rytm (cooldown 40–60 s)?

## Backlog (świadomie odroczone)

- Multiplayer / netcode
- Asymetryczne rasy (zajączki, wydry, jeże, wilki, hieny, nietoperze)
- Prawdziwe AI wroga (teraz skrypt fal + ważony wybór ścieżek)
- Zapis/wczytanie trwającej partii
- iOS (wymaga Maca)
