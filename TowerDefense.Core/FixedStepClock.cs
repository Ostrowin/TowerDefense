namespace TowerDefense.Core;

/// <summary>
/// Zamienia zmienny czas klatki na stałe kroki symulacji.
///
///   klatka (elapsed) ──► akumulator ──► N × Tick(Step) ──► reszta zostaje → Alpha do interpolacji
///
/// Clamp: ponad MaxStepsPerFrame zaległy czas jest porzucany (anty spiral-of-death —
/// gra chwilowo zwalnia zamiast się zakopać, np. po breakpoincie albo przeciąganiu okna).
/// </summary>
public sealed class FixedStepClock
{
    private double _accumulator;

    public float StepSeconds { get; }
    public int MaxStepsPerFrame { get; }
    /// <summary>Ułamek kroku [0,1) między poprzednim a bieżącym stanem sim.</summary>
    public float Alpha => (float)(_accumulator / StepSeconds);

    public FixedStepClock(float stepSeconds = 1f / 60f, int maxStepsPerFrame = 5)
    {
        if (stepSeconds <= 0f) throw new ArgumentOutOfRangeException(nameof(stepSeconds));
        if (maxStepsPerFrame < 1) throw new ArgumentOutOfRangeException(nameof(maxStepsPerFrame));
        StepSeconds = stepSeconds;
        MaxStepsPerFrame = maxStepsPerFrame;
    }

    /// <summary>Dodaje czas klatki; zwraca, ile kroków symulacji wykonać teraz.</summary>
    public int Advance(double elapsedSeconds)
    {
        if (elapsedSeconds > 0) _accumulator += elapsedSeconds;
        int steps = (int)(_accumulator / StepSeconds);
        if (steps > MaxStepsPerFrame)
        {
            _accumulator = 0;
            return MaxStepsPerFrame;
        }
        _accumulator -= steps * (double)StepSeconds;
        return steps;
    }
}
