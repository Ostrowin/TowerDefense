using Xunit;

namespace TowerDefense.Core.Tests;

public class EnemyBaseTests
{
    [Fact]
    public void TakeDamage_ReducesHp_AndClampsAtZero()
    {
        var enemyBase = new EnemyBase(id: 1, hp: 100);

        enemyBase.TakeDamage(30);
        Assert.Equal(70, enemyBase.Hp);
        Assert.False(enemyBase.IsDestroyed);

        enemyBase.TakeDamage(1000);
        Assert.Equal(0, enemyBase.Hp);
        Assert.True(enemyBase.IsDestroyed);
    }
}