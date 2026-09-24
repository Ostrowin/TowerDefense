using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class UnitMovementTests
{
    private const float FixedDt = 1f / 60f;

    [Fact]
    public void Unit_WalksPath_AndReachesEnd()
    {
        var waypoints = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        var unit = new Unit(id: 1, speed: 5f, waypoints: waypoints, damage: 1);

        for(int i = 0; i< 180; i++)
            unit.Update(FixedDt);

        Assert.True(unit.ReachedEnd);
        Assert.Equal(new Vector2(10,0), unit.Position);
    }

    [Fact]
    public void Unit_WalksPath_AndHasNotReachesEnd()
    {
        var waypoints = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        var unit = new Unit(id: 1, speed: 5f, waypoints: waypoints, damage: 1);

        for (int i = 0; i < 30; i++)
            unit.Update(FixedDt);

        Assert.False(unit.ReachedEnd);
        Assert.True(unit.Position.X > 0f);
    }
}
