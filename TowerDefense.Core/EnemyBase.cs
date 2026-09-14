namespace TowerDefense.Core;

public sealed class EnemyBase
{
    public int Id { get; }
    public int Hp { get; private set; }
    public bool IsDestroyed => Hp <= 0;

    public EnemyBase(int id, int hp)
    {
        Id = id;
        Hp = hp;
    }

    public void TakeDamage(int amount)
    {
        if (amount <= 0) return;
        Hp -= amount;
        if (Hp < 0) Hp = 0;
    }


}
