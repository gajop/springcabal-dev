import unittest
import json
from pathlib import Path
import tempfile
import run
import report
import dashboard
import profile_export
import threading
import subprocess
import struct
import storage
from unittest.mock import patch


class EquivalenceTests(unittest.TestCase):
    def test_clean_target_succeeds_after_interrupted_attempt_without_accepting_partial_pairs(self):
        variants=[('lua','off'),('wasm','off')]
        results=[{'game':'hunted','repeat':repeat,'backend':backend,'rust_jobs':'off',
                  'ok':not (repeat==0 and backend=='lua'),
                  'contended':repeat==0 and backend=='lua'}
                 for repeat in (0,1) for backend in ('lua','wasm')]
        status=run.campaign_completion(results,variants,['hunted'],1)
        self.assertTrue(status['complete'])
        self.assertEqual(status['clean_pairs_by_game'],{'hunted':1})
        self.assertEqual(status['failed_attempts'],1)
        self.assertEqual(status['contended_attempts'],1)
        self.assertFalse(run.campaign_completion(results,variants,['hunted'],2)['complete'])
        self.assertFalse(run.campaign_completion(results,variants,['hunted'])['complete'])
        self.assertFalse(run.campaign_completion(results[:-1],variants,['hunted'],1)['complete'])
        self.assertFalse(run.campaign_completion(results,variants,['hunted','flove'],1)['complete'])
        self.assertFalse(run.campaign_completion([],variants,['hunted'],1)['complete'])

    def test_saved_global_pressure_excludes_old_cgroup_only_acceptance_without_rewriting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status = root/'result.json'
            original = {'ok': True, 'contended': False, 'gpu_process_guard': True}
            status.write_text(json.dumps(original))
            telemetry = root/'host-samples.json'
            telemetry.write_text(json.dumps([{'cpu_pressure': 'some avg10=39.22',
                                             'contention_cpu_pressure': 'some avg10=0.00'}]))
            reviewed = report.read_result(status)
            self.assertTrue(reviewed['contended'])
            self.assertFalse(reviewed['recorded_contended'])
            self.assertEqual(reviewed['global_cpu_pressure_review'], {'max_avg10': 39.22, 'passed': False})
            self.assertEqual(json.loads(status.read_text()), original)
            telemetry.write_text(json.dumps([{'cpu_pressure': 'some avg10=0.00'}]))
            self.assertFalse(report.read_result(status)['contended'])
            telemetry.unlink()
            self.assertTrue(report.read_result(status)['contended'])

    def test_empty_report_clears_a_previous_campaign_export(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/'jobs'
            report.write_rows(output, [{'campaign': 'previous', 'measured_pairs': 5}])
            report.write_rows(output, [])
            self.assertEqual(json.loads(output.with_suffix('.json').read_text()), [])
            self.assertEqual(output.with_suffix('.csv').read_text(), '')

    def jit_fixture(self, root, loads, flags=0, extra=b''):
        data = struct.pack('<6I2Q', 0x4a695444, 1, 40, 62, 0, 42, 0, flags)
        for address, name, timestamp in loads:
            payload = struct.pack('<II4Q', 42, 43, address, address, 32, 1)
            payload += name.encode()+b'\0'+b'\x90'*32
            data += struct.pack('<IIQ', 0, len(payload)+16, timestamp)+payload
        (root/'jit-42.dump').write_bytes(data+extra)
        return profile_export.JitSymbols(root)

    def test_jit_symbols_require_matching_process_range_and_load_time(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit = self.jit_fixture(root, [(0x1000, 'core::slice::sort', 1_000_000_000)])
            raw = ('recoil-main 42/43 2.000000: 2000000\n'
                   '  1015 [unknown] (/tmp/perf-42.map)\n')
            frames = profile_export.parse(raw, jit)[0]['frames']
            self.assertEqual(frames, [('core::slice::sort', 'jit-42.dump')])
            self.assertEqual(profile_export.category(*frames[0]), 'Wasm guest')
            self.assertIsNone(jit.resolve(99, 0x1015, 2_000_000_000))
            self.assertIsNone(jit.resolve(42, 0x1015, 999_999_999))
            self.assertIsNone(jit.resolve(42, 0x1020, 2_000_000_000))
            self.assertEqual(profile_export.parse(raw.replace('42/43', '99/43'), jit)[0]['frames'][0][0], '[unknown]')

    def test_jit_symbols_leave_unsupported_or_ambiguous_code_unresolved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            loads = [(0x1000, 'first', 1)]
            self.assertIsNone(self.jit_fixture(root, loads, flags=1).resolve(42, 0x1000, 10))
            move = struct.pack('<IIQ', 1, 16, 2)
            self.assertIsNone(self.jit_fixture(root, loads, extra=move).resolve(42, 0x1000, 10))
            overlap = loads+[(0x1010, 'second', 2)]
            self.assertIsNone(self.jit_fixture(root, overlap).resolve(42, 0x1010, 10))
            close = struct.pack('<IIQ', 3, 16, 3)
            jit = self.jit_fixture(root, loads, extra=close)
            self.assertEqual(jit.resolve(42, 0x1000, 2)[0], 'first')
            self.assertIsNone(jit.resolve(42, 0x1000, 3))

    def test_jit_symbols_reject_truncated_code_records(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.jit_fixture(root, [(0x1000, 'first', 1)])
            path = root/'jit-42.dump'
            path.write_bytes(path.read_bytes()[:-1])
            with self.assertRaisesRegex(ValueError, 'record length'):
                profile_export.JitSymbols(root)

    def test_frozen_content_does_not_inherit_its_parent_repository_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '--quiet', str(root)], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Perf test',
                            '-c', 'user.email=perf@example.invalid', '-c', 'commit.gpgsign=false',
                            'commit', '--quiet', '--allow-empty', '-m', 'Fixture'], check=True)
            copied = root/'frozen-games'
            copied.mkdir()
            self.assertIsNotNone(run.revision(root))
            self.assertIsNone(run.revision(copied))

    def test_pending_campaign_has_no_fabricated_measurements(self):
        with self.assertRaises(ValueError):
            dashboard.scene_summary({}, 'ttld-pending', 'ttld')
        pending = dashboard.scene_summary({}, 'ttld-pending', 'ttld', True)
        self.assertEqual(pending['measured_pairs'], 0)
        self.assertEqual(pending['run_ids'], [])
        self.assertNotIn('wall_mean_lua_ms', pending)
        completed = {'campaign': 'ttld-pending', 'measured_pairs': 5}
        self.assertIs(dashboard.scene_summary({'ttld-pending': completed},
                                            'ttld-pending', 'ttld', True), completed)

    def test_dashboard_preserves_partial_evidence_without_inventing_frames(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'frames.csv').write_text(
                'kind,frame,elapsed_us,lua_us,wasm_us,import_us,units,projectiles,particles\n'
                'sim,300,1000,100,200,10,7,2,1\n'
                'draw,300,2000,300,400,20,7,2,1\n'
                'sim,301,1000,100,200,10,8,2,1\n')
            rows = dashboard.trace(root, strict=False)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0][0], 300)
            self.assertEqual(rows[0][9:], [7, 2, 1])
            with self.assertRaises(ValueError): dashboard.trace(root)

    def test_verification_lease_yields_idle_time_without_allowing_active_overlap(self):
        with tempfile.TemporaryDirectory() as directory:
            lock=Path(directory)/'verification.lock'
            def competitor():
                return subprocess.run(['flock','-n',str(lock),'true'],check=False).returncode
            with run.VerificationLease(lock) as lease:
                self.assertEqual(competitor(),1)
                lease.release()
                self.assertEqual(competitor(),0)
                self.assertTrue(lease.try_acquire())
                self.assertEqual(competitor(),1)
            self.assertEqual(competitor(),0)

    def test_idle_wait_samples_gpu_only_while_owning_the_resource_lease(self):
        from types import SimpleNamespace
        class Lease:
            held=True
            attempts=0
            def release(self): self.held=False
            def try_acquire(self):
                self.attempts+=1
                self.held=self.attempts>2
                return self.held
        lease=Lease();clock=[0];samples=[]
        def gpu():
            self.assertTrue(lease.held)
            sample={'foreign':[{'pid':12}] if not samples else [],'time':clock[0]}
            samples.append(sample);return sample
        def host(_):
            self.assertTrue(lease.held)
            return {'cpu_pressure':'some avg10=0.00'}
        options=SimpleNamespace(wait_for_idle=True,wait_for_gpu_idle=True)
        before,last,history=run.wait_for_resources(options,None,100,'fixture',lease,
            host_sample=host,gpu_sample=gpu,now=lambda:clock[0],sleep=lambda duration:clock.__setitem__(0,clock[0]+duration))
        self.assertTrue(lease.held)
        self.assertFalse(last['foreign'])
        self.assertGreaterEqual(last['time']-samples[1]['time'],10)
        self.assertEqual(history,samples)

    def test_timer_off_control_requires_engine_acknowledgement_and_zero_counters(self):
        row={'callback_timers':'0','lua_us':'0','wasm_us':'0','import_us':'0'}
        self.assertTrue(run.callback_timers_off([row,dict(row)]))
        self.assertFalse(run.callback_timers_off([]))
        self.assertFalse(run.callback_timers_off([{k:v for k,v in row.items() if k!='callback_timers'}]))
        self.assertFalse(run.callback_timers_off([dict(row, callback_timers='1')]))
        self.assertFalse(run.callback_timers_off([row,dict(row, import_us='0.001')]))

    def optimization_fixture(self, root):
        experiment={'id':'example', 'title':'Fixture', 'load':'Normal', 'change':'Same work',
                    'rounds':[{'before':['before'], 'after':['after']}]}
        for phase, factor in [('before', 1), ('after', .5)]:
            campaign=root/phase;campaign.mkdir()
            (campaign/'provenance.json').write_text(json.dumps({'engine_sha256':'same', 'args':{'unit_multiplier':1}}))
            for backend, time in [('lua', 10), ('wasm', 8)]:
                directory=campaign/('fixture-00-'+backend);directory.mkdir()
                result={'repeat':0, 'backend':backend, 'game':'fixture', 'ok':True,
                        'contended':False, 'window_wall_ms_per_frame':time*factor,
                        'metrics':{key:{'p50':time*factor*1000} for key in ('sim.elapsed_us','draw.elapsed_us')}}
                (directory/'result.json').write_text(json.dumps(result))
        return [experiment]

    def test_source_ab_uses_each_language_and_complete_clean_four_run_rounds(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);manifest=self.optimization_fixture(root)
            rows=report.source_optimization_summary(manifest, root)
            self.assertEqual([r['wall_before_ms'] for r in rows], [10,8])
            self.assertEqual([r['wall_after_ms'] for r in rows], [5,4])
            self.assertTrue(all(r['wall_change_pct']==-50 and r['measured_rounds']==1 for r in rows))
            path=root/'after/fixture-00-wasm/result.json';result=json.loads(path.read_text())
            result['contended']=True;path.write_text(json.dumps(result))
            rows=report.source_optimization_summary(manifest, root)
            self.assertTrue(all(r['measured_rounds']==0 and r['wall_change_pct'] is None for r in rows))

    def test_source_ab_rejects_changed_engine_or_workload(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);manifest=self.optimization_fixture(root)
            path=root/'after/provenance.json';stamp=json.loads(path.read_text())
            stamp['engine_sha256']='different';path.write_text(json.dumps(stamp))
            with self.assertRaisesRegex(ValueError, 'same engine'):
                report.source_optimization_summary(manifest, root)
            stamp['engine_sha256']='same';stamp['args']['unit_multiplier']=10;path.write_text(json.dumps(stamp))
            with self.assertRaisesRegex(ValueError, 'unit_multiplier'):
                report.source_optimization_summary(manifest, root)
            stamp['args']['unit_multiplier']=1;stamp['runner_sha256']='new runner'
            path.write_text(json.dumps(stamp))
            self.assertTrue(all(r['measured_rounds']==0 for r in report.source_optimization_summary(manifest, root)))

    def test_lua_only_source_change_uses_its_clean_runs_without_a_rust_counterpart(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);manifest=self.optimization_fixture(root)
            manifest[0]['backends']=['lua']
            path=root/'after/fixture-00-wasm/result.json'
            result=json.loads(path.read_text());result['contended']=True
            path.write_text(json.dumps(result))
            rows=report.source_optimization_summary(manifest, root)
            self.assertEqual(len(rows),1)
            self.assertEqual(rows[0]['backend'],'lua')
            self.assertEqual(rows[0]['wall_change_pct'],-50)
            self.assertEqual(rows[0]['measured_rounds'],1)
            result=json.loads((root/'after/fixture-00-lua/result.json').read_text())
            result['contended']=True
            (root/'after/fixture-00-lua/result.json').write_text(json.dumps(result))
            self.assertEqual(report.source_optimization_summary(manifest, root)[0]['measured_rounds'],0)

    def test_world_compression_preserves_bytes_and_removes_the_raw_copy(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'world.jsonl';destination=root/'world.jsonl.gz'
            original=b'{"frame": 1, "units": []}\n'*1000
            source.write_bytes(original)
            metadata=storage.compress_world(source, destination)
            self.assertFalse(source.exists())
            self.assertEqual(metadata['world_recording_sha256'],hashlib.sha256(original).hexdigest())
            with storage.open_world(source) as stream:self.assertEqual(stream.read().encode(),original)
            self.assertLess(destination.stat().st_size,len(original)//5)

    def test_failed_compression_keeps_the_original_recording(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'world.jsonl';destination=root/'world.jsonl.gz'
            source.write_bytes(b'original evidence')
            with patch.object(storage.gzip,'open',side_effect=OSError('readback failure')):
                with self.assertRaisesRegex(OSError,'readback failure'):
                    storage.compress_world(source,destination)
            self.assertEqual(source.read_bytes(),b'original evidence')
            self.assertFalse(destination.exists())
            self.assertFalse(destination.with_suffix('.gz.partial').exists())

    def test_compaction_keeps_identical_recordings_shared_and_removes_duplicates(self):
        import compact, os
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);first=root/'one';second=root/'two'
            for p in (first,second):
                (p/'write').mkdir(parents=True)
                (p/'result.json').write_text(json.dumps({'world_recording':'world.jsonl'}))
            original=b'{"type":"sample","frame":3}\n'
            (first/'world.jsonl').write_bytes(original)
            os.link(first/'world.jsonl',second/'world.jsonl')
            for p in (first,second):os.link(p/'world.jsonl',p/'write/perf-world.jsonl')
            self.assertEqual(compact.compact(root),(2,0))
            self.assertEqual((first/'world.jsonl.gz').stat().st_ino,(second/'world.jsonl.gz').stat().st_ino)
            for p in (first,second):
                self.assertFalse((p/'world.jsonl').exists())
                self.assertFalse((p/'write/perf-world.jsonl').exists())
                with storage.open_world(p/'world.jsonl') as stream:self.assertEqual(stream.read().encode(),original)
                self.assertEqual(json.loads((p/'result.json').read_text())['world_recording'],'world.jsonl.gz')

    def test_disk_reserve_rejects_a_run_before_the_emergency_floor(self):
        from types import SimpleNamespace
        with patch.object(storage.shutil,'disk_usage',return_value=SimpleNamespace(free=30*1024**3)):
            with self.assertRaisesRegex(ValueError,'40 GiB reserve'):
                storage.require_space(Path('.'),40)
            storage.require_space(Path('.'),20)

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
        self.assertEqual([p['pid'] for p in run.foreign_gpu_processes(sample)], [10, 20, 30, 40, 50, 60])
        groups = {10: 321, 20: 123, 30: 321, 40: 321, 50: 321, 60: 321}
        self.assertEqual([p['pid'] for p in run.foreign_gpu_processes(sample, 123, groups.__getitem__)], [10, 30, 40, 50, 60])

    def test_pressure_guard_checks_global_and_selected_scope_and_fails_closed(self):
        sample = {'cpu_pressure': 'some avg10=40.00 avg60=20.00'}
        self.assertEqual(run.pressure(sample), 40)
        sample['contention_cpu_pressure'] = 'some avg10=0.20 avg60=0.10'
        self.assertEqual(run.pressure(sample), 40)
        sample['cpu_pressure'] = 'some avg10=0.10'
        self.assertEqual(run.pressure(sample), 0.2)
        sample['cpu_pressure'] = None
        self.assertEqual(run.pressure(sample), float('inf'))
        sample['cpu_pressure'] = 'some avg10=0.10'
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
            contended = root/'case'/'game-3-lua'
            contended.mkdir()
            result.update(ok=True, contended=True)
            (contended/'result.json').write_text(json.dumps(result))
            summary, = report.summarize(root)
            self.assertEqual(summary['attempted'], 4)
            self.assertEqual(summary['completed'], 3)
            self.assertEqual(summary['timed_runs'], 2)
            self.assertEqual(summary['sim_p50_ms'], 2)



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
        self.assertEqual(profile_export.category('[unknown]', 'libnvidia-eglcore.so'), 'CPU time in graphics driver')

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
