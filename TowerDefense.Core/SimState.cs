using System.Numerics;

namespace TowerDefense.Core;

public enum GameResult { Playing, Won, Lost }

public enum PlacementResult { Ok, NoGrid, OutOfBounds, Occupied, NotEnoughResources }

/// <summary>
/// Cały stan gry. Jedyne źródło ID encji (jeden licznik) i jedyne miejsce, które dodaje/usuwa encje.
///
/// Linia (lane): gracz ma bazę na Lane[0], wróg na Lane[^1].
/// Jednostki gracza idą Lane, jednostki wroga — Lane odwróconą.
///
/// Pipeline Tick(dt) — tylko gdy Result == Playing:
///   1. Workers     Update → TakeCompletedNode → nowy Extractor (gdy złoże wolne)
///   2. Extractors  Update → TakeOutput → Resources;  wyczerpane usuwane
///   3. EnemyScript TakeDue(Elapsed) → spawn jednostek wroga
///   4. Buildings   Update → TakeSpawnDue → (gracz płaci UnitCost; brak kasy = cykl przepada) → spawn
///   5. Units       Update (marsz)
///   6. Towers      Update (cooldown) → TryFire (wróg w zasięgu, najdalej na ścieżce)
///   7. Rozliczenie martwe out; ReachedEnd → dmg bazy przeciwnika, out
///   8. Wynik       baza gracza padła → Lost (ma pierwszeństwo przy remisie); baza wroga → Won
/// </summary>
public sealed class SimState
{
    private readonly List<Unit> _units = new();
    private readonly List<ProductionBuilding> _buildings = new();
    private readonly List<ResourceNode> _resourceNodes = new();
    private readonly List<Extractor> _extractors = new();
    private readonly List<Worker> _workers = new();
    private readonly List<Tower> _towers = new();
    private readonly Vector2[] _playerLane;
    private readonly Vector2[] _enemyLane;
    private readonly float _extractorRate;
    private readonly EnemyScript? _enemyScript;
    private int _nextId = 1;

    public Base PlayerBase { get; }
    public Base EnemyBase { get; }
    public Grid? Grid { get; }
    public IReadOnlyList<Vector2> Lane => _playerLane;
    public IReadOnlyList<Unit> Units => _units;
    public IReadOnlyList<ProductionBuilding> Buildings => _buildings;
    public IReadOnlyList<ResourceNode> ResourceNodes => _resourceNodes;
    public IReadOnlyList<Extractor> Extractors => _extractors;
    public IReadOnlyList<Worker> Workers => _workers;
    public IReadOnlyList<Tower> Towers => _towers;

    public int Resources { get; private set; }
    public float ElapsedSeconds { get; private set; }
    public GameResult Result { get; private set; } = GameResult.Playing;
    public bool IsWon => Result == GameResult.Won;
    public bool IsLost => Result == GameResult.Lost;

    public SimState(Vector2[] lane, int playerBaseHp, int enemyBaseHp,
                    float extractorRate = 10f, Grid? grid = null, EnemyScript? enemyScript = null)
    {
        if (lane == null || lane.Length < 2)
            throw new ArgumentException("Linia musi mieć co najmniej 2 punkty.", nameof(lane));
        _playerLane = lane.ToArray();
        _enemyLane = lane.Reverse().ToArray();
        _extractorRate = extractorRate;
        _enemyScript = enemyScript;
        Grid = grid;
        PlayerBase = new Base(NextId(), Side.Player, _playerLane[0], playerBaseHp);
        EnemyBase = new Base(NextId(), Side.Enemy, _playerLane[^1], enemyBaseHp);
    }

    private int NextId() => _nextId++;

    // ── Tworzenie encji (jedyna droga — ID zawsze z licznika) ─────────────────

    public void AddResources(int amount)
    {
        if (amount <= 0) return;
        Resources += amount;
    }

    public ResourceNode AddResourceNode(Vector2 position, int amount)
    {
        var node = new ResourceNode(NextId(), position, amount);
        _resourceNodes.Add(node);
        return node;
    }

    public Worker AddWorker(Vector2 position, float speed, float buildTime)
    {
        var worker = new Worker(NextId(), position, speed, buildTime);
        _workers.Add(worker);
        return worker;
    }

