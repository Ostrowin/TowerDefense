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

### D17 — Sim oddzielony od widoku; balans strojony botami (2026-09-24)
**Decyzja:** logika w `Sim` (RefCounted, bez węzłów), widok w `main.gd`, konfiguracja w `Cfg`. Sim komunikuje się z widokiem listą zdarzeń. Balans sprawdzamy headless meczami botów (`tests/bot_test.gd`).
**Dlaczego:** jeden plik przestał się mieścić w głowie przy 10 nowych mechanikach; headless sim daje testy mechanik i szybką pętlę strojenia (9 meczów w ~15 s) bez klikania. To nie jest powrót do rygoru z ery MonoGame — nie ma wymogu 100% pokrycia; testujemy to, co łatwo zepsuć.
**Status:** aktywna.

### D18 — Trzy kręte ścieżki na krzywych, większa mapa z kamerą (2026-09-24)
**Decyzja:** mapa 1600×900 (ekran 1280×720, kamera domyślnie pokazuje całość), trzy ścieżki jako `Curve2D` z punktów kontrolnych w `Cfg.LANES`. Jednostka ma pozycję wzdłuż ścieżki `s`, nie tylko x. Wszystko zależne od kształtu mapy (sloty wież wroga, strefa budowy, linie zbiórki, mosty, plan bota) jest wyliczane z krzywych. Produkcja ma przypisaną ścieżkę; fale wroga są zapowiadane i z czasem dzielą się na więcej ścieżek.
**Dlaczego:** użytkownik chciał wielu dróg do wroga i dłuższych, krętych ścieżek. Krzywe z punktów kontrolnych = mapa jako dane (krótki krok do poziomów jako Resource). Wybór ścieżki natarcia i obrona pozostałych dodaje decyzję strategiczną bez nowego systemu sterowania jednostkami (nadal auto-marsz, zgodnie z D4).
**Konsekwencje:** każda ścieżka spawnuje wrogów równolegle (inaczej przy dzielonych falach kolejka rosła w nieskończoność i powstawał pat), prędkości jednostek +25% (ścieżki są o ~55% dłuższe). Jednostki atakują budynki przy ścieżce — pozycja wieży to kompromis zasięg/ryzyko.
**Status:** aktywna.

### D19 — Mapy jako dane, sprytny wróg, umiejętności; wydajność mierzona, nie zakładana (2026-09-24)
**Decyzja:** geometria map przeniesiona z `Cfg` do `Levels` (słowniki z punktami ścieżek, złożami, slotami); gra ma 3 mapy. Wróg wybiera ścieżki fal losowaniem ważonym słabością obrony gracza. Gracz dostaje 3 umiejętności z cooldownem — pierwszy element sterowania „w trakcie" bitwy. Postęp (rekordy, gwiazdki, samouczek) i ustawienia w `user://` przez `ConfigFile`; testy podmieniają ścieżki plików.
**Dlaczego:** kolejne mapy bez zmian w kodzie; sprytny wróg nagradza obronę wszystkich ścieżek i karze zostawienie jednej pustej; umiejętności dają agencję w grze, w której armia maszeruje sama (D4 nadal obowiązuje — to dodatek, nie mikro).
**Lekcja:** wcześniejszy pomiar „0,43 ms na krok" był błędny (partia w teście już się skończyła, sim stał). Realnie ~11 ms przy ~275 jednostkach. Po siatce przestrzennej, polach zamiast słowników i warstwie terenu: sim ~2 ms, render ~5,5 ms. Pomiary wydajności robimy na trwającej partii (`result == 0`) i sprawdzamy, co robią jednostki.
**Status:** aktywna.

