#!/usr/bin/env python3
"""Connect the booted simulator's installed Debug app to local recorded Live."""
import os
import subprocess

subprocess.run(['xcrun', 'simctl', 'terminate', 'booted', 'com.pitpulse.mobile'],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
env = dict(os.environ, SIMCTL_CHILD_PITPULSE_LIVE_SERVER_URL='http://127.0.0.1:38702')
subprocess.run(['xcrun', 'simctl', 'launch', 'booted', 'com.pitpulse.mobile'], env=env, check=True)
subprocess.run(['xcrun', 'simctl', 'openurl', 'booted', 'pitpulse://live'], check=True)
print('Simulator Live connected to recorded replay at 127.0.0.1:38702')
