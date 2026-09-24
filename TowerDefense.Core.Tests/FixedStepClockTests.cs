using Xunit;

namespace TowerDefense.Core.Tests;

public class FixedStepClockTests
{
    // krok 0.25 s — dokładnie reprezentowalny we floatach/doublach
    [Fact]
    public void Advance_ReturnsWholeSteps_AndKeepsRemainder()
    {
        var clock = new FixedStepClock(stepSeconds: 0.25f, maxStepsPerFrame: 10);

        Assert.Equal(2, clock.Advance(0.625));      // 2 kroki, reszta 0.125
        Assert.Equal(0.5f, clock.Alpha, precision: 5);
        Assert.Equal(1, clock.Advance(0.125));      // reszta + 0.125 = pełny krok
        Assert.Equal(0f, clock.Alpha, precision: 5);
    }

    [Fact]
    public void Advance_ClampsLongFrame_AndDropsBacklog()
    {
        var clock = new FixedStepClock(stepSeconds: 0.25f, maxStepsPerFrame: 3);

        Assert.Equal(3, clock.Advance(10.0));       // chciałby 40 kroków
        Assert.Equal(0f, clock.Alpha);
        Assert.Equal(0, clock.Advance(0.1));        // zaległość porzucona, nie nadrabia
    }

    [Fact]
    public void Advance_IgnoresNegativeTime()
    {
        var clock = new FixedStepClock(stepSeconds: 0.25f);
        Assert.Equal(0, clock.Advance(-1.0));
        Assert.Equal(0f, clock.Alpha);
    }

    [Fact]
    public void InvalidArguments_Throw()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new FixedStepClock(stepSeconds: 0f));
        Assert.Throws<ArgumentOutOfRangeException>(() => new FixedStepClock(maxStepsPerFrame: 0));
    }
}
