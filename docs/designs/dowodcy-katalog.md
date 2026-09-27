# Katalog dowódców — krety, gibony, hieny, dziki, zające, wydry, niedźwiedzie, wilki, jeże

Uzupełnienie projektu [dowodcy-ras.md](dowodcy-ras.md) (2026-09-25). **Propozycje do przejrzenia**, nie decyzje:
każdy dowódca to specjalizacja klasy z WebSlashera przełożona na lane-pushera — 3 umiejętności z typów efektów
(tabela R1 w projekcie) + opis postaci na mapie. Liczby celowo pominięte (strojenie od T9, botami).
Spójne ma być lore, nie umiejętności — tam, gdzie WebSlasher nie pasuje do tej gry, tłumaczenie jest luźne.

Grywalne rasy: krety, gibony, hieny, dziki, zające i wydry (D31), niedźwiedzie, wilki i jeże (D32); przeciwnik losowany przy starcie partii, więc każdy dowódca
bywa też bossem rywala (R8).

## Nowe typy efektów potrzebne w katalogu

R1 w projekcie ma 9 typów (`strike`, `summon_units`, `global`, `zone`, `summon_building`, `buff`, `line`,
`execute`, `demolish`). Katalog dokłada:

| Typ | Co robi | Kto używa | Uwagi |
|---|---|---|---|
| `burrow` | armia na wskazanej ścieżce schodzi pod ziemię na N s: nietykalna, szybsza, wynurza się ze wstrząsem | krety (rasowa) | stan „pod ziemią” musi szanować celowanie wież, jednostek i pocisków |
| `raise_dead` | wrogowie ginący w promieniu przez N s wstają jako Twoje jednostki | Nekromanta | limit populacji (`unit_cap`) obowiązuje |
| `weaken` | wrogowie w obszarze dostają +X% obrażeń przez N s | Rechot, Nekromanta | status jak spowolnienie mrozu |
| `pull` | przyciąga najsilniejszego wroga w obszarze do dowódcy | Żelazny Chwyt | bossy i Wódz: tylko krótko albo odporni |
| `taunt` | wrogowie w promieniu atakują dowódcę przez N s | Żelazny Chwyt | wymaga, by dowódca był celem (uwaga R2-1) |
| `repel` | odrzuca wrogów w obszarze/wzdłuż linii (cofa ich `s` na ścieżce) | Niszczyciel, Stratowanie, Odpychacz | na ścieżce = cofnięcie o X px |
| `leap` | dowódca skacze do punktu w zasięgu, uderzając przy lądowaniu | Rechot, Stratowanie | ruch poza trasą A* — tylko na ląd |
| `bounty_buff` | przez N s zabójstwa dają +X% złota | hieny (rasowa) | ekonomia z padliny (pomysł z projektu 12.09) |

Warianty bez nowego kodu: `buff` z parametrem statystyki (`dmg`, `speed`, `attack_speed`, `armor`, `lifesteal`),
`summon_building` z typem budowli (wieżyczka, totem pulsu, odpychacz, wulkan, wiertło) — budowle tymczasowe (R7)
dopisane do `Cfg.BUILDINGS` z flagą `temporary`.

**Ile umiejętności stoi na danym typie** (40 = 12 dowódców × 3 + 4 rasowe): `buff` 8 · `strike` 7 ·
`summon_building` 5 · `zone` 3 · po 2: `execute`, `demolish`, `weaken`, `leap`, `summon_units` · po 1: `line`,
`repel`, `pull`, `taunt`, `raise_dead`, `bounty_buff`, `burrow`. Najpierw warto zrobić te z góry listy.

## Krety — „Inżynierowie podziemi”

**Umiejętność rasy — Podkop** (`burrow`, rozstrzygnięte: efekt dla całej armii): jednostki na wskazanej ścieżce
schodzą pod ziemię, omijają wieże, wynurzają się ze wstrząsem (przejmuje „trzęsienie” Sapera).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Saper** (SAPPER) | kontrola ścieżki pułapkami | **Pole minowe** (`zone`, mina) · **Wiertło-wieżyczka** (`summon_building`) · **Ładunek burzący** (`demolish`) | wręcz, kilof; średnie HP |
| **Snajper** (SNIPER) | zabija grube cele z daleka | **Strzał snajperski** (`execute`) · **Przebicie** (`line`, railshot) · **Ostrzał** (`strike` — dzisiejszy Deszcz strzał) | dystansowa, najdłuższy zasięg, trafia latających; niskie HP |
| **Magma** (MAGMA) | obszarowe obrażenia w czasie | **Pocisk magmy** (`strike`, jedna salwa) · **Kałuża lawy** (`zone`, obrażenia co sekundę) · **Wulkan** (`summon_building`, wybucha co kilka sekund) | dystansowa, średni zasięg |

## Gibony — kopia goryli z WebSlashera

