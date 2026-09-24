# CLAUDE.md — TowerDefense (Godot)

Gra **tower defense + strategia** (ekonomiczny lane-pusher). Cel: **fajna gra** (nie nauka). Silnik: **Godot 4.7 + GDScript**. Cel wysyłki: **Android**. Historia decyzji: [DECISIONS.md](DECISIONS.md) (D15, D16 zastępują ustalenia z ery MonoGame; ARCHITECTURE.md jest nieaktualne).

## Stan
Prototyp: cała gra w [main.gd](main.gd) (rysowanie przez `_draw`, HUD z węzłów Control budowany w kodzie). Świadomie — iterujemy nad zabawą; rozbijamy na sceny/węzły, gdy mechanika się ustabilizuje.

## Uruchamianie
Godot z wingeta (nie ma go w PATH):
`C:\Users\lucci\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- walidacja: `--headless --path . --quit-after 900` (szukaj błędów w wyjściu)
- gra: `--path .`

## Konwencje
- Statyczne typy w GDScript (`var x: float`, jawny typ gdy RHS to Variant).
- Współrzędne: viewport 1280×720, stretch `canvas_items`/`keep`, input dotykowy emulowany jako mysz.
- Grafika na razie prymitywy; assety CC0 później.
- Zakres pod dyscypliną — najpierw zabawa rdzenia, potem treść.
