using System.Numerics;

namespace TowerDefense.Core;

/// <summary>Parametry typu budynku produkcyjnego.</summary>
public sealed record ProductionBuildingSpec(int BuildCost, float SpawnInterval, int UnitCost, UnitSpec Unit);

public sealed class ProductionBuilding : ISimEntity
{
    private float _timeSinceLastSpawn;
    private int _spawnsDue;

    public int Id { get; }
    public Side Owner { get; }
    public Vector2 Position { get; }
    public ProductionBuildingSpec Spec { get; }

    public ProductionBuilding(int id, Side owner, Vector2 position, ProductionBuildingSpec spec)
    {
        if (spec.SpawnInterval <= 0f)
            throw new ArgumentOutOfRangeException(nameof(spec), "SpawnInterval musi być > 0.");
        Id = id;
        Owner = owner;
        Position = position;
        Spec = spec;
    }

    public void Update(float fixedDt)
    {
        _timeSinceLastSpawn += fixedDt;
        while (_timeSinceLastSpawn >= Spec.SpawnInterval)
        {
            _timeSinceLastSpawn -= Spec.SpawnInterval;
            _spawnsDue++;
        }
    }

    /// <summary>True raz na każdy upłynięty interwał. Niewykorzystany cykl (brak surowców) przepada.</summary>
    public bool TakeSpawnDue()
    {
        if (_spawnsDue == 0) return false;
        _spawnsDue--;
        return true;
    }
}
