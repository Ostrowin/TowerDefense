using System.Numerics;

namespace TowerDefense.Core;

public sealed class Base : IEntity
{
    public int Id { get; }
    public Side Owner { get; }
    public Vector2 Position { get; }
    public int MaxHp { get; }
    public int Hp { get; private set; }
    public bool IsDestroyed => Hp <= 0;

    public Base(int id, Side owner, Vector2 position, int hp)
    {
        Id = id;
        Owner = owner;
        Position = position;
        MaxHp = hp;
        Hp = hp;
    }

    public void TakeDamage(int amount)
    {
        if (amount <= 0) return;
        Hp = Math.Max(0, Hp - amount);
    }
}
