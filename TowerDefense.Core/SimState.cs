namespace TowerDefense.Core;

public sealed class SimState
{
    public EnemyBase EnemyBase { get; }
    public List<Unit> Units { get; } = new();
    public List<ProductionBuilding> Buildings { get; } = new();
    public List<Extractor> Extractors { get; } = new();
    public List<Worker> Workers { get; } = new();
    public List<Tower> Towers { get; } = new();
    private int _nextExtractorId;
    private readonly float _extractorRate;
    private int _nextUnitId;
    public bool IsWon => EnemyBase.IsDestroyed;
    public int Resources { get; private set; }

    public SimState(EnemyBase enemyBase, float extractorRate = 10f)
    {
        EnemyBase = enemyBase;
        _extractorRate = extractorRate;
    }

    public void AddResources(int amount)
    {
        if (amount <= 0) return;
        Resources += amount;
    }

    public void Tick(float dt)
    {
        // -1) ROBOTNICY: ruch + budowa. Gdy skończą, SimState tworzy Extractor (nadaje ID).
        foreach (var worker in Workers)
        {
            ResourceNode? built = worker.Update(dt);
            if (built != null)
                Extractors.Add(new Extractor(_nextExtractorId++, built, _extractorRate));
        }
        // 0) DOCHÓD: wydobywacze dorzucają surowce (najpierw, by produkcja mogła je wydać w tym samym ticku)
        foreach (var extractor in Extractors)
            AddResources(extractor.Extract(dt));

        // 1) Produkcja: budynek chce spawnować, ALE tylko jeśli stać nas na jednostkę
        foreach (var building in Buildings)
        {
            if (building.ReadyToSpawn(dt))
            {
                if (Resources >= building.Cost)
                {
                    Resources -= building.Cost;
                    Units.Add(new Unit(_nextUnitId++, building.UnitSpeed, building.Path, building.UnitDamage));
                }
                // else: brak surowców — cykl przepada, budynek spróbuje za kolejny interwał
            }
        }

        // 2) Ruch
        foreach (var unit in Units)
            unit.Update(dt);

        // COMBAT: wieże strzelają do jednostek w zasięgu
        foreach (var tower in Towers)
            tower.Update(dt, Units);


        // ROZLICZENIE: martwe (od wież) ORAZ te, co doszły do bazy
        for (int i = Units.Count - 1; i >= 0; i--)
        {
            if (Units[i].IsDead)
                Units.RemoveAt(i);                       // zginęła — NIE bije bazy
            else if (Units[i].ReachedEnd)
            {
                EnemyBase.TakeDamage(Units[i].Damage);
                Units.RemoveAt(i);
            }
        }
    }
}
