namespace TowerDefense.Core;

public sealed class Extractor : ISimEntity
{
    private float _accumulator;
    private int _pendingOutput;

    public int Id { get; }
    public ResourceNode Node { get; }
    public float RatePerSecond { get; }
    public bool IsDepleted => Node.IsEmpty;

    public Extractor(int id, ResourceNode node, float ratePerSecond)
    {
        node.ClaimForExtractor();   // rzuca, jeśli złoże już zajęte
        Id = id;
        Node = node;
        RatePerSecond = ratePerSecond;
    }

    public void Update(float fixedDt)
    {
        if (IsDepleted) return;
        _accumulator += RatePerSecond * fixedDt;
        int whole = (int)_accumulator;
        if (whole <= 0) return;
        _accumulator -= whole;
        _pendingOutput += Node.Extract(whole);
    }

    /// <summary>Oddaje surowce wydobyte od ostatniego odbioru.</summary>
    public int TakeOutput()
    {
        int output = _pendingOutput;
        _pendingOutput = 0;
        return output;
    }
}
