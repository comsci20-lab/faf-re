"""F11 diagnostics tests. Run with the existing Python+lupa test runtime."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / 'mods/Microchip-F11-Lag-Links'

class F11Tests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.core = self.lua.execute((MOD / 'modules/analysis.lua').read_text(encoding='utf-8-sig'))
        self.tracker = self.core.New()

    def clients(self, buffers=None, bridge=True):
        rows = {}
        for i, name in enumerate(('Alice', 'Bob', 'Carol'), 1):
            row = {'uid': str(i), 'name': name, 'connected': True, 'quiet': 0, 'ping': 30, 'local': i == 1}
            if bridge:
                row['fafReNetwork'] = {'version': 1, 'dispatched': 100, 'available': 8,
                    'buffers': {j: 8 for j in range(1, 4)}}
            rows[i] = row
        if buffers is not None:
            rows[1]['fafReNetwork']['buffers'] = buffers
        return self.lua.table_from(rows, recursive=True)

    def update(self, clients, now):
        return self.tracker.Update(self.tracker, clients, now)

    def test_persistent_direction_and_recovery(self):
        c = self.clients({1: 8, 2: 0, 3: 9})
        self.assertIsNone(self.update(c, 10)[0][1])
        labels, full = self.update(c, 11.6)
        self.assertTrue(full)
        self.assertIn('waits for Bob', labels[1])  # Alice receives slowly from Bob.
        self.assertIsNone(labels[2])
        self.assertIsNone(self.update(self.clients(), 12)[0][1])
        self.assertIsNone(self.update(c, 12.1)[0][1])

    def test_uniform_cpu_or_pause_does_not_blame_a_pair(self):
        c = self.clients({1: 0, 2: 0, 3: 0})
        self.update(c, 0)
        self.assertIsNone(self.update(c, 10)[0][1])

    def test_worst_incoming_source_is_named_when_multiple_are_delayed(self):
        c = self.clients({1: 8, 2: 0, 3: -4, 4: 10})
        c[4] = self.lua.table_from({'uid': '4', 'name': 'Dave', 'connected': True, 'quiet': 0, 'ping': 30})
        self.update(c, 0)
        self.assertIn('waits for Carol +1', self.update(c, 2)[0][1])

    def test_old_engine_and_local_ping_warning_are_explicit(self):
        c = self.clients(bridge=False)
        c[2]['ping'] = 500
        labels, full = self.update(c, 0)
        self.assertFalse(full)
        self.assertIn('local links only', labels[1])
        self.assertIn('high ping to you', labels[2])
        self.assertNotIn('waits', labels[2])

    def test_disconnected_and_stale_rows_do_not_make_remote_claims(self):
        c = self.clients({1: 8, 2: 0, 3: 9})
        c[2]['quiet'] = 4000
        self.update(c, 0)
        labels, _ = self.update(c, 10)
        self.assertIsNone(labels[1])
        self.assertIn('no packets to you', labels[2])

    def test_roster_change_and_clock_reset_restart_persistence(self):
        c = self.clients({1: 8, 2: 0, 3: 9})
        self.update(c, 0)
        c[3]['uid'] = 'new-player'
        self.assertIsNone(self.update(c, 2)[0][1])
        self.assertIn('waits for Bob', self.update(c, 4)[0][1])
        self.assertIsNone(self.update(c, 1)[0][1])

    def test_hook_keeps_original_snapshot_untouched(self):
        c = self.clients(bridge=False)
        self.lua.globals().snapshot = c
        self.lua.globals().core = self.core
        self.lua.execute('''
            function import() return core end
            function GetSessionClients() return snapshot end
            function GetSystemTimeSeconds() return 10 end
            function CloseWindow() closeCalled=true end
        ''')
        self.lua.execute((MOD / 'hook/lua/ui/game/connectivity.lua').read_text(encoding='utf-8-sig'))
        shown = self.lua.globals().GetSessionClients()
        self.assertIn('local links only', shown[1]['name'])
        self.assertEqual(c[1]['name'], 'Alice')
        self.lua.globals().CloseWindow()
        self.assertTrue(self.lua.globals().closeCalled)

if __name__ == '__main__': unittest.main()