**Umiejętność rasy — Pieśń** (`buff` globalny: cała armia +prędkość i +obrażenia na N s; gibony słyną ze śpiewu).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Żelazny Chwyt** (IRON GRIP) | tank, łapie i trzyma wrogów | **Chwyt** (`pull`) · **Ryk wojenny** (`taunt`) · **Uderzenie o ziemię** (`strike` z krótkim ogłuszeniem) | wręcz, najwyższe HP, pancerz |
| **Niszczyciel** (WRECKER — w WebSlasherze tylko pasywny: siła, odrzut) | burzy wieże, rozbija szyki | **Taran** (`demolish`) · **Fala uderzeniowa** (`repel` wzdłuż linii) · **Zamach** (`strike` wokół siebie) | wręcz; wyjątek od R4 — budynki bije w pełni |
| **Bojowy Rytm** (WARBEAT — w WebSlasherze „Wkrótce”, do wymyślenia) | wsparcie armii bębnami | **Werble** (`buff` szybkości ataku w promieniu) · **Rytm marszu** (`buff` prędkości na ścieżce) · **Grzmot** (`strike` z ogłuszeniem) | wręcz, słaba; aura +obrażenia dla jednostek obok |

## Hieny — „Śmieją się z rannych”

**Umiejętność rasy — Padlina** (`bounty_buff`): przez N s zabójstwa dają więcej złota — hieny żyją z cudzej walki.

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Nekromanta** (NECROMANCER — „wrogowie ginący obok wstają i walczą dla Ciebie”) | zamienia fale wroga we własną armię | **Wskrzeszenie** (`raise_dead`) · **Zew grobu** (`summon_units`) · **Klątwa** (`weaken` w obszarze) | dystansowa, słaba; trzyma się z tyłu |
| **Padlinożerca** (SCAVENGER — w WebSlasherze pasywny: siła, wysysanie życia) | dobija rannych, żyje z zabójstw | **Uczta** (`buff` wysysania życia w promieniu) · **Dobicie** (`execute`) · **Rozszarpanie** (`strike` wokół siebie) | wręcz; leczy się z zabójstw |
| **Rechot** (CACKLE) | szybki zabójca, osłabia hordę | **Skok** (`leap`) · **Rechot** (`weaken` 360° + obrażenia) · **Szał żerowania** (`buff` szybkości ataku) | wręcz, najszybsza |

## Dziki — „Pełen gaz. Bez hamulców.”

**Umiejętność rasy — Szarża** (`buff` na ścieżkę: jednostki +prędkość i odrzut przy pierwszym trafieniu na N s).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Inżynier Totemów** (TOTEM ENGINEER) | stawia tymczasowe totemy | **Totem-wieżyczka** (`summon_building`) · **Totem pulsu** (`summon_building` z aurą: leczy swoich co kilka sekund) · **Odpychacz** (`summon_building`, `repel` wokół) | wręcz, średnia |
| **Stratowanie** (STAMPEDE — w WebSlasherze pasywny: odrzut, HP) | przełamuje linie wroga | **Szarża dowódcy** (`leap` z `repel` przy lądowaniu) · **Tabun** (`summon_units`: krótko żyjące dziki biegną ścieżką) · **Twarda skóra** (`buff` pancerza w promieniu) | wręcz, tank |
| **Kły** (TUSKS — w WebSlasherze „Wkrótce”, do wymyślenia) | czyste obrażenia wręcz | **Rozpruwacz** (`strike` wokół siebie) · **Kolce w ziemi** (`zone`: spowolnienie + obrażenia) · **Furia odyńca** (`buff` dowódcy: więcej obrażeń przy niskim HP) | wręcz, najwięcej obrażeń |

## Do rozstrzygnięcia

- **Zakres implementacji:** projekt obejmuje 6 dowódców (krety, gibony). Hieny i dziki są już grywalne (tożsamość),
  ale ich 6 dowódców i 3 nowe typy (`raise_dead`, `bounty_buff`, szarża) to osobny etap — do ustalenia w `/plan-eng-review`.
- **„Weteran”** (dzisiejsze umiejętności, R10) pokrywa rasy, których dowódcy jeszcze nie istnieją — dotyczy teraz 3 ras.
- **Pieśń (gibony) i Szarża (dziki)** to oba `buff` armii — różnica: Pieśń globalnie i krócej, Szarża na jedną ścieżkę z odrzutem.
- **Bojowy Rytm i Kły** nie istnieją w WebSlasherze — wymyślone tutaj; jeśli spodobają się, mogą wrócić do WebSlashera.

## Zające — „Za szybkie, żeby zginąć. Zazwyczaj.” (D31, 2026-09-27)

**Umiejętność rasy — Kicanie** (`buff` całej armii: +70% szybkości na 6 s — mocniej i krócej niż Pieśń gibonów).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Skoczek** (SLIPSTREAM) | wskakuje w hordę i rozbija ją falą | **Skok bojowy** (`leap`) · **Nova** (`strike` wokół siebie z ogłuszeniem) · **Wiatr w nogach** (`buff` szybkości ataku dowódcy) | wręcz, najszybszy; sci-fi — buty odrzutowe, dwa sztylety |
| **Przywoływacz** (SUMMONER) | przywołańce walczą za niego | **Behemot** (`summon_units`: jeden Ogr na 25 s) · **Hydra** (`summon_building`, strzela) · **Rój** (`summon_units`: 6 Goblinów na 12 s) | dystansowa, słaba; fantasy — druid z kosturem |
| **Mistrz Aur** (AURA MASTER) | ruchoma stacja wzmocnień | **Kojenie** (`heal` w obszarze) · **Osłona** (`buff` pancerza) · **Blask** (`strike` wokół siebie) | wręcz; sci-fi — nadajnik z trzema kulami aur |

