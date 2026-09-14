using System.Numerics;

namespace TowerDefense.Core;

public static class Movement
{
    public static Vector2 MoveTowards(Vector2 position, Vector2 target, float step, out bool arrived)
    {
        Vector2 toTarget = target - position;
        float distanceToTarget = toTarget.Length();
        if (step >= distanceToTarget)
        {
            arrived = true;
            return target;
        }
        arrived = false;
        return position + Vector2.Normalize(toTarget) * step;
    }
}
