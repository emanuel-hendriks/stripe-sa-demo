"""Shared tee-logger: writes stdout to both terminal and a log file in demo/logs/."""
import sys, os, time

LOGS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")

class Tee:
    def __init__(self, logfile):
        os.makedirs(os.path.dirname(logfile), exist_ok=True)
        self.file = open(logfile, "w")
        self.stdout = sys.stdout
    def write(self, data):
        self.stdout.write(data)
        self.file.write(data)
    def flush(self):
        self.stdout.flush()
        self.file.flush()

def start_log(name):
    ts = time.strftime("%Y%m%d-%H%M%S")
    path = f"{LOGS_DIR}/{name}-{ts}.log"
    sys.stdout = Tee(path)
    return path
