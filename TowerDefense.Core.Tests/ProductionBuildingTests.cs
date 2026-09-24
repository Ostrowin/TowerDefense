using System.Numerics;
using Xunit;
using static TowerDefense.Core.Tests.TestHelpers;

namespace TowerDefense.Core.Tests;

public class ProductionBuildingTests
{
    [Fact]
    public void SpawnDue_FiresOncePerInterval()
    {
        var building = new ProductionBuilding(id: 1, owner: Side.Player, position: Vector2.Zero, spec: Barracks(spawnInterval: 1f));

        int spawns = 0;
        for (int i = 0; i < 210; i++)         // 3.5 sekundy
        {
            building.Update(FixedDt);
            if (building.TakeSpawnDue()) spawns++;
        }

        Assert.Equal(3, spawns);              // 3 s / 1 s interwał = 3 spawny
    }

    [Fact]
    public void LongStep_AccumulatesSeveralSpawns()
    {
        var building = new ProductionBuilding(id: 1, owner: Side.Player, position: Vector2.Zero, spec: Barracks(spawnInterval: 0.5f));

        building.Update(1.5f);

        Assert.True(building.TakeSpawnDue());
        Assert.True(building.TakeSpawnDue());
        Assert.True(building.TakeSpawnDue());
        Assert.False(building.TakeSpawnDue());
    }

    [Fact]
    public void NonPositiveInterval_Throws()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new ProductionBuilding(id: 1, owner: Side.Player, position: Vector2.Zero, spec: Barracks(spawnInterval: 0f)));
    }
}
