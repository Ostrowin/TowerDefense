using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class ScreenMappingTests
{
    [Fact]
    public void Resize_Letterboxes_KeepingAspect()
    {
        var mapping = new ScreenMapping(virtualWidth: 100, virtualHeight: 50, pixelsPerUnit: 10);
        mapping.Resize(200, 200);                   // ekran wyższy niż wirtualny → pasy góra/dół

        Assert.Equal(2f, mapping.ViewScale);
        Assert.Equal(new Vector2(0, 50), mapping.Offset);
    }

    [Fact]
    public void WorldToScreen_And_Back_RoundTrip()
    {
        var mapping = new ScreenMapping(virtualWidth: 100, virtualHeight: 50, pixelsPerUnit: 10);
        mapping.Resize(200, 200);

        var screen = mapping.WorldToScreen(new Vector2(5, 2));

        Assert.Equal(new Vector2(100, 90), screen);  // (50,20)·2 + (0,50)
        Assert.Equal(new Vector2(5, 2), mapping.ScreenToWorld(screen));
    }
}
