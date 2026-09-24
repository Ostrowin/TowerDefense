using Xunit;
using static TowerDefense.Core.Tests.TestHelpers;

namespace TowerDefense.Core.Tests;

public class Level1Tests
{
    [Fact]
    public void Idle_Player_EventuallyLoses()
    {
        var sim = Level1.Create();

        Run(sim, seconds: 600);

        Assert.True(sim.IsLost);
    }

    [Fact]
    public void Scripted_BuildOrder_BeatsLevel()
    {
        // Skryptowany „gracz": robotnik na oba złoża, potem koszary gdy stać.
        var sim = Level1.Create();
        var worker = sim.Workers[0];
        var pendingNodes = new Queue<ResourceNode>(sim.ResourceNodes);
        int nextCell = 0;

        for (int step = 0; step < 60 * 600 && sim.Result == GameResult.Playing; step++)
        {
            if (worker.State == WorkerState.Idle && pendingNodes.Count > 0)
                sim.TryOrderBuild(worker, pendingNodes.Dequeue());
            if (sim.Resources >= Level1.Barracks.BuildCost + 20 && nextCell < sim.Grid!.Width)
                sim.TryPlaceBuilding(new GridCell(nextCell++, 0), Level1.Barracks, out _);
            sim.Tick(FixedDt);
        }

        Assert.True(sim.IsWon);
    }
}
