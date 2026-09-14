using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class ResourceNodeTests
{
    [Fact]
    public void Extract_TakesRequested_ThenDepletes()
    {
        var node = new ResourceNode(id: 1, position: new Vector2(5, 0), amount: 25);

        Assert.Equal(10, node.Extract(10));    // bierzemy 10 z 25
        Assert.Equal(15, node.Amount);
        Assert.False(node.IsEmpty);

        Assert.Equal(15, node.Extract(100));   // prosimy o 100, zostało 15 → dostajemy 15
        Assert.Equal(0, node.Amount);
        Assert.True(node.IsEmpty);

        Assert.Equal(0, node.Extract(5));      // pusty — zero
    }
}