using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class ProductionBuildingTests
{
    private const float FixedDt = 1f / 60f;

    [Fact]
    public void ReadyToSpawn_FiresOncePerInterval()
    {
        var path = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        var building = new ProductionBuilding(spawnInterval: 1f, cost: 10, unitSpeed: 5f, unitDamage: 10, path: path);

        int spawns = 0;
        for (int i = 0; i < 210; i++)      // 3.5 sekundy
            if (building.ReadyToSpawn(FixedDt)) spawns++;

        Assert.Equal(3, spawns);              // 3 s / 1 s interwał = 3 spawny
    }

    [Fact]
    public void ProductionBuilding_SpawnsUnitsOverTime_AndDestroysBase()
    {
        var enemyBase = new EnemyBase(id: 1, hp: 30);
        var sim = new SimState(enemyBase);
        sim.AddResources(10000);

        var path = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        // co 5 s produkuje jednostkę 10 dmg — w 60 s z zapasem starczy na 30 HP
        sim.Buildings.Add(new ProductionBuilding(spawnInterval: 5f, cost: 10, unitSpeed: 5f, unitDamage: 10, path: path));

        for (int i = 0; i < 60 * 60; i++)     // 60 s, ZERO ręcznie wstawianych jednostek
            sim.Tick(FixedDt);

        Assert.True(sim.IsWon);
    }
}
