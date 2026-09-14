namespace TowerDefense.Core;

public sealed class Extractor
{
    private readonly ResourceNode _node;
    private float _accumulator;
    public int Id { get; }
    public float RatePerSecond { get; }

    public Extractor(int id, ResourceNode node, float ratePerSecond)
    {
        Id = id;
        _node = node;
        RatePerSecond = ratePerSecond;
    }

    public int Extract(float dt)
    {
        _accumulator += RatePerSecond * dt;
        int whole = (int)_accumulator;
        if(whole <= 0) return 0;
        _accumulator -= whole;
        return _node.Extract(whole);
    }
        
}
