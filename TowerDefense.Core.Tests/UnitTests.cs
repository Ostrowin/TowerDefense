using System.Numerics;
using Xunit;
using static TowerDefense.Core.Tests.TestHelpers;

namespace TowerDefense.Core.Tests;

public class UnitTests
{
    private static Unit MakeUnit(Vector2[] waypoints, float speed = 5f, int hp = 10) =>
        new(id: 1, owner: Side.Player, spec: new UnitSpec(speed, Damage: 1, Hp: hp), waypoints: waypoints);

    [Fact]
    public void Unit_WalksPath_AndReachesEnd()
    {
        var unit = MakeUnit(ShortLane);

        for (int i = 0; i < 180; i++)
            unit.Update(FixedDt);

        Assert.True(unit.ReachedEnd);
        Assert.Equal(new Vector2(10, 0), unit.Position);
    }

    [Fact]
    public void Unit_WalksPath_AndHasNotReachedEnd()
    {
        var unit = MakeUnit(ShortLane);

        for (int i = 0; i < 30; i++)
            unit.Update(FixedDt);

        Assert.False(unit.ReachedEnd);
        Assert.True(unit.Position.X > 0f);
    }

    [Fact]
    public void Unit_CarriesLeftoverStep_AroundCorner()
    {
        // krok 2 j.: 1 do zakrętu (1,0) + 1 w dół → (1,1)
        var unit = MakeUnit(new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 10) }, speed: 2f);

        unit.Update(1f);

        Assert.Equal(new Vector2(1, 1), unit.Position);
        Assert.Equal(2f, unit.PathProgress);
        Assert.Equal(new Vector2(0, 0), unit.PreviousPosition);
    }

    [Fact]
    public void Unit_EmptyWaypoints_Throws()
    {
        Assert.Throws<ArgumentException>(() => MakeUnit(Array.Empty<Vector2>()));
    }

    [Fact]
    public void Unit_SingleWaypoint_IsAlreadyAtEnd()
    {
        var unit = MakeUnit(new[] { new Vector2(3, 3) });
        unit.Update(FixedDt);

        Assert.True(unit.ReachedEnd);
        Assert.Equal(new Vector2(3, 3), unit.Position);
    }

    [Fact]
    public void DeadUnit_DoesNotMove()
    {
        var unit = MakeUnit(ShortLane);
        unit.TakeDamage(100);
        unit.Update(1f);

        Assert.True(unit.IsDead);
        Assert.Equal(0, unit.Hp);
        Assert.Equal(Vector2.Zero, unit.Position);
    }

    [Fact]
    public void TakeDamage_IgnoresNonPositive()
    {
        var unit = MakeUnit(ShortLane, hp: 10);
        unit.TakeDamage(-3);
        Assert.Equal(10, unit.Hp);
        Assert.Equal(10, unit.MaxHp);
    }
}
