using System.Numerics;
using Xunit;
using static TowerDefense.Core.Tests.TestHelpers;

namespace TowerDefense.Core.Tests;

public class TowerTests
{
    private static Unit EnemyAt(Vector2 position, int hp = 10) =>
        new(id: 1, owner: Side.Enemy, spec: new UnitSpec(0f, 5, hp), waypoints: new[] { position });

    [Fact]
    public void Tower_ShootsUnitInRange_UntilItDies()
    {
        var tower = new Tower(id: 1, owner: Side.Player, position: Vector2.Zero, range: 5f, damage: 10, fireInterval: 1f);
        var unit = EnemyAt(new Vector2(1, 0), hp: 25);
        var units = new List<Unit> { unit };

        for (int i = 0; i < 60 * 5; i++)   // 5 s z zapasem (strzał co 1 s, 10 dmg, 25 HP → 3 strzały)
        {
            tower.Update(FixedDt);
            tower.TryFire(units);
        }

        Assert.True(unit.IsDead);
    }

    [Fact]
    public void Tower_RespectsCooldown()
    {
        var tower = new Tower(id: 1, owner: Side.Player, position: Vector2.Zero, range: 5f, damage: 1, fireInterval: 1f);
        var unit = EnemyAt(new Vector2(1, 0), hp: 100);
        var units = new List<Unit> { unit };

        // dt = 0.5 (dokładne we floatach): strzały w tickach 1, 3, 5
        for (int i = 0; i < 5; i++)
        {
            tower.Update(0.5f);
            tower.TryFire(units);
        }

        Assert.Equal(97, unit.Hp);
    }

    [Fact]
    public void Tower_TargetsUnitFurthestAlongPath()
    {
        var lane = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        var behind = new Unit(id: 1, owner: Side.Enemy, spec: new UnitSpec(1f, 1, 10), waypoints: lane);
        var ahead = new Unit(id: 2, owner: Side.Enemy, spec: new UnitSpec(1f, 1, 10), waypoints: lane);
        behind.Update(1f);                      // (1,0)
        for (int i = 0; i < 3; i++) ahead.Update(1f);   // (3,0)

        var tower = new Tower(id: 3, owner: Side.Player, position: new Vector2(2, 0), range: 5f, damage: 1, fireInterval: 1f);

        Assert.Same(ahead, tower.SelectTarget(new List<Unit> { behind, ahead }));
    }

    [Fact]
    public void Tower_IgnoresOwnSide_OutOfRange_AndDead()
    {
        var tower = new Tower(id: 1, owner: Side.Player, position: Vector2.Zero, range: 2f, damage: 1, fireInterval: 1f);
        var friendly = new Unit(id: 2, owner: Side.Player, spec: new UnitSpec(0f, 1, 10), waypoints: new[] { new Vector2(1, 0) });
        var far = EnemyAt(new Vector2(5, 0));
        var dead = EnemyAt(new Vector2(1, 0));
        dead.TakeDamage(100);

        Assert.Null(tower.TryFire(new List<Unit> { friendly, far, dead }));
        Assert.True(tower.IsReady);             // nie strzeliła → nie weszła w cooldown
    }
}
