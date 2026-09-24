namespace TowerDefense.Core;

public enum Side { Player, Enemy }

public static class SideExtensions
{
    public static Side Opponent(this Side side) => side == Side.Player ? Side.Enemy : Side.Player;
}
