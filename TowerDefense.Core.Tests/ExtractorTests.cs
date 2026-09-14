using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class ExtractorTests
{
    [Fact]
    public void Extractor_FundsProduction_WhichDestroysBase()
    {
        var enemyBase = new EnemyBase(id: 1, hp: 30);
        var sim = new SimState(enemyBase);

        var node = new ResourceNode(id: 1, position: new Vector2(0, 5), amount: 1000);
        sim.Extractors.Add(new Extractor(id: 1, node: node, ratePerSecond: 20f));   // dochód 20/s

        var path = new[] { new Vector2(0, 0), new Vector2(10, 0) };
        sim.Buildings.Add(new ProductionBuilding(spawnInterval: 2f, cost: 10, unitSpeed: 5f, unitDamage: 10, path: path));

        for (int i = 0; i < 60 * 60; i++)     // 60 s
            sim.Tick(1f / 60f);

        Assert.True(sim.IsWon);               // złoże → wydobywacz → produkcja → jednostki → baza pada
    }


    [Fact]
    public void Extractor_GeneratesFromNode_UntilDepleted()
    {
        var node = new ResourceNode(id: 1, position: new Vector2(5, 0), amount: 100);
        var extractor = new Extractor(id: 1, node: node, ratePerSecond: 10f);

        int total = 0;
        for (int i = 0; i < 60 * 30; i++)     // 30 s (tempo 10/s → chciałby 300, ale w węźle jest 100)
            total += extractor.Extract(1f / 60f);

        Assert.Equal(100, total);             // wyciągnął DOKŁADNIE tyle, ile było
        Assert.True(node.IsEmpty);
    }
}