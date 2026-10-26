import unittest
import json
from pathlib import Path
import tempfile
import run
import report
import dashboard
import profile_export
import threading


class EquivalenceTests(unittest.TestCase):
    def test_gpu_sampling_does_not_block_the_frame_marker_controller(self):
        entered=threading.Event();release=threading.Event()
        def sample(group):
            entered.set();release.wait(1)
            return {'group':group,'foreign':[]}
        monitor=run.GpuMonitor(123,sample)
        self.assertTrue(entered.wait(1))
        self.assertEqual(monitor.samples, [])
        release.set();monitor.stop()
        self.assertIsNone(monitor.error)
        self.assertEqual(monitor.samples[0]['group'],123)

    def test_gpu_monitor_failure_is_retained_for_run_rejection(self):
        entered=threading.Event()
        def sample(_):
            entered.set();raise ValueError('driver unavailable')
        monitor=run.GpuMonitor(123,sample)
        self.assertTrue(entered.wait(1));monitor.stop()
        self.assertIsInstance(monitor.error,ValueError)

    def test_affinity_rejects_invalid_or_unavailable_cpu_sets(self):
        self.assertEqual(run.cpu_list('0,2-4,2',set(range(8))), [0,2,3,4])
        for value in ['', '3-1', '2,9', '-1', '0,,2', '0;true']:
            with self.assertRaises(ValueError):run.cpu_list(value,set(range(8)))

    def test_gpu_guard_distinguishes_desktop_own_and_foreign_clients(self):
        sample = ('# gpu pid type sm command\n'
                  '0 10 G 20 Xorg\n0 20 G - spring\n'
                  '0 30 C+G 99 spring\n0 40 C 80 python\n'
                  '0 50 G - eglretrace\n0 60 G 25 blender\n')
        self.assertEqual([p['pid'] for p in run.foreign_gpu_processes(sample)], [20, 30, 40, 50, 60])
        groups = {20: 123, 30: 321, 40: 321, 50: 321, 60: 321}
        self.assertEqual([p['pid'] for p in run.foreign_gpu_processes(sample, 123, groups.__getitem__)], [30, 40, 50, 60])

    def test_pressure_guard_uses_selected_scope_and_fails_closed(self):
        sample = {'cpu_pressure': 'some avg10=40.00 avg60=20.00'}
        self.assertEqual(run.pressure(sample), 40)
        sample['contention_cpu_pressure'] = 'some avg10=0.20 avg60=0.10'
        self.assertEqual(run.pressure(sample), 0.2)
        sample['contention_cpu_pressure'] = None
        self.assertEqual(run.pressure(sample), float('inf'))

    def test_cgroup_pressure_resolves_own_scope_and_requires_available_file(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            proc = root / 'cgroup'
            proc.write_text('0::/user.slice/app.scope\n')
            expected = root / 'user.slice/app.scope/cpu.pressure'
            with self.assertRaises(ValueError):
                run.cpu_pressure_path('cgroup', proc, root)
            expected.parent.mkdir(parents=True)
            expected.write_text('some avg10=0.00\n')
            self.assertEqual(run.cpu_pressure_path('cgroup', proc, root), expected)
            proc.write_text('2:cpu:/legacy\n')
            with self.assertRaises(ValueError):
                run.cpu_pressure_path('cgroup', proc, root)

    def test_pool_width_uses_configured_width_and_checks_effective_workers(self):
        log = ('[ThreadPool::SetThreadCount][1] wanted=20 current=1 maximum=20 (init=1)\n'
               '[ThreadPool::SetThreadCount][2] workers=19\n'
               '[ThreadPool::SetThreadCount][1] wanted=4 current=20 maximum=20 (init=0)\n'
               'thread affinity line\n[ThreadPool::SetThreadCount][2] workers=3\n'
               '[ThreadPool::SetThreadCount][1] wanted=0 current=4 maximum=20 (init=1)\n'
               '[ThreadPool::SetThreadCount][2] workers=0\n')
        self.assertEqual(run.pool_width(log), (4, 4))
        self.assertEqual(run.pool_width(log.replace('workers=3', 'workers=1')), (4, 2))
        self.assertIsNone(run.pool_width(log.split('(init=0)')[0]))

    @staticmethod
    def row(frame, units=10, digest='123'):
        return {'kind': 'sim', 'frame': str(frame), 'units': str(units),
                'projectiles': '0', 'state_digest': digest}

    def test_empty_or_early_exit_is_not_equivalent(self):
        for a, b in [([], []), ([self.row(1)], [])]:
            result = run.compare(a, b)
            self.assertFalse(result['frame_sets_equal'])
            self.assertFalse(result['alive_counters_match'])

    def test_job_comparison_labels_are_not_reported_as_languages(self):
        a = dict(self.row(1), commands='3')
        b = dict(self.row(1), commands='4')
        result = run.compare([a], [b], labels=('off', 'on'))
        self.assertEqual(result['event_totals']['commands'], {'off': 3, 'on': 4})

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
            '0: local console 0', '60: give 10 rabbit', '300: local echo [PerfWindow] begin frame=300',
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
    def test_recording_and_sampling_runs_do_not_supply_timings(self):
        self.assertFalse(report.is_timing({'instrumented': True, 'rust_jobs': 'off'}))
        self.assertTrue(report.is_timing({'instrumented': False, 'rust_jobs': 'off'}))
        self.assertFalse(report.is_timing({'rust_jobs': 'check'}))

    def test_check_mode_completes_but_does_not_supply_timing_results(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root/'case'/'game-00-wasm'
            directory.mkdir(parents=True)
            result = {'game': 'hunted', 'backend': 'wasm', 'repeat': 0,
                      'ok': True, 'contended': False, 'rust_jobs': 'check',
                      'window_wall_ms_per_frame': 1000,
                      'metrics': {'sim.elapsed_us': {'p50': 1000000}},
                      'population': {'units': {'p50': 10}}}
            (directory/'result.json').write_text(json.dumps(result))
            row, = report.summarize(root)
            self.assertEqual(row['completed'], 1)
            self.assertEqual(row['timed_runs'], 0)
            self.assertIsNone(row['sim_p50_ms'])
            self.assertIsNone(row['window_wall_ms_per_frame'])

    def test_job_modes_are_kept_separate_and_only_paired_at_matching_width(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for width in (1, 4):
                for mode in ('off', 'on'):
                    directory = root/f'w{width}'/f'game-00-wasm-{mode}'
                    directory.mkdir(parents=True)
                    result = {'game': 'hunted', 'backend': 'wasm', 'repeat': 0,
                              'ok': True, 'contended': False, 'comparison_kind': 'jobs',
                              'rust_jobs': mode, 'worker_threads': width,
                              'window_wall_ms_per_frame': 4 if mode == 'off' else 3,
                              'metrics': {}, 'population': {'units': {'p50': 10}}}
                    (directory/'result.json').write_text(json.dumps(result))
            self.assertEqual(len(report.summarize(root)), 4)
            self.assertEqual(report.paired_summary(root), [])
            paired = report.paired_summary(root, jobs=True)
            self.assertEqual({r['worker_threads'] for r in paired}, {1, 4})
            self.assertTrue(all(r['measured_pairs'] == 1 for r in paired))
            self.assertTrue(all(r['wall_mean_paired_jobs_change_pct'] == -25 for r in paired))

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


class ProfileAndRecordingTests(unittest.TestCase):
    def test_profile_parsing_preserves_cpp_parentheses_and_sample_weights(self):
        raw = ('recoil-main 10/10 123.456: 2000000\n'
               '   1234 std::_Function_handler<void (int), (anonymous namespace)::Task>::run() (/tmp/spring)\n'
               '   2345 CGame::Draw() (/tmp/spring)\n\n'
               'recoil-main 10/10 123.458: 3000000\n'
               '   1235 luaH_get(Table*, lua_TValue const*) (/tmp/spring)\n')
        samples = profile_export.parse(raw)
        self.assertEqual(len(samples), 2)
        self.assertEqual(samples[0]['frames'][0][1], '/tmp/spring')
        self.assertIn('(anonymous namespace)', samples[0]['frames'][0][0])
        tree = profile_export.export(samples)
        self.assertEqual(tree['threads'][0]['weight'], 5000000)
        self.assertEqual(sum(n['weight'] for n in tree['leaves']), 5000000)
        self.assertEqual(profile_export.category('[unknown]', 'libnvidia-eglcore.so'), 'Graphics driver (CPU)')

    def test_recording_delta_encoding_preserves_moves_removals_and_id_reuse(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'world.jsonl'
            rows = [{'type': 'header', 'format': 'springcabal-world'},
                    {'type': 'sample', 'frame': 0, 'units': [[4, 1, 0, 10.12, 20.34, 99.5, 100]], 'projectiles': []},
                    {'type': 'sample', 'frame': 6, 'units': [[4, 1, 0, 11.25, 20.32, 98.5, 100]], 'projectiles': [[1, 12, 13]]},
                    {'type': 'sample', 'frame': 12, 'units': [], 'projectiles': []},
                    {'type': 'sample', 'frame': 18, 'units': [[4, 2, 1, 80, 40, 50, 60]], 'projectiles': []},
                    {'type': 'end', 'samples': 4, 'frame': 18}]
            path.write_text(''.join(json.dumps(r)+'\n' for r in rows))
            packed = dashboard.world(path)
            self.assertEqual(packed['samples'][1][1], [[4, 113, -2, -100]])
            self.assertEqual(packed['samples'][2][2], [4])
            self.assertEqual(packed['samples'][3][1], [[4, 2, 1, 8000, 4000, 5000, 6000]])
            rows[-1]['samples'] = 5
            path.write_text(''.join(json.dumps(r)+'\n' for r in rows))
            with self.assertRaises(ValueError):
                dashboard.world(path)


if __name__ == '__main__':
    unittest.main()
