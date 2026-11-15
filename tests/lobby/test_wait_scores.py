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
        # Ann: worst once (30 s) in 30 min played; Bob: 12 s + 10 min * 3 % = 18 s in 30 min.
        self.assertAlmostEqual(scores["name:Ann"].percent, 30 * 100 / (1800 + 1800))
        self.assertEqual(scores["name:Ann"].worstGames, 1)
        self.assertAlmostEqual(scores["name:Bob"].percent, 30 * 100 / (1800 + 1800))
        self.assertEqual(scores["name:Bob"].worstGames, 2)
        self.assertEqual(scores["name:Bob"].games, 3)

    def test_scores_follow_the_faf_id_across_a_name_change(self):
        csv = "\n".join([
            HEADER + ",player_ids",
            '"g1","a","b",ended,10.0,"Ann",5.00,"Ann 5.00%; Bob 1.00%","Ann 30.0; Bob 6.0",,,"Ann 11; Bob 22"',
            '"g2","a","b",ended,10.0,"Anna",4.00,"Anna 4.00%; Bob 1.00%","Anna 24.0; Bob 6.0",,,"Anna 11; Bob 22"',
        ])
        self.lua.globals().MicrochipReadWaitHistory = lambda: csv
        get = self.lua.globals().Get
        # Same ID 11 under two names: 54 s in 20 min.
        self.assertAlmostEqual(get("Anna", "11").percent, 54 * 100 / (1200 + 1800))
        self.assertEqual(get("Anna", "11").worstGames, 2)
        self.assertIsNone(get("Bob", None))
        self.assertEqual(get("Bob", "22").worstGames, 0)

    def test_game_length_does_not_distort_the_score(self):
        # Cat holds up one 60-min game for 6 min (10 %); Dan one 6-min game for 36 s (10 %).
        # Both also played a clean 30-min game. Counted per game, their waits would weigh the same;
        # by time, Cat's long game weighs ten times as much as Dan's short one.
        csv = "\n".join([
            HEADER,
            '"g1","a","b",ended,60.0,"Cat",10.00,"Cat 10.00%; Eve 0.10%","Cat 360.0; Eve 3.6",,',
            '"g2","a","b",ended,30.0,"Eve",1.00,"Cat 0.00%; Eve 1.00%","Cat 0; Eve 18.0",,',
            '"g3","a","b",ended,6.0,"Dan",10.00,"Dan 10.00%; Eve 0.10%","Dan 36.0; Eve 0.36",,',
            '"g4","a","b",ended,30.0,"Eve",1.00,"Dan 0.00%; Eve 1.00%","Dan 0; Eve 18.0",,',
        ])
        scores = self.parse(csv)
        self.assertAlmostEqual(scores["name:Cat"].percent, 360 * 100 / (5400 + 1800))  # 5.0 %
        self.assertAlmostEqual(scores["name:Dan"].percent, 36 * 100 / (2160 + 1800))   # 0.9 %: short game, little weight

    def test_games_under_five_minutes_are_skipped(self):
        csv = HEADER + '\n"g1","a","b",ended,2.0,"Fay",30.00,"Fay 30.00%","Fay 36.0",,\n'
        self.assertEqual(len(list(self.parse(csv).items())), 0)

    def test_games_without_a_worst_player_count_for_nobody(self):
        scores = self.parse(HEADER + '\n"g1","a","b",ended,24.0,,,"",,,\n')
        self.assertEqual(len(list(scores.items())), 0)

    def test_missing_history_gives_no_scores(self):
        self.assertEqual(len(list(self.parse(None).items())), 0)


if __name__ == "__main__":
    unittest.main()
