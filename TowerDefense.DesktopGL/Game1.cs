using System;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;
using TowerDefense.Core;
using SimVector2 = System.Numerics.Vector2;

namespace TowerDefense.DesktopGL;

/// <summary>
/// Cienka głowa: input → rozkazy dla SimState, zegar stałego kroku, render stanu (tylko odczyt).
/// Logika gry żyje w Core.
/// </summary>
public class Game1 : Game
{
    private const int VirtualWidth = 1280;
    private const int VirtualHeight = 720;
    private const float PixelsPerUnit = 40f;

    private readonly GraphicsDeviceManager _graphics;
    private readonly ScreenMapping _mapping = new(VirtualWidth, VirtualHeight, PixelsPerUnit);
    private readonly FixedStepClock _clock = new();
    private SpriteBatch _spriteBatch = null!;
    private Texture2D _pixel = null!;
    private MouseState _prevMouse;
    private KeyboardState _prevKeyboard;

    private SimState _sim = null!;
    private string _lastAction = "Klik: złoże = wydobywacz, siatka = koszary (50)";

    public Game1()
    {
        _graphics = new GraphicsDeviceManager(this)
        {
            PreferredBackBufferWidth = VirtualWidth,
            PreferredBackBufferHeight = VirtualHeight,
            SynchronizeWithVerticalRetrace = true,
        };
        Content.RootDirectory = "Content";
        IsMouseVisible = true;
        IsFixedTimeStep = false;                 // krok stały robi FixedStepClock
        Window.AllowUserResizing = true;
        Window.ClientSizeChanged += (_, _) => UpdateMapping();
    }

    protected override void Initialize()
    {
        _sim = Level1.Create();
        base.Initialize();
        UpdateMapping();
    }

    protected override void LoadContent()
    {
        _spriteBatch = new SpriteBatch(GraphicsDevice);
        _pixel = new Texture2D(GraphicsDevice, 1, 1);
        _pixel.SetData(new[] { Color.White });
    }

    private void UpdateMapping() => _mapping.Resize(Window.ClientBounds.Width, Window.ClientBounds.Height);

    // ── Update: input + stały krok ───────────────────────────────────────────

    protected override void Update(GameTime gameTime)
    {
        var mouse = Mouse.GetState();
        var keyboard = Keyboard.GetState();

        if (keyboard.IsKeyDown(Keys.Escape)) Exit();
        if (keyboard.IsKeyDown(Keys.R) && _prevKeyboard.IsKeyUp(Keys.R))
        {
            _sim = Level1.Create();
            _lastAction = "Restart";
        }

        bool leftClicked = mouse.LeftButton == ButtonState.Pressed && _prevMouse.LeftButton == ButtonState.Released;
        if (leftClicked && IsActive)
            HandleClick(_mapping.ScreenToWorld(new SimVector2(mouse.X, mouse.Y)));

        _prevMouse = mouse;
        _prevKeyboard = keyboard;

        int steps = _clock.Advance(gameTime.ElapsedGameTime.TotalSeconds);
        for (int i = 0; i < steps; i++)
            _sim.Tick(_clock.StepSeconds);

        Window.Title = BuildStatusLine();
        base.Update(gameTime);
    }

    private void HandleClick(SimVector2 world)
    {
        foreach (var node in _sim.ResourceNodes)
        {
            if (SimVector2.Distance(world, node.Position) >= 1f) continue;
            _lastAction = _sim.TryOrderBuild(_sim.Workers[0], node)
                ? "Robotnik idzie budować wydobywacz"
                : "Złoże zajęte albo puste";
            return;
        }

        if (_sim.Grid is { } grid && grid.InBounds(grid.WorldToCell(world)))
        {
            var result = _sim.TryPlaceBuilding(grid.WorldToCell(world), Level1.Barracks, out _);
            _lastAction = result switch
            {
                PlacementResult.Ok => "Postawiono koszary",
                PlacementResult.Occupied => "Pole zajęte",
                PlacementResult.NotEnoughResources => $"Za mało surowców (koszary: {Level1.Barracks.BuildCost})",
                _ => result.ToString(),
            };
        }
    }

    private string BuildStatusLine()
    {
        string state = _sim.Result switch
        {
            GameResult.Won => "WYGRANA! (R = restart)",
            GameResult.Lost => "PRZEGRANA (R = restart)",
            _ => _lastAction,
        };
        return $"Surowce: {_sim.Resources} | Baza: {_sim.PlayerBase.Hp}/{_sim.PlayerBase.MaxHp} | " +
               $"Wróg: {_sim.EnemyBase.Hp}/{_sim.EnemyBase.MaxHp} | {_sim.ElapsedSeconds:0}s | {state}";
    }

    // ── Draw: tylko odczyt stanu, pozycje interpolowane ─────────────────────

