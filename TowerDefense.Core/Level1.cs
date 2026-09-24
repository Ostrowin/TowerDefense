using System.Numerics;

namespace TowerDefense.Core;

/// <summary>
/// Poziom 1 — hardcode (format danych poziomu dopiero przy M3).
/// Świat 32 × 18 jednostek (= 1280 × 720 wirtualnych px przy 40 px/j).
///
///   y 4   P════════╗           ╔════════E      P = baza gracza, E = baza wroga
///   y 7            ╚═══════════╝               ═ linia (lane)
///   y 10–16  [ siatka 14 × 3 pod budynki ]
/// </summary>
public static class Level1
{
    public static readonly ProductionBuildingSpec Barracks =
        new(BuildCost: 50, SpawnInterval: 2.5f, UnitCost: 10, Unit: new UnitSpec(Speed: 2.5f, Damage: 10, Hp: 25));

    private static readonly UnitSpec Grunt = new(Speed: 2.5f, Damage: 10, Hp: 20);
    private static readonly UnitSpec Brute = new(Speed: 1.5f, Damage: 25, Hp: 60);

    public static SimState Create()
    {
        var lane = new[]
        {
            new Vector2(2, 4), new Vector2(10, 4), new Vector2(10, 7),
            new Vector2(22, 7), new Vector2(22, 4), new Vector2(30, 4),
        };
        var grid = new Grid(origin: new Vector2(2, 10), width: 14, height: 3, cellSize: 2f);

        var sim = new SimState(lane, playerBaseHp: 100, enemyBaseHp: 150,
                               extractorRate: 8f, grid: grid, enemyScript: CreateEnemyScript());
        sim.AddResources(60);

        sim.AddResourceNode(new Vector2(3, 7.5f), amount: 2000);
        sim.AddResourceNode(new Vector2(6, 8.5f), amount: 2000);
        sim.AddWorker(new Vector2(3, 6), speed: 4f, buildTime: 2f);

        sim.AddTower(Side.Player, new Vector2(8, 5.5f), range: 3.5f, damage: 6, fireInterval: 0.8f);
        sim.AddTower(Side.Enemy, new Vector2(24, 5.5f), range: 3f, damage: 5, fireInterval: 0.8f);
        sim.AddTower(Side.Enemy, new Vector2(27, 2.5f), range: 3f, damage: 5, fireInterval: 0.8f);
        return sim;
    }

    /// <summary>Stały strumień piechoty od 10 s + ciężkie jednostki od 60 s.</summary>
    private static EnemyScript CreateEnemyScript()
    {
        var events = new List<SpawnEvent>();
        for (int i = 0; i < 60; i++) events.Add(new SpawnEvent(10f + i * 5f, Grunt));
        for (int i = 0; i < 20; i++) events.Add(new SpawnEvent(60f + i * 12f, Brute));
        return new EnemyScript(events);
    }
}
