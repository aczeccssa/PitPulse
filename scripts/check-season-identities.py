#!/usr/bin/env python3
"""Regression: a stable driver retains distinct seasonal numbers and media."""
import importlib.util
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('artwork_collector', root / 'server/resources/motorsport/collect.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
roster = {'seasons': {}}
for year, number, team in [(2021, '33', 'red_bull'), (2022, '1', 'red_bull')]:
    roster['seasons'][str(year)] = {'drivers': {'max_verstappen': {'name': 'Max Verstappen', 'code': 'VER', 'constructors': [team], 'appearances': [{'round': 1, 'driverNumber': number, 'constructorId': team, 'constructorName': 'Red Bull Racing'}]}}}
assets = [{'season': 2021, 'kind': 'driver-photo', 'id': 'max_verstappen', 'file': '2021/driver-photo/max_verstappen.png'}]
identities = collector.season_identities(roster, assets)
seasons = identities['drivers']['max_verstappen']['seasons']
assert seasons['2021']['driverNumbers'] == ['33']
assert seasons['2022']['driverNumbers'] == ['1']
assert seasons['2021']['photo'] == '2021/driver-photo/max_verstappen.png'
assert seasons['2022']['photo'] is None, 'missing media must not carry another year forward'
assert identities['constructors']['red_bull']['seasons']['2021']['name'] == 'Red Bull Racing'
print('PASS: stable identity, seasonal numbers, independent media, historical team name')
