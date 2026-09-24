using System.Numerics;
using Xunit;
using static TowerDefense.Core.Tests.TestHelpers;

namespace TowerDefense.Core.Tests;

public class SimStateTests
{
    private static readonly UnitSpec Soldier = new(Speed: 5f, Damage: 10, Hp: 10);

    // ── Marsz i wygrana (T2: 60 s headless) ──────────────────────────────────

    [Fact]
    public void Sim_UnitsReachBase_DestroyIt_AndWin()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 100, enemyBaseHp: 30);
        for (int i = 0; i < 3; i++)
            sim.SpawnUnit(Side.Player, Soldier);

        Run(sim, seconds: 60);

        Assert.True(sim.IsWon);
        Assert.True(sim.EnemyBase.IsDestroyed);
        Assert.Empty(sim.Units);            // wszystkie jednostki „skonsumowane" po dojściu
    }

    [Fact]
    public void Sim_UnitsDealTooLittleDamage_BaseSurvives_NoWin()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 100, enemyBaseHp: 30);
        for (int i = 0; i < 3; i++)
            sim.SpawnUnit(Side.Player, Soldier with { Damage = 1 });

        Run(sim, seconds: 60);

        Assert.Equal(GameResult.Playing, sim.Result);
        Assert.Equal(27, sim.EnemyBase.Hp);
        Assert.Empty(sim.Units);
    }

    [Fact]
    public void Bases_SitAtLaneEnds_AndEnemyWalksReversedLane()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 10, enemyBaseHp: 10);
        var enemy = sim.SpawnUnit(Side.Enemy, Soldier);

        Assert.Equal(new Vector2(0, 0), sim.PlayerBase.Position);
        Assert.Equal(new Vector2(10, 0), sim.EnemyBase.Position);
        Assert.Equal(new Vector2(10, 0), enemy.Position);
        Assert.Same(sim.PlayerBase, sim.BaseOf(Side.Player));
        Assert.Same(sim.EnemyBase, sim.BaseOf(Side.Enemy));
    }

    [Fact]
    public void Lane_WithFewerThanTwoPoints_Throws()
    {
        Assert.Throws<ArgumentException>(() => new SimState(new[] { Vector2.Zero }, 10, 10));
    }

    // ── Ekonomia ─────────────────────────────────────────────────────────────

    [Fact]
    public void Production_SpawnsUnitsOverTime_AndDestroysBase()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 100, enemyBaseHp: 30);
        sim.AddResources(10000);
        sim.AddBuilding(Side.Player, Vector2.Zero, Barracks(spawnInterval: 5f));

        Run(sim, seconds: 60);

        Assert.True(sim.IsWon);
    }

    [Fact]
    public void Production_StopsWhenOutOfResources()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 100, enemyBaseHp: 1000);
        sim.AddResources(20);                              // DOKŁADNIE na 2 jednostki po 10
        sim.AddBuilding(Side.Player, Vector2.Zero, Barracks(spawnInterval: 1f, unitCost: 10, unitDamage: 5));

        Run(sim, seconds: 30);

        Assert.Equal(0, sim.Resources);
        Assert.Equal(990, sim.EnemyBase.Hp);               // 2 × 5 dmg
    }

    [Fact]
    public void AddResources_IgnoresNonPositive()
    {
        var sim = new SimState(ShortLane, 10, 10);
        sim.AddResources(0);
        sim.AddResources(-5);
        Assert.Equal(0, sim.Resources);
    }

    [Fact]
    public void Worker_BuildsExtractor_WhichFundsProduction_ToWin()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 100, enemyBaseHp: 30, extractorRate: 20f);
        var node = sim.AddResourceNode(new Vector2(0, 5), amount: 1000);
        var worker = sim.AddWorker(Vector2.Zero, speed: 5f, buildTime: 2f);
        sim.AddBuilding(Side.Player, Vector2.Zero, Barracks(spawnInterval: 2f));

        Assert.True(sim.TryOrderBuild(worker, node));      // ROZKAZ GRACZA — jedyne „kliknięcie"
        Run(sim, seconds: 60);

        Assert.True(sim.IsWon);
        Assert.Single(sim.Extractors);
    }

    [Fact]
    public void TryOrderBuild_RejectsNodeWithExtractor_OrEmpty()
    {
        var sim = new SimState(ShortLane, 10, 10);
        var node = sim.AddResourceNode(Vector2.Zero, amount: 1000);
        var empty = sim.AddResourceNode(new Vector2(1, 0), amount: 0);
        var worker = sim.AddWorker(Vector2.Zero, speed: 5f, buildTime: 0.5f);

        Assert.False(sim.TryOrderBuild(worker, empty));
        Assert.True(sim.TryOrderBuild(worker, node));
        Run(sim, seconds: 1);

        Assert.False(sim.TryOrderBuild(worker, node));
        Assert.Equal(WorkerState.Idle, worker.State);
    }

    [Fact]
    public void TwoWorkers_OnSameNode_BuildOnlyOneExtractor()
    {
        var sim = new SimState(ShortLane, 10, 10);
        var node = sim.AddResourceNode(Vector2.Zero, amount: 1000);
        var a = sim.AddWorker(Vector2.Zero, speed: 5f, buildTime: 1f);
        var b = sim.AddWorker(Vector2.Zero, speed: 5f, buildTime: 1f);

        Assert.True(sim.TryOrderBuild(a, node));
        Assert.True(sim.TryOrderBuild(b, node));           // obaj ruszyli, zanim cokolwiek stanęło
        Run(sim, seconds: 2);

        Assert.Single(sim.Extractors);
    }

    [Fact]
    public void DepletedExtractor_IsRemoved()
    {
        var sim = new SimState(ShortLane, 10, 10, extractorRate: 10f);
        var node = sim.AddResourceNode(Vector2.Zero, amount: 5);
        var worker = sim.AddWorker(Vector2.Zero, speed: 5f, buildTime: 0.1f);
        sim.TryOrderBuild(worker, node);

        Run(sim, seconds: 3);

        Assert.Equal(5, sim.Resources);
        Assert.Empty(sim.Extractors);
    }

    // ── Budowa na siatce ─────────────────────────────────────────────────────

    private static SimState SimWithGrid() =>
        new(ShortLane, 10, 10, grid: new Grid(new Vector2(0, 2), width: 2, height: 1, cellSize: 2f));

    [Fact]
    public void TryPlaceBuilding_Ok_PaysAndOccupiesCell()
    {
        var sim = SimWithGrid();
        sim.AddResources(60);

        var result = sim.TryPlaceBuilding(new GridCell(1, 0), Barracks(buildCost: 50), out var building);

        Assert.Equal(PlacementResult.Ok, result);
        Assert.Equal(10, sim.Resources);
        Assert.Equal(new Vector2(3, 3), building!.Position);
        Assert.True(sim.Grid!.IsOccupied(new GridCell(1, 0)));
        Assert.Single(sim.Buildings);
    }

    [Fact]
    public void TryPlaceBuilding_Rejections_CostNothing()
    {
        var sim = SimWithGrid();
        sim.AddResources(60);
        sim.TryPlaceBuilding(new GridCell(0, 0), Barracks(buildCost: 50), out _);   // zostaje 10

        Assert.Equal(PlacementResult.Occupied, sim.TryPlaceBuilding(new GridCell(0, 0), Barracks(buildCost: 1), out _));
        Assert.Equal(PlacementResult.OutOfBounds, sim.TryPlaceBuilding(new GridCell(5, 0), Barracks(buildCost: 1), out _));
        Assert.Equal(PlacementResult.NotEnoughResources, sim.TryPlaceBuilding(new GridCell(1, 0), Barracks(buildCost: 50), out var none));
        Assert.Null(none);
        Assert.Equal(10, sim.Resources);
        Assert.Single(sim.Buildings);
    }

    [Fact]
    public void TryPlaceBuilding_WithoutGrid_ReturnsNoGrid()
    {
        var sim = new SimState(ShortLane, 10, 10);
        sim.AddResources(100);
        Assert.Equal(PlacementResult.NoGrid, sim.TryPlaceBuilding(new GridCell(0, 0), Barracks(), out _));
    }

    // ── Walka, wróg, wynik ───────────────────────────────────────────────────

    [Fact]
    public void Tower_KillsMarchingUnits_BeforeReachingBase()
    {
        var lane = new[] { new Vector2(0, 0), new Vector2(20, 0) };
        var sim = new SimState(lane, playerBaseHp: 100, enemyBaseHp: 100);
        sim.AddResources(1000);
        sim.AddBuilding(Side.Player, Vector2.Zero, Barracks(spawnInterval: 2f, unitSpeed: 3f));
        sim.AddTower(Side.Enemy, new Vector2(10, 0), range: 3f, damage: 100, fireInterval: 0.5f);

        Run(sim, seconds: 60);

        Assert.Equal(100, sim.EnemyBase.Hp);
    }

    [Fact]
    public void EnemyScript_UnitsDestroyPlayerBase_Lost()
    {
        var script = EnemyScript.Repeating(start: 1f, interval: 1f, count: 3, unit: Soldier);
        var sim = new SimState(ShortLane, playerBaseHp: 30, enemyBaseHp: 100, enemyScript: script);

        Run(sim, seconds: 60);

        Assert.True(sim.IsLost);
        Assert.False(sim.IsWon);
    }

    [Fact]
    public void SimultaneousBaseKills_CountAsLoss()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 10, enemyBaseHp: 10);
        sim.SpawnUnit(Side.Player, Soldier);
        sim.SpawnUnit(Side.Enemy, Soldier);

        Run(sim, seconds: 5);

        Assert.True(sim.PlayerBase.IsDestroyed);
        Assert.True(sim.EnemyBase.IsDestroyed);
        Assert.Equal(GameResult.Lost, sim.Result);
    }

    [Fact]
    public void Tick_AfterGameOver_FreezesSim()
    {
        var sim = new SimState(ShortLane, playerBaseHp: 100, enemyBaseHp: 10);
        sim.SpawnUnit(Side.Player, Soldier);
        Run(sim, seconds: 5);
        float endTime = sim.ElapsedSeconds;
        sim.SpawnUnit(Side.Player, Soldier);

        Run(sim, seconds: 5);

        Assert.True(sim.IsWon);
        Assert.Equal(endTime, sim.ElapsedSeconds);
        Assert.Equal(Vector2.Zero, sim.Units[0].Position);  // nowa jednostka nie ruszyła
    }

    [Fact]
    public void TwoWayBattle_PlayerDefendsAndWins()   // M1b w pigułce
    {
        var lane = new[] { new Vector2(0, 0), new Vector2(20, 0) };
        var script = EnemyScript.Repeating(start: 1f, interval: 2f, count: 20, unit: new UnitSpec(3f, 10, 10));
        var sim = new SimState(lane, playerBaseHp: 50, enemyBaseHp: 50, enemyScript: script);
        sim.AddResources(1000);
        sim.AddBuilding(Side.Player, Vector2.Zero, Barracks(spawnInterval: 1f, unitHp: 30));
        sim.AddTower(Side.Player, new Vector2(4, 0), range: 3f, damage: 100, fireInterval: 0.3f);
        sim.AddTower(Side.Enemy, new Vector2(16, 0), range: 3f, damage: 5, fireInterval: 1f);

        Run(sim, seconds: 60);

        Assert.True(sim.IsWon);
        Assert.Equal(sim.PlayerBase.MaxHp, sim.PlayerBase.Hp);   // wieża gracza nie przepuściła nikogo
    }

    [Fact]
    public void EveryEntity_GetsUniqueId()
    {
        var sim = new SimState(ShortLane, 10, 10);
        var ids = new List<int> { sim.PlayerBase.Id, sim.EnemyBase.Id };
        ids.Add(sim.AddResourceNode(Vector2.Zero, 10).Id);
        ids.Add(sim.AddWorker(Vector2.Zero, 1f, 1f).Id);
        ids.Add(sim.AddTower(Side.Player, Vector2.Zero, 1f, 1, 1f).Id);
        ids.Add(sim.AddBuilding(Side.Player, Vector2.Zero, Barracks()).Id);
        ids.Add(sim.SpawnUnit(Side.Player, Soldier).Id);
        var worker = sim.AddWorker(Vector2.Zero, 10f, 0.1f);
        sim.TryOrderBuild(worker, sim.ResourceNodes[0]);
        Run(sim, seconds: 0.5f);
        ids.Add(sim.Extractors[0].Id);

        Assert.Equal(ids.Count, ids.Distinct().Count());
        Assert.Single(sim.Towers);
        Assert.Equal(ShortLane, sim.Lane);
    }
}
