# CLAUDE.md — TowerDefense

Instrukcje dla asystenta AI (Claude Code / gstack) pracującego w tym repo.

## Kontekst projektu

Gra **tower defense + strategia** (ekonomiczny lane-pusher) do nauki C#/.NET. Serce = ekonomia/build-order; jednostki auto-maszerują linią do bazy wroga; wieże bronią. Cel wysyłki: **Android**. Silnik: **MonoGame** (czysty C#, bez edytora). Projekt solo, edukacyjny. Pełny kontekst: [DECISIONS.md](DECISIONS.md), [ARCHITECTURE.md](ARCHITECTURE.md), README.

## Reguły architektury (twarde)

- **Core najpierw, testowalny headless.** Cała logika/symulacja w `TowerDefense.Core` — ZERO zależności od renderu. Najpierw model + test 60 s sim bez renderu, dopiero potem render.
- **Sim oddzielony od renderu**, pętla o **stałym kroku** (fixed timestep). Render interpoluje stan, nie zmienia go.
- **Ścieżki jednostek = waypointy, NIE A\*.** Ruch robotnika = bezpośrednio do celu (teren bazy otwarty), też bez A*.
- **Determinizm ODROCZONY** — sim ma być *serializowalny* (zapis/wczytanie), nie deterministyczny cross-platform. Nie wprowadzaj fixed-point/lockstep bez wyraźnej decyzji.
- **Object pooling ODROCZONY** — czysta alokacja teraz. Encje projektuj ze stabilnym ID i jawnym cyklem create/destroy, żeby pooling dało się dodać później bez przepisywania. Optymalizuj dopiero gdy profiling pokaże churn.
- **Przestrzeń współrzędnych ustalona wcześnie** — virtual resolution / kamera / mapowanie inputu przed dużą ilością UI i współrzędnych.
- **Serializacja: referencje przez ID, nie wskaźniki**; obsłuż martwe encje, cele pocisków, stan RNG, wersjonowanie zapisu.
- **Model encji: zwykłe listy/struktury za `ISimEntity.Update(fixedDt)`, NIE ECS.**
- **UI: minimalny ręczny HUD** na M1. Nie dodawaj Myry ani innej biblioteki UI bez decyzji.
- **Grafika M0/M1: prymitywy lub tekstura 1×1.** Content Pipeline (MGCB) dopiero przy prawdziwych assetach.
- **M0 jednorazowy** — nie zostawiaj logiki sim w `Game1`.

## Testy

- Framework: **xUnit**, projekt `TowerDefense.Core.Tests`.
- Komenda: `dotnet test`.
- Testuj **logikę Core**: sim tick, ruch po waypointach, damage/death, przyrost zasobów, cykl robotnika, harmonogram spawnu, win/loss, edge case'y (pusty waypoint, zajęty kafel, brak zasobów, wiele jednostek w zasięgu wieży).
- **NIE testuj** renderu MonoGame (SpriteBatch/Draw).
- Cel: 100% pokrycia logiki Core. Testy piszemy razem z kodem, nie później.

## Konwencje

- .NET 10 (net10.0), C#. Explicit ponad clever. DRY. Prawy rozmiar zmiany. (MonoGame 3.8.4.1 wymaga min .NET 9; celujemy w 10.)
- Zakres pod dyscypliną: M1 rozbity na M1a (jednokierunkowy) → M1b (dwukierunkowy). Nie rozdmuchuj wycinka.
- Diagramy ASCII w komentarzach przy nietrywialnych rzeczach (maszyna stanu robotnika, pipeline walki). Aktualizuj diagramy razem z kodem.

## Skill routing

Gdy prośba pasuje do skilla gstack, wywołaj go przez Skill tool. W razie wątpliwości — wywołaj skill.

- Pomysły/burza mózgów → /office-hours
- Strategia/zakres → /plan-ceo-review
- Architektura → /plan-eng-review
- Bugi/błędy → /investigate
- QA/testowanie → /qa lub /qa-only
- Code review/diff → /review
- Zapis/odtworzenie kontekstu → /context-save, /context-restore
- Specyfikacja → /spec

## Wskazówki startowe

Zaczynasz kod? Kolejność z [TODO.md](TODO.md): `git init` → Core + test 60 s headless → M0 render → M1a → M1b → M2. Nie skacz od razu do wież i budynków przed działającym, przetestowanym Core.
