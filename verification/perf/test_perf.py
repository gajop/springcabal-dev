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

    def test_wall_markers_preserve_scripted_action_order(self):
        text = '# scene\n60: give 10 rabbit\n300: local shadows 1\n'
        self.assertEqual(run.timed_input(text, 300, 900).splitlines(), [
            '60: give 10 rabbit', '300: local echo [PerfWindow] begin frame=300',
            '300: local shadows 1', '900: local echo [PerfWindow] end frame=900'])
        for invalid in ('60: cheat\n1: cheat\n', '-1: cheat\n'):
            with self.assertRaises(ValueError):
                run.timed_input(invalid, 300, 900)

    def test_wall_window_includes_time_between_complete_frame_boundaries(self):
        log = ('[t=00:00:02.123456][f=0000300] [PerfWindow] begin frame=300\n'
               '[t=00:00:05.123456][f=0000900] [PerfWindow] end frame=900\n')
        self.assertAlmostEqual(run.wall_window(log, 300, 900), 3)
        for invalid in (log.splitlines()[0], log+log, log.replace('frame=900', 'frame=899'),
                        log.replace('05.123456', '01.123456')):
            with self.assertRaises(ValueError):
                run.wall_window(invalid, 300, 900)


class ReportTests(unittest.TestCase):
    def test_paired_report_excludes_both_members_of_contended_or_failed_pair(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for repeat in range(5):
                for backend in ('lua', 'wasm'):
                    if repeat == 4 and backend == 'wasm':
                        continue
                    bad = backend == 'wasm' and repeat in (2, 3)
                    directory = root/'case'/f'game-{repeat}-{backend}'
                    directory.mkdir(parents=True)
                    result = {'game': 'hunted', 'backend': backend, 'repeat': repeat,
                              'ok': not (bad and repeat == 2), 'contended': bad and repeat == 3,
                              'metrics': {'frame.cpu_us': {'p50': 2000 if backend == 'lua' else 1000}},
                              'window_wall_ms_per_frame': 4 if backend == 'lua' else 3,
                              'population': {'units': {'p50': 10}}}
                    (directory/'result.json').write_text(json.dumps(result))
            row, = report.paired_summary(root)
            self.assertEqual(row['measured_pairs'], 2)
            self.assertEqual(row['attempted_pairs'], 5)
            self.assertEqual(row['excluded_pairs'], 3)
            self.assertEqual(row['cpu_p50_paired_rust_change_pct'], -50)
            self.assertEqual(row['wall_mean_paired_rust_change_pct'], -25)

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
