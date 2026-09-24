namespace TowerDefense.Core;

/// <summary>Encja ze stabilnym ID nadawanym przez <see cref="SimState"/>. Referencje między encjami — przez ID.</summary>
public interface IEntity
{
    int Id { get; }
}

/// <summary>
/// Encja z własnym krokiem symulacji. Update zmienia TYLKO stan encji;
/// efekty dla świata (surowce, spawny, ukończone budowy) SimState odbiera po kroku metodami Take*.
/// </summary>
public interface ISimEntity : IEntity
{
    void Update(float fixedDt);
}
