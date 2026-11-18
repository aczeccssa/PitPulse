#!/usr/bin/env python3
"""Recorded FIA 2021 PU table regression; run from repository root."""
import importlib.util
import json
from pathlib import Path
import sqlite3

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('fia_collector', root / 'scripts/sync-engineering.py')
fia = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fia)
text = (root / 'server/tests/fixtures/fia-usage-2021.txt').read_text()
source = {'url': 'https://www.fia.com/sites/default/files/doc_2_-_2021_abu_dhabi_grand_prix_-_pu_elements_used_per_driver_up_to_now.pdf'}
rows = fia.parse_usage(text, {'season': 2021, 'round': 22}, source)
assert len(rows) == 20
max_row = next(r for r in rows if r['driverNumber'] == 33)
assert max_row['driverName'] == 'Max Verstappen'
assert max_row['used'] == {'ice': 4, 'tc': 4, 'mgu-h': 4, 'mgu-k': 4, 'es': 3, 'ce': 3, 'ex': 7}
assert max_row['engineManufacturer'] == 'Honda'
assert next(r for r in rows if r['driverNumber'] == 47)['team'] == 'Haas'
assert next(r for r in rows if r['driverNumber'] == 14)['engineManufacturer'] == 'Renault'
assert fia.source_url(source['url']) == source['url']
try:
    fia.parse_usage('\n'.join(text.splitlines()[:42]), {'season': 2021, 'round': 22}, source)
except ValueError:
    pass
else:
    raise AssertionError('truncated table must not replace a full report')
with sqlite3.connect(':memory:') as db:
    db.execute('CREATE TABLE analysis_cache(cache_key TEXT PRIMARY KEY,value_json TEXT,fetched_at TEXT)')
    db.execute('CREATE TABLE meetings(round INTEGER,season INTEGER,status TEXT,end_date TEXT)')
    fia.save(db, 'pitpulse:fia:document:2021:22:usage', {'kind':'usage','round':22,'rows':rows}, {'fetchedAt':'2021-12-09T13:30:00Z','publishedAt':'2021-12-09T13:30:00Z'})
    fia.rebuild(db, 2021, '2021-12-13T00:00:00Z')
    elements = json.loads(db.execute("SELECT value_json FROM analysis_cache WHERE cache_key='pitpulse:fia:elements:2021'").fetchone()[0])['data']
    assert [e['code'] for e in elements] == list(max_row['used'])
    assert all(e['quota'] is None for e in elements)
print('PASS: historical MGU-H/EX columns, team/engine ownership, truncated input rejection, stored season columns')
