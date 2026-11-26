#!/usr/bin/env python3
"""Compare two release binaries on a synthetic season fixture and local Postgres."""

import argparse
import asyncio
import collections
import contextlib
import datetime
import http.client
import json
import math
import os
from pathlib import Path
import shutil
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.parse

SEASONS = range(2024, 2027)
SESSION_TYPES = ('fp1', 'fp2', 'fp3', 'qualifying', 'race')
TABLES = ('meetings', 'sessions', 'session_results', 'driver_standings',
          'constructor_standings', 'provider_mappings', 'driver_mappings',
          'constructor_mappings', 'provider_identity_cache', 'calendar_snapshots',
          'next_season_schedule')
STAMP = '2026-11-01T12:00:00Z'
STATS = '/api/v1/diagnostics/season-cache'
HOT_KEY = '/api/v1/calendar?season=2024'


def seed(path, include_history):
    with contextlib.closing(sqlite3.connect(path)) as db, db:
        db.execute('PRAGMA foreign_keys = ON')
        db.execute('INSERT INTO sync_state (provider, endpoint, last_attempt_at) VALUES (?, ?, ?)',
                   ('fixture', 'local-state', STAMP))
        if include_history:
            for year in SEASONS:
                db.execute('INSERT INTO calendar_snapshots VALUES (?, ?, 1)', (year, 'fixture'))
                db.execute('INSERT INTO provider_identity_cache VALUES (?, ?, ?, ?)',
                           (year, '[]', '[]', STAMP))
                for driver in range(1, 21):
                    db.execute('''INSERT INTO driver_standings
                        (season, position, driver_id, driver_name, constructor, points, wins,
                         source, fetched_at, quality, constructor_ids, driver_number)
                        VALUES (?, ?, ?, ?, ?, ?, 0, 'fixture', ?, 'final', ?, ?)''',
                        (year, driver, f'driver-{driver}', f'Driver {driver}',
                         f'Team {(driver + 1) // 2}', 100 - driver, STAMP,
                         json.dumps([f'team-{(driver + 1) // 2}']), str(driver)))
                for team in range(1, 11):
                    db.execute('''INSERT INTO constructor_standings
                        (season, position, constructor_id, constructor_name, points, wins,
                         source, fetched_at, quality)
                        VALUES (?, ?, ?, ?, ?, 0, 'fixture', ?, 'final')''',
                        (year, team, f'team-{team}', f'Team {team}', 200 - team, STAMP))
                for round_no in range(1, 25):
                    meeting = f'{year}:{round_no}'
                    start = datetime.date(year, 3, 1) + datetime.timedelta(days=(round_no-1)*10)
                    end = start + datetime.timedelta(days=2)
                    db.execute('''INSERT INTO meetings
                        (id, season, round, name, country, location, start_date, end_date,
                         status, source, fetched_at, jolpica_round_id)
                        VALUES (?, ?, ?, ?, 'Fixture Country', 'Fixture City', ?, ?,
                                'completed', 'fixture', ?, ?)''',
                        (meeting, year, round_no, f'Fixture GP {round_no}', start.isoformat(), end.isoformat(),
                         STAMP, meeting))
                    for index, session_type in enumerate(SESSION_TYPES):
                        session = f'{meeting}:{session_type}'
                        db.execute('''INSERT INTO sessions
                            (id, meeting_id, session_type, start_time, end_time, status, source,
                             fetched_at, openf1_session_key)
                            VALUES (?, ?, ?, ?, ?, 'completed', 'fixture', ?, ?)''',
                            (session, meeting, session_type, f'{end}T{10+index:02d}:00:00Z',
                             f'{end}T{11+index:02d}:00:00Z', STAMP,
                             year*1000 + round_no*10 + index))
                        db.execute('INSERT INTO provider_mappings VALUES (?, ?, ?, ?)',
                                   ('fixture', session, meeting, session))
                        db.executemany('''INSERT INTO session_results
                            (session_id, position, classification, driver_id, driver_name,
                             constructor_id, team, laps, points, source, fetched_at, revision,
                             quality, driver_number)
                            VALUES (?, ?, 'classified', ?, ?, ?, ?, 55, ?, 'fixture', ?, ?, ?, ?)''',
                            ((session, driver, f'driver-{driver}', f'Driver {driver}',
                              f'team-{(driver+1)//2}', f'Team {(driver+1)//2}', 20-driver, STAMP,
                              revision, 'final' if revision == 2 else 'provisional', str(driver))
                             for revision in (1, 2) for driver in range(1, 21)))
            for driver in range(1, 21):
                db.execute('INSERT INTO driver_mappings VALUES (?, ?, ?)',
                           ('fixture', str(driver), f'driver-{driver}'))
            for team in range(1, 11):
                db.execute('INSERT INTO constructor_mappings VALUES (?, ?, ?)',
                           ('fixture', str(team), f'team-{team}'))
    return sqlite_summary(path, vacuum=True)