### D20 — Limity populacji, furia wroga, sim 30 Hz z interpolacją, budżet klatki (2026-09-24)
**Decyzja:** armia gracza max `MAX_ARMY` = 200, wrogów na mapie max `MAX_ENEMIES` = 150, kolejka fali max `MAX_SPAWN_QUEUE` = 40. Od fali 40 „furia": HP i obrażenia nowych wrogów +6% na falę. Symulacja liczy 30 kroków/s (było 60), render interpoluje pozycje. Pętla kroków ma budżet 10 ms na klatkę — po przekroczeniu porzuca zaległości. W dużej bitwie jednostki rysowane uproszczone, efekty mają limity.
**Dlaczego:** użytkownikowi „wieszał się PC pod koniec partii". Benchmark (`tests/perf_test.gd`) pokazał, że jednostek przybywało bez końca (fala 50: ~2800), koszt rósł liniowo, a przy x3 wolna klatka wymuszała jeszcze więcej kroków w następnej (spiral of death). Pamięć stała — to nie był wyciek.
**Strojenie limitów (boty, 3 mapy × 3 trudności):**
- limity 120/150 → paty po 25 min na Trudnym i na Przesmyku: gracz z niższym limitem nie przełamywał obrony, wróg nie przełamywał gracza;
- wzrost obrażeń wroga od 1. fali → psuł środek gry (Normalny przestał być wygrywalny) — odrzucone; furia dopiero od fali 40 rozstrzyga paty bez ruszania wczesnej gry;
- limit gracza 150 → Przesmyk (jeden most) nie do przełamania; 200 > 150 wroga naprawia;
- kolejka 150 → baza wroga miała niekończące się posiłki na miejscu, Trudny nie do wygrania; kolejka 40 → Trudny znów wygrywalny (6–7 min).
**Status:** aktywna.

### D21 — Eksport na Androida bez Gradle, pełny ekran przez stretch „expand" (2026-09-24)
**Decyzja:** APK z gotowego szablonu (bez Gradle i `android_source.zip`), tylko arm64-v8a, podpis kluczem debug także dla release (sideload na własny telefon). Pobrane tylko pliki Androida z paczki szablonów (230 MB z 1,28 GB — odczyt zakresów HTTP, CRC każdego pliku sprawdzone). SDK i JDK 21 już były (z Visual Studio). Build, instalacja, log i benchmark na telefonie — `tools/android.ps1`. Widok: stretch `expand` zamiast `keep`; na telefonie domyślna skala interfejsu ×1,3; systemowe „Wstecz" działa jak Esc.
**Dlaczego:** Gradle potrzebny dopiero przy wtyczkach/Play Store — bez niego build trwa sekundy i nie wymaga dodatkowych pobrań. Telefony mają ~20:9, a `keep` przy 16:9 zostawiał ~20% ekranu na czarne pasy; wysokość 720 zostaje, HUD i tak liczył się od `screen`. HUD na 720 px na ekranie o wysokości ~7 cm daje napisy ~1,5 mm przy ×1. Domyślne „Wstecz" zamykało grę w trakcie partii.
**Status:** aktywna. Do Google Play potrzebny będzie własny klucz release (i najpewniej AAB przez Gradle).

