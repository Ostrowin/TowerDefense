# Decisions — TowerDefense

Log decyzji (ADR-lite). Każdy wpis: **decyzja**, **dlaczego**, **status**. Źródło: sesje /office-hours + /plan-eng-review, 2026-09-12.

---

### D1 — Gra wygrywa nad nauką MAUI
**Decyzja:** priorytet to dobra gra; technologię dobieramy pod nią, nie pod naukę MAUI.
**Dlaczego:** MAUI to framework aplikacji, nie silnik gier — real-time RTS w MAUI to walka pod prąd. Nauka .NET i tak zostaje przez silnik mówiący po C#.
**Status:** aktywna.

### D2 — Silnik: MonoGame (czysty C#/.NET)
**Decyzja:** MonoGame zamiast Unity/Godota.
**Dlaczego:** świadomy wybór głębokiej, transferowalnej nauki .NET nad szybkością. Unity uczy „Unity-C#"; Godot ma eksperymentalny eksport C# na mobile (koniec 2025). MonoGame = czysty C#, sprawdzony na mobile (Stardew, Celeste), pełna kontrola.
**Status:** aktywna. Kompromis: budujesz wszystko sam (bez edytora, UI, pathfindingu).

### D3 — Cel wysyłki: tylko Android; iOS wycięty
**Decyzja:** wysyłamy na Android; iOS wypada z zakresu.
**Dlaczego:** iOS wymaga Maca + Xcode niezależnie od silnika (jesteś na Windows). Wycięcie usuwa cały bloker. Android buduje się z Windows.
**Status:** aktywna. iOS może wrócić jako osobny wysiłek.

### D4 — Serce = ekonomia; walka automatyczna
**Decyzja:** rdzeń zabawy to ekonomia/build-order; jednostki auto-maszerują, wieże auto-strzelają.
**Dlaczego:** lżejsza presja real-time (pasuje na dotyk i solo), satysfakcja „patrz jak machina miele".
**Status:** aktywna.

### D5 — Struktura: Core + głowy; start od 2 projektów
**Decyzja:** `Core` (sim, headless) + głowy `DesktopGL` (dev) i `Android` (ship). Start: tylko Core + DesktopGL; Android na M2.
**Dlaczego:** DesktopGL to harness dev (build+run w sekundy, pełny debugger), nie cel wysyłki — przyspiesza iterację. Puste głowy platformowe = balast, dodaje się je gdy potrzebne.
**Status:** aktywna.

### D6 — Determinizm odroczony (tylko serializowalny stan)
**Decyzja:** sim serializowalny teraz; pełny determinizm (fixed-point/lockstep) później, jeśli w ogóle.
**Dlaczego:** serializowalny stan wystarcza, by drzwi do MP zostały otwarte. Pełny determinizm to spora robota potrzebna tylko dla lockstep-netcode, którego możesz nie wybrać.
**Status:** aktywna.

### D7 — Poziom 1 hardcode; format danych później
**Decyzja:** poziom 1 zaszyty w C#; format ładowania poziomów dopiero przy M3 (drugi poziom).
**Dlaczego:** „make the change easy, then make the easy change" — nie buduj loadera zanim masz 2 poziomy do uzasadnienia.
**Status:** aktywna.

### D8 — M1 dwukierunkowy (rozszerzenie zakresu)
**Decyzja:** w M1 obie strony produkują i wysyłają jednostki; wróg **skryptowany** (spawn na timerze + wieże), nie AI. Przegrana = wróg zniszczy Twoją bazę.
**Dlaczego:** użytkownik chciał pełnej pętli atak+obrona od pierwszego grywalnego builda. Świadome rozszerzenie ponad rekomendację. Rozłożone na M1a (jednokierunkowy) → M1b (dwukierunkowy), żeby nie rozsadzić wycinka.
**Status:** aktywna. Ryzyko: większy M1 — pilnować tempa do pierwszej grywalnej wersji.

