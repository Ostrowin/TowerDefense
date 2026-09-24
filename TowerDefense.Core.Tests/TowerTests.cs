using System.Collections.Generic;
using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class TowerTests
{
    [Fact]
    public void Tower_ShootsUnitInRange_UntilItDies()
    {
        var tower = new Tower(id: 1, position: new Vector2(0, 0), range: 5f, damage: 10, fireInterval: 1f);
        // jednostka stoi w zasięgu (nie wołamy Update, więc się nie rusza), HP 25
        var unit = new Unit(id: 1, speed: 0f, waypoints: new[] { new Vector2(1, 0) }, damage: 5, hp: 25);
        var units = new List<Unit> { unit };

        for (int i = 0; i < 60 * 5; i++)   // 5 s z zapasem (strzał co 1 s, 10 dmg, 25 HP → 3 strzały)
            tower.Update(1f / 60f, units);

        Assert.True(unit.IsDead);           // czysty boolean — bez dramy floatów przy liczeniu strzałów
    }
}