### D22 — Świat rysowany jednym wywołaniem (`Painter`) (2026-09-24)
**Decyzja:** wszystkie kształty świata (koła, łuki, linie, prostokąty, wielokąty) trafiają do jednej listy trójkątów (`scripts/painter.gd`, `canvas_item_add_triangle_array`), napisy rysowane na końcu, na wierzchu. Koła terenu (trawa, drzewa) liczone raz przy zmianie mapy. W `main.gd` świat rysuje `pen.*` zamiast `draw_*` (te same argumenty).
**Dlaczego:** pomiar na telefonie (realme 8i, Mali-G57), a nie zgadywanie. Sonda warstw (`tests/render_probe.gd`) pokazała ~600 wywołań rysowania na klatkę, z czego ~430 to statyczny teren: każde `draw_circle` to osobne wywołanie (Godot nie łączy wielokątów w paczki). Pusta gra miała 45 FPS; niższa rozdzielczość renderu nic nie dawała (to nie wypełnianie pikseli), wyłączenie terenu dawało 60. W dużej bitwie klatka rosła do 60 ms — do tego wątek czekający na GPU był zrzucany przez system na mały rdzeń i zwalniał też sim.
**Wynik:** wywołania 599 → 77 (świat 40, reszta to HUD i teren z krzywych); telefon: pusta gra 60 FPS, `perf_test` (Trudny, x3, do ~240 jednostek) mediana 17,6 ms, p95 22,9 ms (było 53–61 ms przy ~150 jednostkach). Na PC rysowanie GDScript też szybsze (2,0 → 1,2 ms).
**Kompromis:** napisy świata zawsze na wierzchu (wcześniej np. jednostka mogła przykryć „60 zł" przy złożu). Koła mają 8–64 boków zależnie od promienia.
**Status:** aktywna. Nowe rysowanie świata → `pen.*`; gołe `draw_circle` w pętli po jednostkach wraca problem.

### D23 — Rasy wspólne z innymi grami; pierwsze grywalne: krety i gibony (2026-09-25)
**Decyzja:** 12 ras z innej gry użytkownika (te same id i kolory — spójne lore między grami) jako dane w `scripts/races.gd`. Goryle zastąpione gibonami. Pierwsze grywalne rasy: krety i gibony — gracz wybiera jedną w menu, przeciwnikiem jest druga (`Races.rival`). Pozostałe rasy widoczne w menu jako „Wkrótce”. Rasa to na razie tożsamość: nazwa, kolor rasy (ramka karty w menu), hasło, podpisy nad fortecami, rasa gracza na ekranie końca. Tytuł gry bez zmian — roboczo „Tower Defense”.
**Dlaczego:** użytkownik buduje kilka gier w jednym świecie i dopiero pracuje nad lore; menu z 12 rasami pokazuje kierunek bez przesądzania mechaniki. Statystyki ras świadomie pominięte.
**Kompromis:** na mapie zostają barwy drużyn (niebieski — Ty, czerwony — wróg), nie kolory ras — brązowy kret i jasny gibon na ciemnej trawie byłyby mniej czytelne i słabo się od siebie odróżniały. Do zmiany razem z grafiką (P5). Wybór rasy nie jest zapamiętywany między uruchomieniami (jak wybór mapy).
**Status:** aktywna. Asymetria ras (własne jednostki/mechaniki) — w backlogu, po lore.

### D24 — Dowódcy ras: sterowany bohater po obu stronach (2026-09-25, projekt)
**Decyzja:** każda rasa dostaje 3 dowódców (krety: Saper, Snajper, Magma — jak specjalizacje w WebSlasherze). Dowódca to wybór przed bitwą (3 umiejętności w pasku + 1 umiejętność rasy, np. Podkop kretów) i postać na mapie sterowana jak bohater w Kingdom Rush (stuknij, stuknij cel; sam walczy, odradza się). Umiejętności to dane z typów efektów, działające dla obu drużyn — wróg dostaje dowódcę rywala jako bossa co 10 fal zamiast Wodza. Zakres: od razu 6 dowódców i obie strony, z punktem kontrolnym na telefonie po pierwszym (Saper).
**Dlaczego:** najtańsza droga do ras, które naprawdę grają inaczej (bez 12 osobnych armii), spójna ze światem innych gier użytkownika. Sterowanie jedną postacią to **świadomy wyjątek od D4** (walka automatyczna) — armia dalej maszeruje sama. Wzór sterowania sprawdzony na telefonach (Kingdom Rush). Sesja /office-hours 2026-09-25; szczegóły, reguły R1–R11 i lista tasków: [docs/designs/dowodcy-ras.md](docs/designs/dowodcy-ras.md).
**Status:** w realizacji — Etap 0 (rzeka w `Sim`, nawigacja, umiejętności jako typy efektów dla obu drużyn) zrobiony 2026-09-25. Podkop = efekt dla całej armii; gibony = kopia goryli z WebSlashera.