    protected override void Draw(GameTime gameTime)
    {
        GraphicsDevice.Clear(Color.Black);      // pasy letterboxa
        var transform = Matrix.CreateScale(_mapping.ViewScale)
                      * Matrix.CreateTranslation(_mapping.Offset.X, _mapping.Offset.Y, 0f);
        _spriteBatch.Begin(transformMatrix: transform, samplerState: SamplerState.PointClamp);

        _spriteBatch.Draw(_pixel, new Rectangle(0, 0, VirtualWidth, VirtualHeight), Color.CornflowerBlue);
        DrawGrid();
        DrawLane();

        foreach (var node in _sim.ResourceNodes)
            DrawMarker(node.Position, 16, node.IsEmpty ? Color.DimGray : node.HasExtractor ? Color.Orange : Color.Gold);

        foreach (var tower in _sim.Towers)
        {
            Color color = tower.Owner == Side.Player ? Color.SteelBlue : Color.BlueViolet;
            DrawCircleOutline(tower.Position, tower.Range, color * 0.6f);
            DrawMarker(tower.Position, 14, color);
        }

        foreach (var building in _sim.Buildings)
            DrawMarker(building.Position, 30, Color.SaddleBrown);

        DrawBase(_sim.PlayerBase, Color.RoyalBlue);
        DrawBase(_sim.EnemyBase, Color.Firebrick);

        float alpha = _clock.Alpha;
        foreach (var unit in _sim.Units)
        {
            var pos = SimVector2.Lerp(unit.PreviousPosition, unit.Position, alpha);
            DrawMarker(pos, 10, unit.Owner == Side.Player ? Color.DeepSkyBlue : Color.OrangeRed);
            DrawHealthBar(pos, unit.Hp, unit.MaxHp, width: 14, yOffset: -10);
        }

        foreach (var worker in _sim.Workers)
            DrawMarker(SimVector2.Lerp(worker.PreviousPosition, worker.Position, alpha), 10, Color.White);

        if (_sim.Result != GameResult.Playing)
        {
            Color tint = _sim.IsWon ? Color.LimeGreen : Color.DarkRed;
            _spriteBatch.Draw(_pixel, new Rectangle(0, 0, VirtualWidth, VirtualHeight), tint * 0.35f);
        }

        _spriteBatch.End();
        base.Draw(gameTime);
    }

    private Vector2 ToVirtual(SimVector2 world)
    {
        var v = _mapping.WorldToVirtual(world);
        return new Vector2(v.X, v.Y);
    }

    private void DrawGrid()
    {
        if (_sim.Grid is not { } grid) return;
        var mouseWorld = _mapping.ScreenToWorld(new SimVector2(_prevMouse.X, _prevMouse.Y));
        var hovered = grid.WorldToCell(mouseWorld);
        int cellPx = (int)(grid.CellSize * PixelsPerUnit);

        for (int x = 0; x < grid.Width; x++)
        for (int y = 0; y < grid.Height; y++)
        {
            var cell = new GridCell(x, y);
            var center = ToVirtual(grid.CellCenter(cell));
            var rect = new Rectangle((int)center.X - cellPx / 2 + 1, (int)center.Y - cellPx / 2 + 1, cellPx - 2, cellPx - 2);
            Color color = Color.White * 0.12f;
            if (cell == hovered)
                color = !grid.IsOccupied(cell) && _sim.Resources >= Level1.Barracks.BuildCost
                    ? Color.LimeGreen * 0.4f
                    : Color.Red * 0.4f;
            _spriteBatch.Draw(_pixel, rect, color);
        }
    }

    private void DrawLane()
    {
        var lane = _sim.Lane;
        for (int i = 0; i < lane.Count - 1; i++)
        {
            Vector2 a = ToVirtual(lane[i]), b = ToVirtual(lane[i + 1]);
            float length = Vector2.Distance(a, b);
            float angle = MathF.Atan2(b.Y - a.Y, b.X - a.X);
            _spriteBatch.Draw(_pixel, a, null, Color.Tan * 0.6f, angle, new Vector2(0f, 0.5f),
                              new Vector2(length, 12f), SpriteEffects.None, 0f);
        }
    }

    private void DrawBase(Base b, Color color)
    {
        DrawMarker(b.Position, 36, color);
        DrawHealthBar(b.Position, b.Hp, b.MaxHp, width: 48, yOffset: -30);
    }

    private void DrawMarker(SimVector2 world, int size, Color color)
    {
        var v = ToVirtual(world);
        _spriteBatch.Draw(_pixel, new Rectangle((int)v.X - size / 2, (int)v.Y - size / 2, size, size), color);
    }

    private void DrawHealthBar(SimVector2 world, int hp, int maxHp, int width, int yOffset)
    {
        var v = ToVirtual(world);
        int x = (int)v.X - width / 2, y = (int)v.Y + yOffset;
        _spriteBatch.Draw(_pixel, new Rectangle(x, y, width, 4), Color.DarkRed);
        int fill = maxHp > 0 ? (int)(width * (hp / (float)maxHp)) : 0;
        _spriteBatch.Draw(_pixel, new Rectangle(x, y, fill, 4), Color.LimeGreen);
    }

    private void DrawCircleOutline(SimVector2 worldCenter, float worldRadius, Color color)
    {
        Vector2 center = ToVirtual(worldCenter);
        float radius = worldRadius * PixelsPerUnit;
        const int segments = 48;
        for (int i = 0; i < segments; i++)
        {
            float angle = MathHelper.TwoPi * i / segments;
            int x = (int)(center.X + MathF.Cos(angle) * radius);
            int y = (int)(center.Y + MathF.Sin(angle) * radius);
            _spriteBatch.Draw(_pixel, new Rectangle(x - 1, y - 1, 2, 2), color);
        }
    }
}
