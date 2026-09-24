using System.Numerics;
using Xunit;
using static TowerDefense.Core.Tests.TestHelpers;

namespace TowerDefense.Core.Tests;

public class ExtractorTests
{
    [Fact]
    public void Extractor_GeneratesFromNode_UntilDepleted()
    {
        var node = new ResourceNode(id: 1, position: new Vector2(5, 0), amount: 100);
        var extractor = new Extractor(id: 2, node: node, ratePerSecond: 10f);

        int total = 0;
        for (int i = 0; i < 60 * 30; i++)     // 30 s (tempo 10/s → chciałby 300, ale w węźle jest 100)
        {
            extractor.Update(FixedDt);
            total += extractor.TakeOutput();
        }

        Assert.Equal(100, total);             // wyciągnął DOKŁADNIE tyle, ile było
        Assert.True(extractor.IsDepleted);
    }

    [Fact]
    public void TakeOutput_ReturnsEachResourceOnce()
    {
        var node = new ResourceNode(id: 1, position: Vector2.Zero, amount: 100);
        var extractor = new Extractor(id: 2, node: node, ratePerSecond: 10f);

        extractor.Update(1f);
        Assert.Equal(10, extractor.TakeOutput());
        Assert.Equal(0, extractor.TakeOutput());
    }

    [Fact]
    public void SecondExtractor_OnSameNode_Throws()
    {
        var node = new ResourceNode(id: 1, position: Vector2.Zero, amount: 100);
        _ = new Extractor(id: 2, node: node, ratePerSecond: 10f);

        Assert.True(node.HasExtractor);
        Assert.Throws<InvalidOperationException>(() => new Extractor(id: 3, node: node, ratePerSecond: 10f));
    }
}
