using System.Numerics;

namespace TowerDefense.Core;

public readonly record struct GridCell(int X, int Y);

/// <summary>Siatka pod budynki. Origin = lewy górny róg komórki (0,0) w świecie.</summary>
public sealed class Grid
{
    private readonly HashSet<GridCell> _occupied = new();

    public Vector2 Origin { get; }
    public int Width { get; }
    public int Height { get; }
    public float CellSize { get; }

    public Grid(Vector2 origin, int width, int height, float cellSize)
    {
        if (width <= 0 || height <= 0 || cellSize <= 0f)
            throw new ArgumentOutOfRangeException(nameof(width), "Wymiary siatki muszą być dodatnie.");
        Origin = origin;
        Width = width;
        Height = height;
        CellSize = cellSize;
    }

    public bool InBounds(GridCell cell) => cell.X >= 0 && cell.Y >= 0 && cell.X < Width && cell.Y < Height;
    public bool IsOccupied(GridCell cell) => _occupied.Contains(cell);

    public GridCell WorldToCell(Vector2 world) => new(
        (int)MathF.Floor((world.X - Origin.X) / CellSize),
        (int)MathF.Floor((world.Y - Origin.Y) / CellSize));

    public Vector2 CellCenter(GridCell cell) =>
        Origin + new Vector2((cell.X + 0.5f) * CellSize, (cell.Y + 0.5f) * CellSize);

    internal void Occupy(GridCell cell) => _occupied.Add(cell);
}
