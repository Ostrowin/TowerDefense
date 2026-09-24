using System;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;
using TowerDefense.Core;
using SimVector2 = System.Numerics.Vector2;

namespace TowerDefense.DesktopGL;

public class Game1 : Game
{
    private GraphicsDeviceManager _graphics;
    private SpriteBatch _spriteBatch = null!;
    private Texture2D _pixel = null!;
    private MouseState _prevMouse;

    //gra
    private SimState _sim = null!;
    private ResourceNode _node = null!;
    private Worker _worker = null!;
    private SimVector2[] _path = null!;
    private int _baseStartHp;
    private const float Scale = 40f;
    private static readonly Vector2 Origin = new(120f, 220f);

    public Game1()
    {
        _graphics = new GraphicsDeviceManager(this);
        Content.RootDirectory = "Content";
        IsMouseVisible = true;
    }

    protected override void Initialize()
    {
        var enemyBase = new EnemyBase(id:1, hp: 60);
        _baseStartHp = 60;
        _sim = new SimState(enemyBase, extractorRate: 20f);

        _path = new[] { new SimVector2(0, 0), new SimVector2(12, 0) };
        _node = new ResourceNode(id: 1, position: new SimVector2(2, 5), amount:10000);
        _worker = new Worker(id: 1, speed: 3f, buildTime: 2f, position: new SimVector2(0,0));
        _sim.Workers.Add(_worker);
        _sim.Buildings.Add(new ProductionBuilding(spawnInterval:1f, cost:10, unitSpeed:3f, unitDamage: 10, path: _path));
        _sim.Towers.Add(new Tower(id: 1, position: new SimVector2(10, 0), range: 3f, damage: 5, fireInterval: 1f));
        base.Initialize();
    }

    protected override void LoadContent()
    {
        _spriteBatch = new SpriteBatch(GraphicsDevice);
        _pixel = new Texture2D(GraphicsDevice, 1, 1);
        _pixel.SetData(new[] { Color.White });   // jeden biały piksel
    }

    protected override void Update(GameTime gameTime)
    {
        var mouse = Mouse.GetState();

        // KLIKNIĘCIE = zbocze: teraz wciśnięty, a w poprzedniej klatce był puszczony
        bool leftClicked = mouse.LeftButton == ButtonState.Pressed
                        && _prevMouse.LeftButton == ButtonState.Released;

        if (leftClicked)
        {
            SimVector2 world = ScreenToWorld(new Vector2(mouse.X, mouse.Y));
            if (SimVector2.Distance(world, _node.Position) < 1.0f)   // kliknięto blisko złoża
                _worker.OrderBuildOn(_node);
        }

        _prevMouse = mouse;                 // zapamiętaj na następną klatkę

        _sim.Tick(1f / 60f);
        base.Update(gameTime);
    }


    protected override void Draw(GameTime gameTime)
    {
        GraphicsDevice.Clear(Color.CornflowerBlue);
        _spriteBatch.Begin();

        DrawMarker(_node.Position, 16, Color.Gold);            // 1. złoże (spód)
        DrawMarker(_worker.Position, 10, Color.White);         // 2. robotnik
        if (_sim.Extractors.Count > 0)
            DrawMarker(_node.Position, 14, Color.Orange);      // 3. wydobywacz NA WIERZCHU,
                                                               // wieże wroga (obrona bazy) + ich zasięg
        foreach (var tower in _sim.Towers)
        {
            DrawCircleOutline(tower.Position, tower.Range, Color.MediumPurple);
            DrawMarker(tower.Position, 14, Color.BlueViolet);
        }

        foreach (var unit in _sim.Units)
            DrawMarker(unit.Position, 8, Color.DeepSkyBlue);        // jednostki
        DrawMarker(_path[^1], 24, Color.Firebrick);                // baza wroga (koniec ścieżki)
        DrawHealthBar(_path[^1], _sim.EnemyBase.Hp, _baseStartHp);

        _spriteBatch.End();
        base.Draw(gameTime);
    }

    // sim -> ekran
    private Vector2 WorldToScreen(SimVector2 w) => Origin + new Vector2(w.X, w.Y) * Scale;

    private void DrawMarker(SimVector2 world, int size, Color color)
    {
        var s = WorldToScreen(world);
        _spriteBatch.Draw(_pixel, new Rectangle((int)s.X - size / 2, (int)s.Y - size / 2, size, size), color);
    }

    private void DrawHealthBar(SimVector2 world, int hp, int maxHp)
    {
        var s = WorldToScreen(world);
        int w = 44, h = 5, x = (int)s.X - w / 2, y = (int)s.Y - 28;
        _spriteBatch.Draw(_pixel, new Rectangle(x, y, w, h), Color.DarkRed);          // tło paska
        int fill = (int)(w * (hp / (float)maxHp));
        _spriteBatch.Draw(_pixel, new Rectangle(x, y, fill, h), Color.LimeGreen);     // życie
    }

    private SimVector2 ScreenToWorld(Vector2 screen)
    {
        Vector2 rel = (screen - Origin) / Scale;   // cofnij Origin i Scale
        return new SimVector2(rel.X, rel.Y);
    }

    private void DrawCircleOutline(SimVector2 worldCenter, float worldRadius, Color color)
    {
        Vector2 center = WorldToScreen(worldCenter);
        float radiusPx = worldRadius * Scale;
        const int segments = 48;
        for (int i = 0; i < segments; i++)
        {
            float angle = MathHelper.TwoPi * i / segments;
            int x = (int)(center.X + MathF.Cos(angle) * radiusPx);
            int y = (int)(center.Y + MathF.Sin(angle) * radiusPx);
            _spriteBatch.Draw(_pixel, new Rectangle(x - 1, y - 1, 2, 2), color);
        }
    }
}
