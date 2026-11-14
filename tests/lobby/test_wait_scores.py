"""Run with Python + lupa (Lua 5.1); no game required."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

SOURCE = Path(__file__).resolve().parents[2] / "data/fafengine/lua/ui/lobby/waitscores.lua"
HEADER = ("game_id,started,last_updated,status,minutes_played,worst_player,worst_wait_percent,"
          "all_players_wait_percent,all_players_total_wait_seconds,all_players_wait_episodes,"
          "all_players_average_wait_ms")


class WaitScoreTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute("string.gfind = string.gfind or string.gmatch")
        self.lua.execute(SOURCE.read_text(encoding="utf-8"))
        self.parse = self.lua.globals().Parse

    def test_counts_wait_only_in_games_the_player_was_worst(self):
        csv = "\r\n".join([
            HEADER,
            '"g1","a","b",ended,10.0,"Ann",5.00,"Ann 5.00%; Bob 1.00%","Ann 30.0; Bob 6.0",,',
            '"g2","a","b",ended,10.0,"Bob",2.00,"Ann 1.00%; Bob 2.00%","Ann 6.0; Bob 12.0",,',
            '"g3","a","b",ended,10.0,"Bob",3.00,"Ann 0.50%; Bob 3.00%","",,',
        ])
        scores = self.parse(csv)
        # Ann: worst once (30 s) over 3 games; Bob: 12 s + 10 min * 3 % = 18 s, over 3 games.
        self.assertAlmostEqual(scores["Ann"].average, 10.0)
        self.assertEqual(scores["Ann"].worstGames, 1)
        self.assertAlmostEqual(scores["Bob"].average, 10.0)
        self.assertEqual(scores["Bob"].worstGames, 2)
        self.assertEqual(scores["Bob"].games, 3)

    def test_games_without_a_worst_player_count_for_nobody(self):
        scores = self.parse(HEADER + '\n"g1","a","b",ended,24.0,,,"",,,\n')
        self.assertEqual(len(list(scores.items())), 0)

    def test_missing_history_gives_no_scores(self):
        self.assertEqual(len(list(self.parse(None).items())), 0)


if __name__ == "__main__":
    unittest.main()
