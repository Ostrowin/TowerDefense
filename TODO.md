# TODO — TowerDefense

Kolejność ma znaczenie: **Core najpierw**, test headless, dopiero potem render. Odhaczaj w miarę postępu.

## Milestones

- [x] **M0 — pierwsze światło**: okno DesktopGL renderuje stan Core (sprite po waypointach). M0 jednorazowy, zero logiki sim w `Game1`.
- [x] **M1a — jednokierunkowy, grywalny na desktopie**: robotnik + ekonomia + budynek produkcyjny + marsz jednostek + statyczna baza wroga + warunek wygranej.
- [x] **M1b — dwukierunkowy**: skryptowany wróg (produkcja + spawn na timerze + wieże) + wieże gracza z celami + warunek przegranej.
- [ ] **M2 — Android**: ten sam wycinek na fizycznym telefonie (APK sideload). Rozważ crude smoke test już po M1a.
- [ ] **M3 (stretch)**: głębia ekonomii (2-3 budynki, ulepszenia) + drugi poziom → wtedy wydziel format danych poziomu.

## Zadania implementacyjne (z eng-review)

- [x] **T1 (P1)** — `Core`: najmniejszy model sim + fixed-step `Tick(fixedDt)` + stabilne ID encji (`SimState`, `ISimEntity`, `Unit`, `Base`, `EnemyBase`).
- [x] **T2 (P1)** — `Core.Tests`: jeden test xUnit przepuszczający ~60 s symulacji BEZ renderu (spawn → marsz → dmg → win). Dowód, że Core żyje sam.
- [x] **T3 (P1)** — `DesktopGL`: render stanu Core prymitywami; M0 jednorazowy.
- [x] **T4 (P1)** — `DesktopGL`: polityka współrzędnych (virtual resolution / kamera / mapowanie inputu) — ustal WCZEŚNIE.
- [x] **T5 (P2)** — `Core`: robotnik — ruch do celu (tap → idź), cykl gather→return, maszyna stanu, budowa. Teren bazy otwarty, bez A*.
- [x] **T6 (P2)** — `Core`: ekonomia + budynek produkcyjny + spawn + marsz + baza wroga/win → domyka M1a.
- [x] **T7 (P2)** — `Core`: skryptowany wróg (harmonogram) + wieże obu stron + warunek przegranej → M1b.
- [ ] **T8 (P3)** — `Android`: głowa Android + APK + uruchomienie na telefonie → M2.

## Do rozstrzygnięcia (open questions)

- [x] Grafika: prymitywy/kształty na M0/M1 (rekomendacja); paczki CC0 później.
- [x] Rozstawianie budynków: siatka (grid) — rekomendacja.
- [x] Węzły surowców: ile i gdzie na M1? Rekomendacja: 1-2 blisko bazy (krótki cykl robotnika).
- [x] Harmonogram skryptowanego wroga: kiedy spawnuje, czy ma zasoby, wieże preplaced, strojenie trudności.
- [x] Dorzucić clamp na akumulatorze fixed-step (max frame skip) — anty spiral-of-death.

## Backlog (świadomie odroczone — NIE robić teraz)

- **iOS** — usuwał bloker Mac/Xcode; wraca jako osobny wysiłek.
- **Multiplayer / netcode** — Core trzymany serializowalny, by drzwi zostały otwarte; 0 netcode teraz.
- **Pełny determinizm (fixed-point/lockstep)** — tylko gdyby wybrano lockstep-netcode.
- **Object pooling** — czysta alokacja teraz; pooling gdy profiling pokaże churn na Androidzie.
- **Format danych poziomów** — poziom 1 hardcode; format przy M3.
- **Asymetryczne rasy** — jedna „domyślna" frakcja najpierw.
- **Biblioteka UI Myra** — minimalny ręczny HUD na M1; Myra gdy UI urośnie i dotyk zweryfikowany.
- **Content Pipeline (MGCB)** — prymitywy na M0/M1; MGCB przy prawdziwych assetach/fontach.
- **Prawdziwe AI wroga** — wróg skryptowany, nie adaptacyjny.