### D9 — Robotnik-zbieracz w M1 (rozszerzenie zakresu)
**Decyzja:** sterowalny robotnik zbiera surowce z węzłów i buduje.
**Dlaczego:** robotnik był w wizji od początku. Świadome rozszerzenie ponad rekomendację (i CEO, i Codex sugerowali cięcie). Pociąga maszynerię: ruch, cykl gather→return, maszyna stanu, UI rozkazów — zapisane jako część zakresu M1. Ruch bezpośredni do celu (bez A*).
**Status:** ZASTĄPIONA przez D14.

### D10 — Pooling odroczony (cross-model, zmiana rekomendacji)
**Decyzja:** czysta alokacja teraz; object pooling dopiero gdy profiling na Androidzie pokaże churn.
**Dlaczego:** pooling przed ustabilizowaniem modelu sim utrudnia naukę na bugach cyklu życia i gryzie się z serializacją. Głos z zewnątrz (Codex) przekonał; przyjęte. Encje projektujemy ze stabilnym ID i jawnym create/destroy, by pooling dało się dodać bez przepisywania.
**Status:** aktywna.

### D11 — Sekwencja Core-first (od Codeksa)
**Decyzja:** najpierw najmniejszy model Core + test ~60 s symulacji bez renderu, dopiero potem render.
**Dlaczego:** inaczej separacja Core jest kosmetyczna, a logika ląduje w `Game1`.
**Status:** aktywna.

### D12 — Przestrzeń współrzędnych ustalona wcześnie (od Codeksa)
**Decyzja:** polityka virtual resolution / kamera / mapowanie inputu przed dużą ilością UI/współrzędnych.
**Dlaczego:** bez tego touch placement, zasięgi wież, skalowanie HUD i współrzędne ścieżek trzeba przepisać przy przejściu na Androida.
**Status:** aktywna.

### D13 — Target .NET 10 (odwraca .NET 8 z planu)
**Decyzja:** całe solution celuje w `net10.0`.
**Dlaczego:** MonoGame 3.8.4.1 wymaga min .NET 9, a .NET 10 jest wspierany; plan mówił .NET 8 (moja wiedza ze stycznia 2026), ale to już poniżej minimum MonoGame. Maszyna ma SDK 10.0.401 — zero instalacji.
**Status:** aktywna. Zastępuje wcześniejsze założenie „.NET 8".

### D14 — Robotnik „warhammerowy": buduje wydobywacze na złożach, reszta automat (zastępuje D9)
**Decyzja:** robotnik nie nosi surowców (brak gather→return). Jego rola: iść na węzeł surowca i postawić na nim **Extractor** (wydobywacz), który potem **automatycznie** generuje surowce w czasie (ciągnąc z węzła). Model jak Dawn of War / Company of Heroes.
**Dlaczego:** prościej (znika cykl noszenia i maszyna stanu carry/return), lepiej pasuje do serca „ekonomia = build-order" (agencja gracza = które złoża zająć i kiedy), reużywa `ResourceNode.Extract`. Uproszczenie zakresu M1 bez utraty „gracz coś stawia palcem".
**Status:** aktywna. FSM robotnika upraszcza się do: GoToNode → Build → Idle (zaktualizować ARCHITECTURE.md przy budowie robotnika).

---

### D15 — Zmiana silnika: Godot 4 + GDScript (zastępuje D2, D5, D13)
**Decyzja:** porzucamy MonoGame. Silnik: **Godot 4.7**, język: **GDScript**, renderer GL Compatibility.
**Dlaczego:** nowy cel (D16) to fajna gra, nie nauka .NET — edytor, UI, sceny i eksport na Androida gratis. GDScript zamiast C#, bo eksport C# na mobile w Godocie jest mniej dojrzały, a GDScript iteruje najszybciej.
**Status:** aktywna.

### D16 — Cel: fajna gra, nie nauka (zastępuje priorytet nauki z D1/D2)
**Decyzja:** priorytet = grywalność i szybka iteracja nad zabawą. Architektura Core/headless/xUnit z ery MonoGame przestaje obowiązywać.
**Dlaczego:** decyzja użytkownika, 2026-09-24.
**Status:** aktywna. Prototyp w jednym `main.gd`; podział na sceny gdy mechaniki się ustabilizują.
