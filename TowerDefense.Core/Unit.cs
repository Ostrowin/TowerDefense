using System.Numerics;
using System.Reflection.Metadata.Ecma335;
using static System.Net.Mime.MediaTypeNames;

namespace TowerDefense.Core;

public sealed class Unit
{
    private readonly Vector2[] _waypoints;
    private int _targetIndex;

    public int Id { get; }
    public Vector2 Position { get; private set; }
    public float Speed { get; }
    public bool ReachedEnd { get; private set; }
    public int Damage { get; }
    public int Hp { get; private set; }
    public bool IsDead => Hp <= 0;

    public Unit(int id, float speed, Vector2[] waypoints,int damage, int hp = 10)
    {
        Id = id;
        Speed = speed;
        Damage = damage;
        Hp = hp;
        _waypoints = waypoints;
        Position = waypoints[0];
        _targetIndex = 1;
        if (waypoints.Length < 2) ReachedEnd = true;
    }

    public void Update (float dt)
    {
        if (ReachedEnd) return;

        float step = Speed * dt;
        Position = Movement.MoveTowards(Position, _waypoints[_targetIndex], step, out bool arrived);
        if (arrived)
        {
            _targetIndex++;
            if (_targetIndex >= _waypoints.Length)
            {
                ReachedEnd = true;
            }
        }
    }

    public void TakeDamage(int amount)
    {
        if (amount <= 0) return;
        Hp -= amount;
        if (Hp < 0) Hp = 0;
    }

}