def sqlite_summary(path, *, vacuum=False):
    with contextlib.closing(sqlite3.connect(path)) as db:
        db.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchall()
        if vacuum:
            db.execute('VACUUM')
            db.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchall()
        counts = {table: db.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
                  for table in (*TABLES, 'sync_state')}
        assert db.execute('PRAGMA foreign_key_check').fetchall() == []
    return {'bytes': path.stat().st_size, 'rows': counts}


def free_port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        return listener.getsockname()[1]


def get(port, path):
    client = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
    try:
        client.request('GET', path)
        response = client.getresponse()
        return response.status, json.loads(response.read())
    finally:
        client.close()


@contextlib.contextmanager
def server(binary, database, config, env, log):
    port = free_port()
    env = env | {'F1_COMPANION_DATABASE_PATH': str(database),
                 'F1_COMPANION_BIND': f'127.0.0.1:{port}', 'F1_COMPANION_CONFIG': str(config)}
    with open(log, 'w') as handle:
        proc = subprocess.Popen([binary], env=env, stdout=handle, stderr=handle)
        try:
            for _ in range(250):
                if proc.poll() is not None:
                    break
                try:
                    if get(port, '/api/v1/health')[0] == 200:
                        break
                except (OSError, http.client.HTTPException):
                    pass
                time.sleep(0.02)
            else:
                raise RuntimeError(f'server startup timed out, see {log}')
            if proc.poll() is not None:
                raise RuntimeError(f'server exited {proc.returncode}, see {log}')
            yield port
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


