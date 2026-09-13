# TowerDefense

Ekonomiczny lane-pusher: **tower defense + strategia**. Rozbudowujesz bazę, produkujesz armię, która **sama** maszeruje linią do bazy wroga, bronisz się wieżami. Serce zabawy = **ekonomia i build-order**, walka jest wynikiem dobrej machiny.

> Projekt do nauki C#/.NET + frajdy. Cel wysyłki: **Android**. Silnik: **MonoGame** (czysty C#, bez edytora).

## Status

**Planowanie zakończone, przed kodem.** Pełna wizja i decyzje: patrz [DECISIONS.md](DECISIONS.md), [ARCHITECTURE.md](ARCHITECTURE.md) oraz design doc w `~/.gstack/projects/TowerDefense/`.

## Core loop

```
Robotnik zbiera surowce  →  budujesz budynki produkcyjne  →  budynki spawnują jednostki
      →  jednostki maszerują linią do bazy wroga  →  wieże (obu stron) strzelają po drodze
      →  zniszcz bazę wroga = WYGRANA / wróg zniszczy Twoją = PRZEGRANA
```

Wróg w M1 jest **skryptowany** (spawn na timerze + wieże), nie inteligentne AI. Multiplayer 1v1 i asymetryczne rasy (zajączki, wydry, jeże, wilki, hieny, nietoperze) = gwiazda polarna na później.

## Stack

- **.NET 10** + **C#** (MonoGame 3.8.4.1 wymaga min .NET 9)
- **MonoGame** (DesktopGL do developmentu, Android jako cel wysyłki)
- **xUnit** do testów logiki Core
- Windows 11 jako maszyna deweloperska

## Struktura solution (docelowa)

```
TowerDefense.Core         biblioteka: symulacja + logika, ZERO renderu (testowalna headless)
TowerDefense.Core.Tests   xUnit
TowerDefense.DesktopGL     harness dev na Windows (render + input) ← tu spędzasz ~90% czasu
TowerDefense.Android       cel wysyłki (dodawany na M2)
```

Start budowy: tylko `Core` + `DesktopGL`. Android dochodzi na M2. iOS **wycięty**.

## Roadmap

| Milestone | Co |
|-----------|-----|
| **M0** | „Pierwsze światło": okno DesktopGL renderuje stan Core — jeden sprite jedzie po waypointach. |
| **M1a** | Jednokierunkowo: robotnik + ekonomia + budynek produkcyjny + marsz jednostek + baza wroga + win. Grywalne na desktopie. |
| **M1b** | Dwukierunkowo: skryptowany wróg + wieże obu stron + warunek przegranej. |
| **M2** | Ten sam wycinek na Androidzie (APK na urządzeniu). |
| **M3** (stretch) | Głębia ekonomii (więcej budynków, ulepszenia) + drugi poziom. |

## Jak zbudować / uruchomić (gdy kod powstanie)

```bash
# jednorazowo: szablony MonoGame
dotnet new install MonoGame.Templates.CSharp

# development na Windows
dotnet run --project TowerDefense.DesktopGL

# testy logiki Core
dotnet test
```

## Dokumentacja

- [TODO.md](TODO.md) — checklista milestone'ów i zadań
- [ARCHITECTURE.md](ARCHITECTURE.md) — diagramy i reguły architektury
- [DECISIONS.md](DECISIONS.md) — log decyzji (dlaczego tak)
- [CLAUDE.md](CLAUDE.md) — instrukcje dla asystenta AI
