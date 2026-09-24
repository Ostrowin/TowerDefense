using System.Numerics;
using Xunit;
using static TowerDefense.Core.Tests.TestHelpers;

namespace TowerDefense.Core.Tests;

public class WorkerTests
{
    [Fact]
    public void Worker_MovesToNode_Builds_ThenReturnsNode_AndGoesIdle()
    {
        var node = new ResourceNode(id: 1, position: new Vector2(0, 10), amount: 100);
        var worker = new Worker(id: 2, position: Vector2.Zero, speed: 5f, buildTime: 1f);

        worker.OrderBuildOn(node);
        Assert.Equal(WorkerState.GoingToNode, worker.State);
        Assert.Same(node, worker.TargetNode);

        ResourceNode? built = null;
        for (int i = 0; i < 60 * 5; i++)   // 5 s: 2 s marszu (dist 10 / speed 5) + 1 s budowy + zapas
        {
            worker.Update(FixedDt);
            built ??= worker.TakeCompletedNode();
        }

        Assert.Same(node, built);
        Assert.Equal(WorkerState.Idle, worker.State);
        Assert.Null(worker.TakeCompletedNode());      // oddany dokładnie raz
    }

    [Fact]
    public void NewOrder_InterruptsBuilding()
    {
        var first = new ResourceNode(id: 1, position: Vector2.Zero, amount: 100);
        var second = new ResourceNode(id: 2, position: new Vector2(3, 0), amount: 100);
        var worker = new Worker(id: 3, position: Vector2.Zero, speed: 1f, buildTime: 10f);

        worker.OrderBuildOn(first);
        worker.Update(FixedDt);
        Assert.Equal(WorkerState.Building, worker.State);

        worker.OrderBuildOn(second);
        Assert.Equal(WorkerState.GoingToNode, worker.State);
        Assert.Same(second, worker.TargetNode);
    }

    [Fact]
    public void IdleWorker_StaysPut()
    {
        var worker = new Worker(id: 1, position: new Vector2(2, 2), speed: 5f, buildTime: 1f);
        worker.Update(1f);

        Assert.Equal(WorkerState.Idle, worker.State);
        Assert.Equal(new Vector2(2, 2), worker.Position);
        Assert.Null(worker.TakeCompletedNode());
    }
}
