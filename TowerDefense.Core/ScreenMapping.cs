using System.Numerics;

namespace TowerDefense.Core;

/// <summary>
/// Polityka współrzędnych — czysta matematyka, współdzielona przez głowy Desktop i Android:
///
///   świat (jednostki sim) ──× PixelsPerUnit──► wirtualny ekran (stała rozdzielczość)
///                         ──× ViewScale + Offset──► fizyczny ekran (letterbox, zachowane proporcje)
///
/// Input idzie drogą odwrotną: ScreenToWorld.
/// </summary>
public sealed class ScreenMapping
{
    public float VirtualWidth { get; }
    public float VirtualHeight { get; }
    public float PixelsPerUnit { get; }
    public float ViewScale { get; private set; } = 1f;
    public Vector2 Offset { get; private set; }

    public ScreenMapping(float virtualWidth, float virtualHeight, float pixelsPerUnit)
    {
        VirtualWidth = virtualWidth;
        VirtualHeight = virtualHeight;
        PixelsPerUnit = pixelsPerUnit;
    }

    public void Resize(int screenWidth, int screenHeight)
    {
        ViewScale = Math.Min(screenWidth / VirtualWidth, screenHeight / VirtualHeight);
        Offset = new Vector2(
            (screenWidth - VirtualWidth * ViewScale) / 2f,
            (screenHeight - VirtualHeight * ViewScale) / 2f);
    }

    public Vector2 WorldToVirtual(Vector2 world) => world * PixelsPerUnit;
    public Vector2 WorldToScreen(Vector2 world) => WorldToVirtual(world) * ViewScale + Offset;
    public Vector2 ScreenToWorld(Vector2 screen) => (screen - Offset) / ViewScale / PixelsPerUnit;
}
