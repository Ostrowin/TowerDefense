using System.Numerics;

namespace TowerDefense.Core;

public sealed class Unit : ISimEntity
{
    private readonly Vector2[] _waypoints;
    private int _targetIndex;

    public int Id { get; }
    public Side Owner { get; }
    public Vector2 Position { get; private set; }
    /// <summary>Pozycja sprzed ostatniego Update — do interpolacji w renderze.</summary>
    public Vector2 PreviousPosition { get; private set; }
    public float Speed { get; }
    public int Damage { get; }
    public int MaxHp { get; }
    public int Hp { get; private set; }
    public bool IsDead => Hp <= 0;
    public bool ReachedEnd { get; private set; }
    /// <summary>Dystans przebyty po ścieżce. Wieże celują w najdalej zaawansowaną jednostkę.</summary>
    public float PathProgress { get; private set; }

    public Unit(int id, Side owner, UnitSpec spec, Vector2[] waypoints)
    {
        if (waypoints == null || waypoints.Length == 0)
            throw new ArgumentException("Ścieżka musi mieć co najmniej jeden punkt.", nameof(waypoints));
        Id = id;
        Owner = owner;
        Speed = spec.Speed;
        Damage = spec.Damage;
        MaxHp = spec.Hp;
        Hp = spec.Hp;
        _waypoints = waypoints;
        Position = PreviousPosition = waypoints[0];
        _targetIndex = 1;
        ReachedEnd = waypoints.Length < 2;
    }

    public void Update(float fixedDt)
    {
        PreviousPosition = Position;
        if (ReachedEnd || IsDead) return;

        // Resztę kroku przenosimy za zakręt — jednostka nie gubi dystansu na waypoincie.
        float remaining = Speed * fixedDt;
        while (remaining > 0f && !ReachedEnd)
        {
            Vector2 target = _waypoints[_targetIndex];
            float distance = Vector2.Distance(Position, target);
            Position = Movement.MoveTowards(Position, target, remaining, out bool arrived);
            if (!arrived)
            {
                PathProgress += remaining;
                return;
            }
            PathProgress += distance;
            remaining -= distance;
            _targetIndex++;
            if (_targetIndex >= _waypoints.Length) ReachedEnd = true;
        }
    }

    public void TakeDamage(int amount)
    {
        if (amount <= 0) return;
        Hp = Math.Max(0, Hp - amount);
    }
}
