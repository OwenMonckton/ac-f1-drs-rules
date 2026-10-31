# Simulated races against F1DRSRules.lua with mocked CSP APIs.
# Usage: pip install lupa; python tests/run.py [path/to/F1DRSRules.lua]
import os, sys
from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'apps', 'lua', 'F1DRSRules', 'F1DRSRules.lua')
HARNESS = os.path.join(HERE, 'harness.lua')
app_src = open(APP, encoding='utf-8').read()
harness_src = open(HARNESS, encoding='utf-8').read()

BAHRAIN = [
    {'DETECTION': 0.889, 'START': 0.964, 'END': 0.127},
    {'DETECTION': 0.127, 'START': 0.185, 'END': 0.272},
    {'DETECTION': 0.477, 'START': 0.5166, 'END': 0.630},
]
LT = 90.0

def cars(*gaps_behind_leader, pit=None):
    # leader at 0.05; other cars placed by seconds behind leader
    out = []
    for i, g in enumerate(gaps_behind_leader):
        c = {'pos': 0.05 - g / LT, 'lapTime': LT}
        if pit is not None and pit[0] == i:
            c['pitOnLap'] = pit[1]
        out.append(c)
    return out

def run(name, scenario):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.APP_SOURCE = app_src
    def tolua(o):
        if isinstance(o, dict):
            t = L.table()
            for k, v in o.items(): t[k] = tolua(v)
            return t
        if isinstance(o, list):
            t = L.table()
            for i, v in enumerate(o): t[i + 1] = tolua(v)
            return t
        return o
    g.SCENARIO = tolua(scenario)
    L.execute(harness_src)
    r = g.RESULT
    print(f'== {name}')
    for i in range(len(scenario['cars'])):
        print(f'  car{i}: unlocked lap1={r.lap1[i]}  passes: {r.unlock[i] or "(none)"}')
    msgs = [r.messages[i] for i in range(1, len(r.messages) + 1)]
    for m in msgs[:4]:
        print('   msg', m)
    for i in range(1, len(r.beeps) + 1):
        print('   beep', r.beeps[i])
    return r

# order on road: car1 leads, car0 0.8 s behind, car2 1.5 s behind car0
run('bahrain: car1 leads, car0 +0.8s, car2 +1.5s behind car0, 3 laps',
    {'zones': BAHRAIN, 'cars': [cars(0.8, 0.0, 2.3)[0], cars(0.8, 0.0, 2.3)[1], cars(0.8, 0.0, 2.3)[2]], 'duration': 3 * LT + 5})
run('practice session (rules off by default)',
    {'zones': BAHRAIN, 'cars': cars(0.8, 0.0), 'duration': 2 * LT + 5, 'session': 1})
run('no drs_zones.ini (whole lap from line), car0 0.5s behind car1',
    {'zones': [], 'cars': cars(0.5, 0.0), 'duration': 3 * LT + 5})
run('car1 pits on lap 2: car0 should lose gap reference while car1 in pitlane',
    {'zones': BAHRAIN, 'cars': cars(0.8, 0.0, pit=(1, 2)), 'duration': 3 * LT + 5})
