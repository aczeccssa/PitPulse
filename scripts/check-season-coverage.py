#!/usr/bin/env python3
"""Audit actual seasonal dashboard inputs; missing media/reports are failures.

python3 scripts/check-season-coverage.py --base-url http://127.0.0.1:38701
Read-only: performs GETs and writes nothing to the database or workspace.
"""
import argparse
import concurrent.futures
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def audit(base, season, manifest):
    def get(resource):
        with urllib.request.urlopen(f'{base}/api/v1/{resource}?season={season}', timeout=40) as response:
            return json.load(response)['data']
    entries = get('results/season')
    drivers = get('standings/drivers')
    constructors = get('standings/constructors')
    pu = get('pu-elements')
    destructors = get('destructors-championship')
    present = {(a['kind'], a['id']) for a in manifest['assets'] if a['season'] == season and not a.get('variant')}
    participants = {r['driverId'] for e in entries for s in e['sessions'].values() for r in s.get('rows', [])}
    teams = {r['constructorId'] for e in entries for s in e['sessions'].values() for r in s.get('rows', []) if r.get('constructorId')}
    missing = sorted(f'{kind}/{key}' for kinds, ids in [(['driver-photo', 'helmet'], participants), (['car-side', 'team-logo'], teams)] for kind in kinds for key in ids if (kind, key) not in present)
    race_rounds = sum(bool(e['sessions'].get('race', {}).get('rows')) for e in entries)
    qualifying_rounds = sum(bool(e['sessions'].get('qualifying', {}).get('rows')) for e in entries)
    gaps = []
    if not drivers: gaps.append('driver standings')
    if not constructors: gaps.append('constructor standings')
    if not race_rounds or not qualifying_rounds: gaps.append('H2H inputs')
    if not pu.get('usage'): gaps.append('PU usage')
    if not destructors.get('rows'): gaps.append('Destructors')
    return {'season': season, 'driverStandings': len(drivers), 'constructorStandings': len(constructors), 'raceRounds': race_rounds, 'qualifyingRounds': qualifying_rounds, 'missingSections': gaps, 'missingMedia': missing, 'complete': not gaps and not missing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', required=True)
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'server/resources/motorsport/manifest.json').read_text())
    with concurrent.futures.ThreadPoolExecutor(3) as pool:
        rows = list(pool.map(lambda season: audit(args.base_url.rstrip('/'), season, manifest), range(2021, 2027)))
    for row in rows:
        print(json.dumps(row, ensure_ascii=False))
    return 0 if all(row['complete'] for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
