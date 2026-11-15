"""Write down how one job went: its step outcomes, the facts it measured and the end of its log.

Each job uploads the result as a small file. The publish job gathers them into status.json,
so a build that failed can be understood from the repository alone.
"""

import json
import os
import sys


def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return []


def main():
    job = sys.argv[1]
    folder = os.path.join(os.environ["RUNNER_TEMP"], "note")
    os.makedirs(folder, exist_ok=True)
    steps = dict(pair.split("=", 1) for pair in os.environ.get("OUTCOMES", "").split())
    facts = {}
    for line in read_lines(os.path.join(folder, "facts")):
        if "=" in line:
            key, value = line.split("=", 1)
            facts[key.strip()] = value.strip()
    failed = "failure" in steps.values()
    tail = read_lines(os.path.join(folder, "log"))[-(60 if failed else 8):]
    note = {"job": job, "steps": steps, "facts": facts, "log_tail": [line[:300] for line in tail]}
    with open(os.path.join(folder, job + ".json"), "w", encoding="utf-8") as f:
        json.dump(note, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(json.dumps(note, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
