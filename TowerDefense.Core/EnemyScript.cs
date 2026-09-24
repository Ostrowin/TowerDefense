namespace TowerDefense.Core;

public readonly record struct SpawnEvent(float Time, UnitSpec Unit);

/// <summary>Skryptowany wróg: stały harmonogram spawnów (czas od startu gry → typ jednostki).</summary>
public sealed class EnemyScript
{
    private readonly SpawnEvent[] _events;
    private int _next;

    public bool IsFinished => _next >= _events.Length;

    public EnemyScript(IEnumerable<SpawnEvent> events)
    {
        _events = events.OrderBy(e => e.Time).ToArray();
    }

    /// <summary>`count` spawnów co `interval` s, zaczynając od `start`.</summary>
    public static EnemyScript Repeating(float start, float interval, int count, UnitSpec unit) =>
        new(Enumerable.Range(0, count).Select(i => new SpawnEvent(start + i * interval, unit)));

    /// <summary>Zdarzenia, których czas minął (każde zwracane dokładnie raz).</summary>
    public List<UnitSpec> TakeDue(float elapsedSeconds)
    {
        var due = new List<UnitSpec>();
        while (_next < _events.Length && _events[_next].Time <= elapsedSeconds)
            due.Add(_events[_next++].Unit);
        return due;
    }
}
