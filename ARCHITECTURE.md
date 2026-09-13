# Architecture — TowerDefense

## Struktura solution

```
TowerDefense.sln
├── TowerDefense.Core          biblioteka: symulacja + logika, ZERO renderu
│   ├── SimState               cały stan gry (serializowalny, referencje przez ID)
│   ├── ISimEntity             Update(fixedDt)
│   ├── Worker                 maszyna stanu: zbieranie + budowa
│   ├── ProductionBuilding     spawnuje Unit co interwał
│   ├── Unit                   podąża za waypointami
│   ├── Tower                  namierza + strzela do jednostek w zasięgu
│   ├── Base / EnemyBase       HP, warunek win/lose
│   ├── ResourceNode           źródło surowców dla robotnika
│   └── Tick(fixedDt)          fixed-step, ustalona kolejność systemów
├── TowerDefense.Core.Tests    xUnit (60 s sim headless + edge cases)
├── TowerDefense.DesktopGL      harness dev na Windows: render + input   ← ~90% czasu tu
└── TowerDefense.Android        cel wysyłki (dodawany na M2)
```

Zasada: `Core` nie wie nic o MonoGame. `DesktopGL` i `Android` to cienkie „głowy", które renderują stan Core i przekazują input. Ten sam Core wszędzie → drzwi do przyszłego multiplayera otwarte (przez serializowalny stan).

## Przepływ ticku symulacji

```
[Input] --(rozkazy: buduj, rusz robotnika)--> SimState.Tick(fixedDt)
                                                     │
   ┌──────────────┬──────────────┬──────────────────┼──────────────────┐
   ▼              ▼              ▼                    ▼                  ▼
EconomyTick   WorkerUpdate   ProductionSpawn    MovementUpdate      (obie strony)
 zasoby +=     FSM stan       co interwał→Unit    waypoint→pozycja
   │              │              │                    │
   └──────────────┴──────► CombatUpdate ◄─────────────┘
                          wieże namierzają → strzał → dmg
                                   │
                            WinLossCheck (HP baz)
                                   │
                    (render interpoluje stan — OSOBNO, nie w Core)
```

Fixed timestep: akumulator kroków; rozważ clamp (max frame skip), żeby wolna klatka nie wywołała spirali. Render osobno, może interpolować między dwoma stanami sim.

## Maszyna stanu robotnika

```
                 tap: węzeł surowca
        Idle ───────────────────────► GoToNode ──dotarł──► Gather
         ▲                                                    │
         │                                              pełny │
         │                          Deposit ◄──dotarł── Return
         │                            │
         └────────────────────────────┘
         │
         │ tap: plac budowy
         └──────────────► GoToBuild ──dotarł──► Build ──gotowe──► Idle
```

Ruch bezpośredni do celu (lerp/krok w stronę), teren bazy otwarty → bez A*. Gdyby baza miała przeszkody, dopiero wtedy pathfinding.

## Model encji

- Zwykłe listy/struktury w `SimState`, każda encja implementuje `ISimEntity.Update(fixedDt)`. **Nie ECS** (dyscyplina zakresu).
- Każda encja ma **stabilne ID**; inne encje trzymają referencje przez ID (np. cel pocisku, cel wieży), nie przez wskaźnik — żeby serializacja i usuwanie martwych encji były czyste.
- Usuwanie: oznacz martwe (dead-flag), sprzątaj na końcu ticku w ustalonej kolejności (unikaj modyfikacji kolekcji w trakcie iteracji).

## Render / współrzędne

- Ustal politykę **virtual resolution** (stała logiczna rozdzielczość) + kamera + mapowanie inputu **wcześnie**. Współrzędne sim są logiczne; render/înput skalują do ekranu urządzenia.
- Bez tego touch placement, zasięgi wież, skalowanie HUD i współrzędne ścieżek trzeba będzie przepisać przy przejściu na Androida.

## Testowalność

`Core` działa bez okna — `Tick(fixedDt)` w pętli to „gra bez ekranu". Stąd test 60 s symulacji headless jest tani i jest pierwszym dowodem, że logika żyje sama. To główny powód podziału Core/head.
