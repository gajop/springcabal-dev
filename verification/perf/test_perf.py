import unittest
import json
from pathlib import Path
import tempfile
import run
import report


class EquivalenceTests(unittest.TestCase):
    @staticmethod
    def row(frame, units=10, digest='123'):
        return {'kind': 'sim', 'frame': str(frame), 'units': str(units),
                'projectiles': '0', 'state_digest': digest}

    def test_empty_or_early_exit_is_not_equivalent(self):
        for a, b in [([], []), ([self.row(1)], [])]:
            result = run.compare(a, b)
            self.assertFalse(result['frame_sets_equal'])
            self.assertFalse(result['alive_counters_match'])

    def test_equal_counts_do_not_hide_state_divergence(self):
        result = run.compare([self.row(1), self.row(2)],
                             [self.row(1), self.row(2, digest='456')])
        self.assertTrue(result['alive_counters_match'])
        self.assertEqual(result['first_state_divergence'], 2)
        self.assertFalse(result['e1_complete'])

    def test_population_mismatch_is_reported(self):
        result = run.compare([self.row(1)], [self.row(1, units=11)])
        self.assertFalse(result['alive_counters_match'])

    def test_partial_frame_window_is_reported(self):
        result = run.compare([self.row(1), self.row(2)], [self.row(1)])
        self.assertFalse(result['frame_sets_equal'])

    def test_render_window_requires_one_draw_per_measured_step(self):
        rows = [{'kind': 'draw', 'frame': str(n)} for n in [-1, 0, 1, 2, 3]]
        self.assertEqual(run.draw_window(rows, 1, 3), [1, 2])
        rows.append({'kind': 'draw', 'frame': '2'})
        self.assertNotEqual(run.draw_window(rows, 1, 3), [1, 2])

    def test_missing_draw_is_not_hidden_by_complete_simulation(self):
        rows = [self.row(n) for n in range(4)]
        rows.append({'kind': 'draw', 'frame': '2'})
        self.assertNotEqual(run.draw_window(rows, 1, 3), [1, 2])


class ReportTests(unittest.TestCase):
    def test_failed_stress_runs_do_not_enter_timing_aggregates(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for repeat, (ok, time) in enumerate([(True, 1000), (True, 3000), (False, 100000)]):
                directory = root/'case'/f'game-{repeat}-lua'
                directory.mkdir(parents=True)
                result = {'game': 'ttld', 'backend': 'lua', 'ok': ok,
                          'contended': False, 'population': {'units': {'p50': 5910}},
                          'metrics': {'sim.elapsed_us': {'p50': time, 'p95': time}}}
                (directory/'result.json').write_text(json.dumps(result))
            summary, = report.summarize(root)
            self.assertEqual(summary['attempted'], 3)
            self.assertEqual(summary['completed'], 2)
            self.assertEqual(summary['sim_p50_ms'], 2)
            self.assertIsNone(summary['sampled_peak_rss_mib'])


if __name__ == '__main__':
    unittest.main()
