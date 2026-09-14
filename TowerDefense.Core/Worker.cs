using System.Numerics;

namespace TowerDefense.Core;

public enum WorkerState { Idle, GoingToNode, Building }

public sealed class Worker
{
    private ResourceNode? _targetNode;
    private float _buildTimer;
    public int Id { get; }
    public Vector2 Position { get; private set; }
    public float Speed { get; }
    public float BuildTime { get; }
    public WorkerState State { get; private set; } = WorkerState.Idle;

    public Worker(int id, Vector2 position, float speed, float buildTime)
    {
        Id = id;
        Position = position;
        Speed = speed;
        BuildTime = buildTime;
    }

    public void OrderBuildOn(ResourceNode node)
    {
        _targetNode = node;
        _buildTimer = 0f;
        State = WorkerState.GoingToNode;
    }

    public ResourceNode? Update(float dt)
    {
        switch (State)
        {
            case WorkerState.GoingToNode:
                Position = Movement.MoveTowards(Position, _targetNode!.Position, Speed * dt, out bool arrived);
                if(arrived)
                {
                    State = WorkerState.Building;
                }
                return null;

            case WorkerState.Building:
                _buildTimer += dt;
                if (_buildTimer >= BuildTime)
                {
                    ResourceNode node = _targetNode!;
                    _targetNode = null;
                    State = WorkerState.Idle;
                    return node;
                }
                return null;

            default:
                return null;
        }
    }

}
