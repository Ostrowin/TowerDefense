using System.Numerics;

namespace TowerDefense.Core;

public sealed class ResourceNode : IEntity
{
    public int Id { get; }
    public Vector2 Position { get; }
    public int Amount { get; private set; }
    public bool IsEmpty => Amount <= 0;
    /// <summary>Jedno złoże = maksymalnie jeden wydobywacz.</summary>
    public bool HasExtractor { get; private set; }

    public ResourceNode(int id, Vector2 position, int amount)
    {
        Id = id;
        Position = position;
        Amount = amount;
    }

    public int Extract(int requested)
    {
        if (requested <= 0 || Amount <= 0) return 0;
        int taken = Math.Min(requested, Amount);
        Amount -= taken;
        return taken;
    }

    internal void ClaimForExtractor()
    {
        if (HasExtractor)
            throw new InvalidOperationException($"Złoże {Id} ma już wydobywacz.");
        HasExtractor = true;
    }
}
