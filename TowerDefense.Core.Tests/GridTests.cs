using System.Numerics;
using Xunit;

namespace TowerDefense.Core.Tests;

public class GridTests
{
    private static Grid MakeGrid() => new(origin: new Vector2(2, 10), width: 3, height: 2, cellSize: 2f);

    [Theory]
    [InlineData(2.1f, 10.1f, 0, 0)]
    [InlineData(7.9f, 13.9f, 2, 1)]
    [InlineData(1.9f, 10f, -1, 0)]
    public void WorldToCell_FloorsIntoCells(float x, float y, int cx, int cy)
    {
        Assert.Equal(new GridCell(cx, cy), MakeGrid().WorldToCell(new Vector2(x, y)));
    }

    [Fact]
    public void CellCenter_IsMiddleOfCell()
    {
        Assert.Equal(new Vector2(5, 13), MakeGrid().CellCenter(new GridCell(1, 1)));
    }

    [Fact]
    public void InBounds_ChecksAllEdges()
    {
        var grid = MakeGrid();
        Assert.True(grid.InBounds(new GridCell(0, 0)));
        Assert.True(grid.InBounds(new GridCell(2, 1)));
        Assert.False(grid.InBounds(new GridCell(-1, 0)));
        Assert.False(grid.InBounds(new GridCell(0, -1)));
        Assert.False(grid.InBounds(new GridCell(3, 0)));
        Assert.False(grid.InBounds(new GridCell(0, 2)));
    }

    [Fact]
    public void InvalidDimensions_Throw()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new Grid(Vector2.Zero, 0, 1, 1f));
        Assert.Throws<ArgumentOutOfRangeException>(() => new Grid(Vector2.Zero, 1, 0, 1f));
        Assert.Throws<ArgumentOutOfRangeException>(() => new Grid(Vector2.Zero, 1, 1, 0f));
    }
}
