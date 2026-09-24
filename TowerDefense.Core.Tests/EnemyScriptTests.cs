using Xunit;

namespace TowerDefense.Core.Tests;

public class EnemyScriptTests
{
    private static readonly UnitSpec Grunt = new(Speed: 1f, Damage: 1, Hp: 1);
    private static readonly UnitSpec Brute = new(Speed: 1f, Damage: 5, Hp: 50);

    [Fact]
    public void TakeDue_ReturnsEventsInTimeOrder_EachOnce()
    {
        var script = new EnemyScript(new[]
        {
            new SpawnEvent(5f, Brute),
            new SpawnEvent(1f, Grunt),
        });

        Assert.Empty(script.TakeDue(0.5f));
        Assert.Equal(new[] { Grunt }, script.TakeDue(1f));
        Assert.Empty(script.TakeDue(2f));
        Assert.False(script.IsFinished);
        Assert.Equal(new[] { Brute }, script.TakeDue(100f));
        Assert.True(script.IsFinished);
    }

    [Fact]
    public void Repeating_SpawnsCountTimesAtInterval()
    {
        var script = EnemyScript.Repeating(start: 2f, interval: 3f, count: 3, unit: Grunt);   // 2, 5, 8

        Assert.Single(script.TakeDue(4.9f));
        Assert.Equal(2, script.TakeDue(8f).Count);
        Assert.True(script.IsFinished);
    }
}
