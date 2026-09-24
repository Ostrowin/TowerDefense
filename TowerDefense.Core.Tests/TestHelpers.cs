using System.Numerics;

namespace TowerDefense.Core.Tests;

internal static class TestHelpers
{
    public const float FixedDt = 1f / 60f;

    /// <summary>Prosta linia 10 jednostek: baza gracza (0,0), baza wroga (10,0).</summary>
    public static Vector2[] ShortLane => new[] { new Vector2(0, 0), new Vector2(10, 0) };

    public static void Run(SimState sim, float seconds)
    {
        int steps = (int)MathF.Round(seconds / FixedDt);
        for (int i = 0; i < steps; i++)
            sim.Tick(FixedDt);
    }

    public static ProductionBuildingSpec Barracks(float spawnInterval = 1f, int unitCost = 10,
                                                  float unitSpeed = 5f, int unitDamage = 10, int unitHp = 10,
                                                  int buildCost = 50) =>
        new(buildCost, spawnInterval, unitCost, new UnitSpec(unitSpeed, unitDamage, unitHp));
}
