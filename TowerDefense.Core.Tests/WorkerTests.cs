using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class WorkerTests
{
    [Fact]
    public void Worker_MovesToNode_Builds_ThenReturnsNode_AndGoesIdle()
    {
        var node = new ResourceNode(id: 1, position: new Vector2(0, 10), amount: 100);
        var worker = new Worker(id: 1, speed: 5f, buildTime: 1f, position: new Vector2(0, 0));

        worker.OrderBuildOn(node);
        Assert.Equal(WorkerState.GoingToNode, worker.State);

        ResourceNode? built = null;
        for (int i = 0; i < 60 * 5; i++)   // 5 s: 2 s marszu (dist 10 / speed 5) + 1 s budowy + zapas
        {
            var result = worker.Update(1f / 60f);
            if (result != null) built = result;
        }

        Assert.Equal(node, built);                    // zwrócił węzeł, na którym zbudował
        Assert.Equal(WorkerState.Idle, worker.State); // po budowie wraca do Idle
    }
}