"""Inspect the 2019 Redis dump for anything worth preserving.

The dump was removed from git, but before the backup directory is deleted it
is worth knowing what was in it: MAKED used Redis as the Celery broker, so it
may hold queued task payloads or cached responses that are not recoverable from
the SQLite database.

Prints a summary of key counts and any strings that look like keys, so the
question "is there data here worth keeping?" can be answered without a running
Redis server.

    python tools/inspect_dump_rdb.py [path-to-dump.rdb]
"""
import collections
import re
import sys
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / "dump.rdb"

# An RDB file is a stream of opcodes. We do not decode it -- redis is not
# guaranteed to be installed -- but the string table at the head and the
# readable key names are enough to answer the question.
KEYLIKE = re.compile(rb"[\x20-\x7e]{4,120}")

# Byte values that dominate an RDB payload and carry no information.
NOISE = re.compile(rb"^[\x00-\x08\x0b-\x1f]+$")


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    if not path.is_file():
        raise SystemExit(f"no dump at {path}")

    data = path.read_bytes()
    print("file:   %s" % path)
    print("size:   %.1f MB" % (len(data) / 1024 / 1024))
    header = data[:9]
    print("header: %r" % header)
    if not header.startswith(b"REDIS"):
        print("  (not a Redis RDB file -- magic bytes missing)")

    counts = collections.Counter()
    samples = collections.defaultdict(list)
    for m in KEYLIKE.finditer(data):
        s = m.group(0)
        if NOISE.match(s):
            continue
        # Celery broker keys look like these; that is the interesting part.
        for kind, pattern in (
            ("celery-task-meta", rb"^celery-task-meta-"),
            ("celery", rb"^celery"),
            ("kombu", rb"^(kombu|amqp|_kombu)"),
            ("django", rb"^django"),
            ("session", rb"^.*_session"),
            ("unbound", rb"^unbound"),
        ):
            if re.match(pattern, s):
                counts[kind] += 1
                if len(samples[kind]) < 5:
                    samples[kind].append(s[:100].decode("utf-8", "replace"))
                break

    print()
    if counts:
        print("key-like entries found:")
        for kind, n in counts.most_common():
            print("  %-18s %d" % (kind, n))
            for s in samples[kind]:
                print("      %s" % s)
    else:
        print("no recognisable key names in the payload")

    # The most useful signal: are there any celery task result payloads?
    n_meta = len(re.findall(rb"celery-task-meta-", data))
    print()
    print("celery-task-meta occurrences: %d" % n_meta)
    if n_meta:
        print(
            "  -> the broker had completed task results cached; these are NOT"
            " in the SQLite database and are lost with the dump."
        )


if __name__ == "__main__":
    main()
