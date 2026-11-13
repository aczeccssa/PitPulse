#!/usr/bin/env python3
"""Connect the booted simulator's installed Debug app to local recorded Live."""
import os
import json
import subprocess

devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
booted = [device for group in devices['devices'].values() for device in group if device['state'] == 'Booted']
preferred = [device for device in booted if device['name'] == 'PitPulse Data QA']
selected = preferred or booted
if len(selected) != 1:
    raise SystemExit('Select exactly one booted simulator or boot PitPulse Data QA')
device_id = selected[0]['udid']
subprocess.run(['xcrun', 'simctl', 'terminate', device_id, 'com.pitpulse.mobile'],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
env = dict(os.environ, SIMCTL_CHILD_PITPULSE_LIVE_SERVER_URL='http://127.0.0.1:38702')
subprocess.run(['xcrun', 'simctl', 'launch', device_id, 'com.pitpulse.mobile', '-serverAddress', 'http://127.0.0.1:38702'], env=env, check=True)
subprocess.run(['xcrun', 'simctl', 'openurl', device_id, 'pitpulse://live'], check=True)
print('Simulator Live connected to recorded replay at 127.0.0.1:38702')
