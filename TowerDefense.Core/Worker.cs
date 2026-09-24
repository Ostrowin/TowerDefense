using System.Numerics;

namespace TowerDefense.Core;

public enum WorkerState { Idle, GoingToNode, Building }

/// <summary>
/// Robotnik stawia wydobywacz na złożu.
///
///   Idle ──OrderBuildOn(node)──► GoingToNode ──dotarł──► Building ──BuildTime──► Idle
///    ▲                                                                   │
///    └───────── SimState odbiera węzeł (TakeCompletedNode) ◄─────────────┘
///
/// Nowy rozkaz w dowolnym stanie przerywa bieżący i zaczyna od GoingToNode.
/// </summary>
public sealed class Worker : ISimEntity
{
    private ResourceNode? _targetNode;
    private ResourceNode? _completedNode;
    private float _buildTimer;

    public int Id { get; }
    public Vector2 Position { get; private set; }
    public Vector2 PreviousPosition { get; private set; }
    public float Speed { get; }
    public float BuildTime { get; }
    public WorkerState State { get; private set; } = WorkerState.Idle;
    public ResourceNode? TargetNode => _targetNode;

    public Worker(int id, Vector2 position, float speed, float buildTime)
    {
        Id = id;
        Position = PreviousPosition = position;
        Speed = speed;
        BuildTime = buildTime;
    }

    public void OrderBuildOn(ResourceNode node)
    {
        _targetNode = node;
        _buildTimer = 0f;
        State = WorkerState.GoingToNode;
    }

    public void Update(float fixedDt)
    {
        PreviousPosition = Position;
        switch (State)
        {
            case WorkerState.GoingToNode:
                Position = Movement.MoveTowards(Position, _targetNode!.Position, Speed * fixedDt, out bool arrived);
                if (arrived) State = WorkerState.Building;
                break;

            case WorkerState.Building:
                _buildTimer += fixedDt;
                if (_buildTimer >= BuildTime)
                {
                    _completedNode = _targetNode;
                    _targetNode = null;
                    State = WorkerState.Idle;
                }
                break;
        }
    }

    /// <summary>Zwraca węzeł, na którym właśnie skończono budowę (raz), inaczej null.</summary>
    public ResourceNode? TakeCompletedNode()
    {
        ResourceNode? node = _completedNode;
        _completedNode = null;
        return node;
    }
}
