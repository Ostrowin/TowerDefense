# TowerDefense

Ekonomiczny lane-pusher: **tower defense + strategia**. Rozbudowujesz ekonomię, stawiasz budynki produkujące armię, która **sama** maszeruje drogą do bazy wroga, i bronisz się wieżami. Serce zabawy = **ekonomia i build-order**.

> Cel: **fajna gra**. Silnik: **Godot 4.7 + GDScript**. Cel wysyłki: **Android**.

## Status

**Grywalny prototyp** (jeden skrypt, grafika z prymitywów). Balans wstępny.

## Core loop

```
złoto (pasywne + wydobywacze na złożach)  →  koszary / strzelnice / wieże
   →  jednostki same idą drogą  →  walka z falami wroga i jego wieżami
   →  zniszcz bazę wroga = WYGRANA / wróg zniszczy Twoją = PRZEGRANA
```

## Sterowanie

- **Klik w złoże (●)** — wydobywacz (60 zł, +2,5 zł/s).
- **Przycisk budynku → klik w siatkę** na swojej połowie (zielone = OK). PPM anuluje.
- **x1/x2** — prędkość gry.

## Uruchamianie

Otwórz folder w edytorze Godot 4.7 (F5) albo:

```bash
godot --path .
```

Godot z wingeta nie trafia do PATH — pełna ścieżka w [CLAUDE.md](CLAUDE.md).

## Dokumenty

- [DECISIONS.md](DECISIONS.md) — log decyzji (D15/D16: przejście na Godot, cel = fajna gra)
- [ARCHITECTURE.md](ARCHITECTURE.md) — jak zbudowany jest kod
- [TODO.md](TODO.md) — roadmapa