    public Tower AddTower(Side owner, Vector2 position, float range, int damage, float fireInterval)
    {
        var tower = new Tower(NextId(), owner, position, range, damage, fireInterval);
        _towers.Add(tower);
        return tower;
    }

    /// <summary>Budynek bez siatki i bez kosztu — do ustawienia poziomu i testów.</summary>
    public ProductionBuilding AddBuilding(Side owner, Vector2 position, ProductionBuildingSpec spec)
    {
        var building = new ProductionBuilding(NextId(), owner, position, spec);
        _buildings.Add(building);
        return building;
    }

    /// <summary>Budowa gracza na siatce: sprawdza granice, zajętość i koszt.</summary>
    public PlacementResult TryPlaceBuilding(GridCell cell, ProductionBuildingSpec spec, out ProductionBuilding? building)
    {
        building = null;
        if (Grid == null) return PlacementResult.NoGrid;
        if (!Grid.InBounds(cell)) return PlacementResult.OutOfBounds;
        if (Grid.IsOccupied(cell)) return PlacementResult.Occupied;
        if (Resources < spec.BuildCost) return PlacementResult.NotEnoughResources;

        Resources -= spec.BuildCost;
        Grid.Occupy(cell);
        building = AddBuilding(Side.Player, Grid.CellCenter(cell), spec);
        return PlacementResult.Ok;
    }

    public Unit SpawnUnit(Side owner, UnitSpec spec)
    {
        var unit = new Unit(NextId(), owner, spec, owner == Side.Player ? _playerLane : _enemyLane);
        _units.Add(unit);
        return unit;
    }

    /// <summary>Rozkaz budowy wydobywacza. False, gdy złoże puste albo już ma wydobywacz.</summary>
    public bool TryOrderBuild(Worker worker, ResourceNode node)
    {
        if (node.IsEmpty || node.HasExtractor) return false;
        worker.OrderBuildOn(node);
        return true;
    }

    public Base BaseOf(Side side) => side == Side.Player ? PlayerBase : EnemyBase;

    // ── Krok symulacji ────────────────────────────────────────────────────────

    public void Tick(float fixedDt)
    {
        if (Result != GameResult.Playing) return;
        ElapsedSeconds += fixedDt;

        // 1. Robotnicy
        foreach (var worker in _workers)
        {
            worker.Update(fixedDt);
            ResourceNode? built = worker.TakeCompletedNode();
            // Dwóch robotników na tym samym złożu: wygrywa pierwszy, drugi budował na darmo.
            if (built != null && !built.HasExtractor)
                _extractors.Add(new Extractor(NextId(), built, _extractorRate));
        }

        // 2. Dochód (przed produkcją, by można go wydać w tym samym ticku)
        foreach (var extractor in _extractors)
        {
            extractor.Update(fixedDt);
            AddResources(extractor.TakeOutput());
        }
        _extractors.RemoveAll(e => e.IsDepleted);

        // 3. Skryptowany wróg
        if (_enemyScript != null)
            foreach (var spec in _enemyScript.TakeDue(ElapsedSeconds))
                SpawnUnit(Side.Enemy, spec);

        // 4. Produkcja
        foreach (var building in _buildings)
        {
            building.Update(fixedDt);
            while (building.TakeSpawnDue())
            {
                if (building.Owner == Side.Player)
                {
                    if (Resources < building.Spec.UnitCost) continue;   // cykl przepada
                    Resources -= building.Spec.UnitCost;
                }
                SpawnUnit(building.Owner, building.Spec.Unit);
            }
        }

        // 5. Ruch
        foreach (var unit in _units)
            unit.Update(fixedDt);

        // 6. Walka
        foreach (var tower in _towers)
        {
            tower.Update(fixedDt);
            tower.TryFire(_units);
        }

        // 7. Rozliczenie: martwe NIE biją bazy
        for (int i = _units.Count - 1; i >= 0; i--)
        {
            Unit unit = _units[i];
            if (unit.IsDead)
                _units.RemoveAt(i);
            else if (unit.ReachedEnd)
            {
                BaseOf(unit.Owner.Opponent()).TakeDamage(unit.Damage);
                _units.RemoveAt(i);
            }
        }

        // 8. Wynik
        if (PlayerBase.IsDestroyed) Result = GameResult.Lost;
        else if (EnemyBase.IsDestroyed) Result = GameResult.Won;
    }
}
