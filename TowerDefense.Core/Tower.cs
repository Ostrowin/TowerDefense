using System.Numerics;

namespace TowerDefense.Core;

public sealed class Tower
{
    private float _cooldown;
    public int Id { get; }
    public Vector2 Position { get; }
    public float Range { get; }
    public int Damage { get; }
    public float FireInterval { get; }

    public Tower(int id, Vector2 position, float range, int damage, float fireInterval)
    {
        Id = id;
        Position = position;
        Range = range;
        Damage = damage;
        FireInterval = fireInterval;
    }

    public void Update(float dt, IReadOnlyList<Unit> units)
    {
        if (_cooldown > 0f) _cooldown -= dt;
        if (_cooldown > 0f) return;

        Unit? target = FindTargetInRange(units);
        if (target == null) return;

        target.TakeDamage(Damage);
        _cooldown = FireInterval;
    }

    private Unit? FindTargetInRange(IReadOnlyList<Unit> units)
    {
        foreach (var unit in units)
        {
            if (unit.IsDead) continue;
            if (Vector2.Distance(Position, unit.Position) <= Range)
            {
                return unit;
            }
        }
        return null;
    }
}
