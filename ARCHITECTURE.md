# Architecture — TowerDefense (Godot)

## Pliki

```
project.godot   1280×720, stretch canvas_items/keep, GL Compatibility, dotyk → mysz
main.tscn       jeden węzeł Node2D ze skryptem main.gd
main.gd         cała gra: dane, symulacja, input, HUD, rysowanie
```

Prototyp celowo w jednym skrypcie — najszybsza iteracja nad zabawą. Rozbijamy na sceny, gdy mechaniki się ustabilizują (patrz TODO P4).

## Model danych (main.gd)

- **Stałe konfiguracyjne**: `UNIT_TYPES`, `BUILDINGS`, `BASE_GUN`, pozycje złóż i wież wroga — tu się stroi balans.
- **Klasy wewnętrzne** (zwykłe obiekty, bez węzłów): `Unit`, `Building`, `Shot`.
- **Stan**: `gold`, `base_hp[2]`, listy `units` / `buildings` / `shots`, `taken_nodes`, stan fal wroga.
- Drużyny: `0` = gracz (lewo), `1` = wróg (prawo). Działka baz to ukryte budynki `basegun`.

## Klatka (`_process`)

```
dt = delta * speed_mult
 ├─ złoto += dochód * dt
 ├─ _update_enemy_script   fale co ~20 s → kolejka spawnu (co 0.7 s)
 ├─ _update_buildings      wieże/działka strzelają; koszary/strzelnice spawnują
 ├─ _update_units          wróg w zasięgu? bij : idź do niego | baza w zasięgu? bij bazę : maszeruj
 ├─ _update_shots          pociski lecą do celu; martwy cel = pocisk znika
 ├─ usuń martwe jednostki
 ├─ win/loss
 └─ HUD + queue_redraw → _draw rysuje wszystko prymitywami
```

## Kierunek rozbicia (gdy przyjdzie czas)

- `Unit`, `Tower`, `Building` jako sceny z własnymi skryptami.
- Konfiguracja jednostek/budynków jako `Resource` (.tres) — edytowalne w edytorze.
- Poziom jako scena (mapa, złoża, wieże wroga) + skrypt fal jako Resource.
- HUD jako osobna scena Control.
