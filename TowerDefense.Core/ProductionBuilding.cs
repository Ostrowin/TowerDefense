using System.Numerics;

namespace TowerDefense.Core;

public sealed class ProductionBuilding
{
    private float _timeSinceLastSpawn;

    public float SpawnInterval { get; }
    public float UnitSpeed { get; }
    public int UnitDamage { get; }
    public Vector2[] Path { get; }
    public int Cost { get; }

    public ProductionBuilding(float spawnInterval, int cost, float unitSpeed, int unitDamage, Vector2[] path)
    {
        SpawnInterval = spawnInterval;
        Cost = cost;
        UnitSpeed = unitSpeed;
        UnitDamage = unitDamage;
        Path = path;
    }

    public bool ReadyToSpawn(float dt)
    {
        _timeSinceLastSpawn += dt;
        if (_timeSinceLastSpawn >= SpawnInterval)
        {
            _timeSinceLastSpawn -= SpawnInterval;
            return true;
        }
        return false;
    }

}