def paths(index):
    year = list(SEASONS)[(index // 4) % len(SEASONS)]
    round_no = 1 + ((index // (4*len(SEASONS))) % 24)
    return (f'/api/v1/calendar?season={year}', f'/api/v1/standings/drivers?season={year}',
            f'/api/v1/standings/constructors?season={year}',
            f'/api/v1/sessions/{year}:{round_no}:race/results')[index % 4]


async def workload(port, count, concurrency, path_for):
    latencies, statuses = [], collections.Counter()
    gate = asyncio.Event()
    connections = await asyncio.gather(*[asyncio.open_connection('127.0.0.1', port)
                                         for _ in range(concurrency)])

    async def worker(index, reader, writer):
        await gate.wait()
        try:
            for request in range(index, count, concurrency):
                started = time.perf_counter_ns()
                try:
                    reply = f'GET {path_for(request)} HTTP/1.1\r\nHost: localhost\r\n\r\n'
                    writer.write(reply.encode('ascii'))
                    await writer.drain()
                    headers = await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'), timeout=10)
                    lines = headers.split(b'\r\n')
                    status = int(lines[0].split()[1])
                    length = next(int(line.split(b':', 1)[1]) for line in lines[1:]
                                  if line.lower().startswith(b'content-length:'))
                    await asyncio.wait_for(reader.readexactly(length), timeout=10)
                except (OSError, ValueError, EOFError, TimeoutError, StopIteration):
                    status = 'transport-error'
                latencies.append((time.perf_counter_ns()-started)/1_000_000)
                statuses[str(status)] += 1
                if status == 'transport-error':
                    raise RuntimeError('HTTP load client lost framing or a connection')
        finally:
            writer.close()
            await writer.wait_closed()

    workers = [asyncio.create_task(worker(i, *conn)) for i, conn in enumerate(connections)]
    started = time.perf_counter()
    gate.set()
    await asyncio.gather(*workers)
    elapsed = time.perf_counter() - started
    latencies.sort()
    return {'concurrency': concurrency, 'requests': count,
            'p50_ms': latencies[math.ceil(.50*count)-1],
            'p95_ms': latencies[math.ceil(.95*count)-1],
            'p99_ms': latencies[math.ceil(.99*count)-1],
            'requests_per_second': count/elapsed,
            'errors': count-statuses['200'], 'error_rate': 1-statuses['200']/count,
            'statuses': dict(statuses)}


def measure(port, count, concurrency, path_for, central):
    before = get(port, STATS)[1]['data'] if central else None
    results = asyncio.run(workload(port, count, concurrency, path_for))
    after = get(port, STATS)[1]['data'] if central else None
    results['cache'] = {key: after[key]-before[key] for key in after} if central else None
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--legacy', type=Path, required=True)
    parser.add_argument('--central', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--requests', type=int, default=2400)
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    if args.requests < 64 or args.repeats < 1:
        parser.error('at least 64 requests and one repeat are required')
    dsn = os.environ['PITPULSE_BENCH_LOCAL_URL']
    read_dsn = os.getenv('PITPULSE_BENCH_LOCAL_READ_URL', dsn)
    for url in (dsn, read_dsn):
        if urllib.parse.urlsplit(url).hostname not in ('127.0.0.1', '::1', 'localhost'):
            parser.error('the benchmark requires loopback Postgres')
    schema = f'pitpulse_bench_{int(time.time())}_{os.getpid()}'
    # Only allow loopback outbound access for the HTTP processes during this test.
    env = {key: value for key, value in os.environ.items() if not key.startswith(
        ('PITPULSE_', 'F1_COMPANION_'))}
    env |= {'RUST_LOG': 'error', 'TOKIO_WORKER_THREADS': '8'}
    for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy'):
        env[key] = 'http://127.0.0.1:1'
    env |= {'NO_PROXY': '127.0.0.1,localhost,::1', 'no_proxy': '127.0.0.1,localhost,::1'}
    write_env = env | {'PITPULSE_SEASON_WRITE_DATABASE_URL': dsn, 'PITPULSE_SEASON_SCHEMA': schema}
    role = os.getenv('PITPULSE_BENCH_LOCAL_READER_ROLE')
    if role:
        write_env['PITPULSE_SEASON_READER_ROLE'] = role
    read_env = env | {'PITPULSE_SEASON_READ_DATABASE_URL': read_dsn, 'PITPULSE_SEASON_SCHEMA': schema}
    args.out.mkdir(parents=True, exist_ok=True)
    report = {'schema': schema, 'repeats': args.repeats, 'rows': [], 'sqlite_after_load': []}
    with tempfile.TemporaryDirectory(prefix='pp57-fixture-', dir=args.out) as tmp:
        work = Path(tmp)
        config = work/'isolated.toml'
        config.write_text('''[server]
bind = "127.0.0.1:38701"
[database]
path = "unused.sqlite"
[providers]
jolpica_enabled = false
openf1_enabled = false
f1_live_enabled = false
f1_telemetry_relay_enabled = false
wec_live_enabled = false
user_agent = "PitPulse-Local-Benchmark"
[live]
snapshot_interval_seconds = 15
stale_after_seconds = 60
[security]
require_token = false
[scheduler]
calendar_interval_seconds = 21600
standings_interval_seconds = 21600
''')
        fixture, empty = work/'history.sqlite', work/'clean.sqlite'
        for path, include_history in ((fixture, True), (empty, False)):
            with server(args.legacy.resolve(), path, config, env, args.out/'initialize.log'):
                pass
            report['legacy_sqlite' if include_history else 'central_sqlite'] = seed(path, include_history)

        def season_data(*command):
            return subprocess.check_output([args.central.resolve(), 'season-data', *command],
                                           env=write_env)

        season_data('migrate')
        report['import'] = json.loads(season_data('import', fixture))
        report['verify'] = json.loads(season_data('verify', fixture))
        assert all(row['source'] == row['verified'] == row['inserted'] for row in report['import'])
        assert all(row['source'] == row['verified'] and row['inserted'] == 0 for row in report['verify'])
        matrix = [('sqlite', args.legacy, fixture, env),
                  ('pg_cold', args.central, empty, read_env | {'PITPULSE_SEASON_CACHE_CAPACITY': '0'}),
                  ('pg_warm', args.central, empty, read_env)]
        fixture_paths = sorted({paths(i) for i in range(4*len(SEASONS)*24)})
        expected = {}
        for repeat in range(args.repeats):
            for mode, binary, original, mode_env in matrix:
                sqlite_path = work/'run.sqlite'
                shutil.copyfile(original, sqlite_path)
                with server(binary.resolve(), sqlite_path, config, mode_env,
                            args.out/f'{mode}-{repeat}.log') as port:
                    # Let the server's current-season startup preloads settle.
                    time.sleep(1)
                    if mode == 'pg_warm' and repeat == 0:
                        burst = measure(port, 64, 64, lambda _: HOT_KEY, True)
                        report['cold_same_key_burst'] = burst
                        assert burst['errors'] == 0 and burst['cache']['originLoads'] == 1, burst
                        assert burst['cache']['hits'] >= 63, burst
                    for path in fixture_paths:
                        value = get(port, path)
                        assert value[0] == 200 and value[1]['data'], path
                        if mode == 'sqlite' and repeat == 0:
                            expected[path] = value
                        else:
                            assert value == expected[path], path
                    for concurrency in (1, 16, 64):
                        row = measure(port, args.requests, concurrency, paths, mode != 'sqlite')
                        row |= {'mode': mode, 'repeat': repeat+1}
                        report['rows'].append(row)
                        print(json.dumps(row), flush=True)
                summary = sqlite_summary(sqlite_path)
                if mode != 'sqlite':
                    assert all(summary['rows'][table] == 0 for table in TABLES), summary
                report['sqlite_after_load'].append(summary | {'mode': mode, 'repeat': repeat+1})
                sqlite_path.unlink()
    (args.out/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'Results written to {args.out/"results.json"}', flush=True)
    if any(row['errors'] for row in report['rows']):
        raise SystemExit('unexpected HTTP errors; see results.json')


if __name__ == '__main__':
    main()
