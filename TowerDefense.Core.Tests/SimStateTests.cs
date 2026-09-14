using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class SimStateTests
{
    private const float FixedDt = 1f / 60f;

    [Fact]
    public void Sim_UnitsReachBase_DestroyIt_AndWin()
    {
        // Arrange: baza 30 HP; 3 jednostki po 10 dmg maszerują do niej
        var enemyBase = new EnemyBase(id: 1, hp: 30);
        var sim = new SimState(enemyBase);

        var path = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        for (int i = 0; i < 3; i++)
            sim.Units.Add(new Unit(id: i, speed: 5f, waypoints: path, damage: 10));

        // Act: 60 sekund symulacji bez renderu
        for (int i = 0; i < 60 * 60; i++)   // 3600 kroków = 60 s
            sim.Tick(FixedDt);

        // Assert
        Assert.True(sim.IsWon);
        Assert.True(enemyBase.IsDestroyed);
        Assert.Empty(sim.Units);            // wszystkie jednostki „skonsumowane" po dojściu
    }

    [Fact]
    public void Sim_UnitsReachBase_DealTooLittleDamage_BaseSurvives_NoWin()
    {
        var enemyBase = new EnemyBase(id: 1, hp: 30);
        var sim = new SimState(enemyBase);

        var path = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        for (int i = 0; i < 3; i++)
            sim.Units.Add(new Unit(id: i, speed: 5f, waypoints: path, damage: 1));

        for (int i = 0; i < 60 * 60; i++)
            sim.Tick(FixedDt);

        // Assert
        Assert.False(sim.IsWon);
        Assert.False(enemyBase.IsDestroyed);
        Assert.Equal(27, enemyBase.Hp);
        Assert.Empty(sim.Units);
    }

    [Fact]
    public void Production_StopsWhenOutOfResources()
    {
        var enemyBase = new EnemyBase(id: 1, hp: 1000);   // duża — badamy ekonomię, nie wygraną
        var sim = new SimState(enemyBase);
        sim.AddResources(20);                             // starczy DOKŁADNIE na 2 jednostki po 10

        var path = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        sim.Buildings.Add(new ProductionBuilding(spawnInterval: 1f, cost: 10, unitSpeed: 5f, unitDamage: 5, path: path));

        for (int i = 0; i < 60 * 30; i++)   // 30 s — mnóstwo cykli produkcji
            sim.Tick(FixedDt);

        Assert.Equal(0, sim.Resources);      // wydał wszystko, potem stanął
        Assert.Equal(990, enemyBase.Hp);     // tylko 2 jednostki × 5 dmg = 10 dotarło (1000 - 10)
    }

    [Fact]
    public void Worker_BuildsExtractor_WhichFundsProduction_ToWin()
    {
        var enemyBase = new EnemyBase(id: 1, hp: 30);
        var sim = new SimState(enemyBase, extractorRate: 20f);

        var node = new ResourceNode(id: 1, position: new Vector2(0, 5), amount: 1000);
        var worker = new Worker(id: 1, speed: 5f, buildTime: 2f, position: new Vector2(0, 0));
        sim.Workers.Add(worker);

        var path = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        sim.Buildings.Add(new ProductionBuilding(spawnInterval: 2f, cost: 10, unitSpeed: 5f, unitDamage: 10, path: path));

        worker.OrderBuildOn(node);          // ROZKAZ GRACZA — jedyne „kliknięcie"

        for (int i = 0; i < 60 * 60; i++)   // 60 s
            sim.Tick(1f / 60f);

        Assert.True(sim.IsWon);
        Assert.Single(sim.Extractors);      // powstał dokładnie jeden wydobywacz
    }
}