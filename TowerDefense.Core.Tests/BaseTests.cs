using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class BaseTests
{
    [Fact]
    public void TakeDamage_ReducesHp_AndClampsAtZero()
    {
        var enemyBase = new Base(id: 1, owner: Side.Enemy, position: Vector2.Zero, hp: 100);

        enemyBase.TakeDamage(30);
        Assert.Equal(70, enemyBase.Hp);
        Assert.Equal(100, enemyBase.MaxHp);
        Assert.Equal(Side.Enemy, enemyBase.Owner);
        Assert.False(enemyBase.IsDestroyed);

        enemyBase.TakeDamage(1000);
        Assert.Equal(0, enemyBase.Hp);
        Assert.True(enemyBase.IsDestroyed);
    }

    [Fact]
    public void TakeDamage_IgnoresNonPositive()
    {
        var b = new Base(id: 1, owner: Side.Player, position: Vector2.Zero, hp: 10);
        b.TakeDamage(0);
        b.TakeDamage(-5);
        Assert.Equal(10, b.Hp);
    }

    [Fact]
    public void Side_Opponent_IsTheOtherSide()
    {
        Assert.Equal(Side.Enemy, Side.Player.Opponent());
        Assert.Equal(Side.Player, Side.Enemy.Opponent());
    }
}
