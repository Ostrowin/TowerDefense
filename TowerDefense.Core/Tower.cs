using System.Numerics;

namespace TowerDefense.Core;

public sealed class Tower : ISimEntity
{
    private float _cooldown;

    public int Id { get; }
    public Side Owner { get; }
    public Vector2 Position { get; }
    public float Range { get; }
    public int Damage { get; }
    public float FireInterval { get; }
    public bool IsReady => _cooldown <= 0f;

    public Tower(int id, Side owner, Vector2 position, float range, int damage, float fireInterval)
    {
        Id = id;
        Owner = owner;
        Position = position;
        Range = range;
        Damage = damage;
        FireInterval = fireInterval;
    }

    public void Update(float fixedDt)
    {
        if (_cooldown > 0f) _cooldown -= fixedDt;
    }

    /// <summary>Strzela, jeśli gotowa i ma cel. Zwraca trafioną jednostkę albo null.</summary>
    public Unit? TryFire(IReadOnlyList<Unit> units)
    {
        if (!IsReady) return null;
        Unit? target = SelectTarget(units);
        if (target == null) return null;

        target.TakeDamage(Damage);
        _cooldown = FireInterval;
        return target;
    }

    /// <summary>Żywy wróg w zasięgu, najdalej na ścieżce (czyli najbliżej naszej bazy).</summary>
    public Unit? SelectTarget(IReadOnlyList<Unit> units)
    {
        Unit? best = null;
        foreach (var unit in units)
        {
            if (unit.IsDead || unit.Owner == Owner) continue;
            if (Vector2.Distance(Position, unit.Position) > Range) continue;
            if (best == null || unit.PathProgress > best.PathProgress)
                best = unit;
        }
        return best;
    }
}
