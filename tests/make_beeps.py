# Regenerates drs_armed.wav and drs_open.wav. Usage: python tests/make_beeps.py <output folder>
import math, struct, sys, wave
RATE = 44100
def tone(freq, ms, amp=0.6):
    n = int(RATE * ms / 1000); fade = int(RATE * 0.006)
    out = []
    for i in range(n):
        env = min(1.0, i / fade, (n - 1 - i) / fade)
        s = math.sin(2 * math.pi * freq * i / RATE) + 0.25 * math.sin(4 * math.pi * freq * i / RATE)
        out.append(amp * env * s / 1.25)
    return out
def silence(ms): return [0.0] * int(RATE * ms / 1000)
def save(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 32767)) for s in samples))
d = sys.argv[1]
save(d + '/drs_armed.wav', tone(880, 90) + silence(70) + tone(880, 90))
save(d + '/drs_open.wav', tone(1320, 180))
