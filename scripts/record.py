"""Record a finished run in the repository: status.json always, LATEST.md after a real release.

Run it from the repository checkout. It reads the notes each job left, the outcome of the
publish steps and what the release holds.
"""

import datetime
import glob
import json
import os


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def pairs(text):
    return dict(pair.split("=", 1) for pair in (text or "").split())


def main():
    temp = os.environ["RUNNER_TEMP"]
    out = os.environ.get("OUT") or os.path.join(temp, "out")
    steps = pairs(os.environ.get("OUTCOMES"))
    rehearsal = bool(os.environ.get("REHEARSAL_URL"))
    release = read_json(os.path.join(out, "release.json"))
    status = {
        "finished": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "run": os.environ.get("RUN_URL"),
        "rehearsal": rehearsal,
        "published": steps.get("release") == "success" and release is not None and not rehearsal,
        "release": release,
        "jobs": pairs(os.environ.get("NEEDS")),
        "steps": steps,
        "source": read_json(os.path.join(out, "source.json")),
        "notes": {},
    }
    for path in sorted(glob.glob(os.path.join(temp, "notes", "*.json"))):
        note = read_json(path, {})
        status["notes"][note.get("job") or os.path.basename(path)[:-5]] = {
            "steps": note.get("steps"), "facts": note.get("facts"), "log_tail": note.get("log_tail")}
    if steps.get("release") != "success":
        try:
            with open(os.path.join(temp, "notes", "publish.log"), encoding="utf-8", errors="replace") as f:
                status["publish_log_tail"] = [line[:300] for line in f.read().splitlines()[-40:]]
        except OSError:
            pass
    with open("status.json", "w", encoding="utf-8") as f:
        json.dump(status, f, indent=1, ensure_ascii=False)
        f.write("\n")
    if status["published"]:
        with open("LATEST.md", "w", encoding="utf-8") as f:
            f.write("# Latest build\n\n" + open(os.path.join(out, "notes.md"), encoding="utf-8").read()
                    + "\nChecksums:\n\n```\n" + open(os.path.join(out, "SHA256SUMS"), encoding="utf-8").read() + "```\n")
    print(json.dumps(status, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