## Wydry — „Trzymają drużynę przy życiu.” (D31, 2026-09-27)

**Umiejętność rasy — Przypływ** (nowy typ `heal`: cała armia i dowódca odzyskują 30% HP).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Pani Przypływu** (TIDECALLER) | fala i wir trzymają wroga z dala | **Fala** (`repel` wzdłuż linii) · **Wir** (`zone`: obrażenia co sekundę + spowolnienie) · **Straż przypływu** (`buff` pancerza) | dystansowa; fantasy — korona z koralowca, kostur z kulą wody |
| **Lustrzany Nurt** (MIRROR TIDE) | zabójca z klonami | **Lustrzana włócznia** (`line`) · **Tysiąc luster** (`summon_units`: 3 klony na 12 s) · **Przemoczenie** (`weaken` — SOAKED z WebSlashera) | wręcz, dużo obrażeń; sci-fi — kombinezon nurka, hologram |
| **Figlarz** (PLAYFUL) | krótkie odnowienia, odbija wrogów | **Kaczki** (`strike`, 2 salwy) · **Fikołek** (`leap` z odrzutem) · **Klaps ogonem** (`repel`) | wręcz, wytrzymały; fantasy — bandana, wiosło, tarcza z muszli |

## Niedźwiedzie — „Wielkie. Wściekłe. Wszystko przyjmą na klatę.” (D32, 2026-09-27)

**Umiejętność rasy — Gęste futro** (`buff` pancerza całej armii na 8 s).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Grawitant** (GRAVITY MAGE) | pola grawitacji zatrzymują hordę | **Pole wstrząsów** (`zone`) · **Zapaść** (`strike` z ogłuszeniem) · **Pole grawitacji** (`zone`, mocne spowolnienie) | dystansowa, rzuca głazami; sci-fi — rękawice z osobliwościami |
| **Szał** (RAMPAGE) | berserker, żyje z zadanych ran | **Zamach łapą** (`strike` wokół siebie) · **Żądza krwi** (`buff` wysysania + obrażeń) · **Taranowanie** (`leap` z odrzutem) | wręcz; fantasy — skóry, malunki, topór |
| **Kolos** (HIBERNATION) | tank, który śpi i wraca silniejszy | **Sen zimowy** (`heal` wokół siebie) · **Tąpnięcie** (`strike` z ogłuszeniem) · **Kolos** (`buff` pancerza + obrażeń) | wręcz, najwięcej HP; sci-fi — egzoszkielet pod kopułą |

## Wilki — „Szybkie ciosy, instynkt stada.” (D32, 2026-09-27)

**Umiejętność rasy — Zew watahy** (`buff` szybkości ataku całej armii na 8 s).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Grom** (THUNDER FANG — w WebSlasherze combo Q/W/E) | błyskawice przez całe szeregi | **Łańcuch burzy** (`line`) · **Nova gromu** (`strike`, 3 salwy) · **Błyskawiczny zryw** (`leap`) | wręcz; sci-fi — cewki Tesli |
| **Alfa** (ALPHA PACK) | prowadzi watahę | **Cios watahy** (`strike` wokół siebie) · **Furia watahy** (`buff` obrażeń w obszarze) · **Zew wilków** (`summon_units` na 20 s) | wręcz; fantasy — hełm z czaszki basiora |
| **Wilkołak** (HOWL) | samotny berserker | **Wypad** (`leap`) · **Dzikie wycie** (`weaken` wokół siebie) · **Przemiana** (`buff` szybkości ataku + obrażeń) | wręcz, najszybszy; fantasy — bestia |

## Jeże — „Dotknij, a pożałujesz.” (D32, 2026-09-27)

**Umiejętność rasy — Najeżenie** (`buff` kolców całej armii: połowa obrażeń z ciosu wręcz wraca do atakującego).

| Dowódca (WebSlasher) | Rola | Umiejętności | Postać |
|---|---|---|---|
| **Sonik** (SONIC) | rozpędzona kula kolców | **Toczenie** (`repel` wzdłuż linii) · **Wirujące kolce** (`strike` wokół siebie) · **Rozpęd** (`buff` szybkości + obrażeń) | wręcz, najszybszy z jeży; sci-fi — buty z odrzutem |
| **Kłębek** (CURL) | tank — dotknij, a pożałujesz | **Nova kolców** (`strike`) · **Żelazny kłębek** (`buff` pancerza + kolców) · **Prowokacja** (`taunt`) | wręcz, dużo HP; fantasy — rycerz z tarczą |
| **Bastion** (BASTION) | pułapka na hordę | **Działko** (`summon_building`) · **Mur kolców** (`zone`: spowolnienie + obrażenia) · **Podkręcenie** (`buff` szybkości ataku) | dystansowa; sci-fi — inżynier z dronem |
