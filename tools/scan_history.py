"""Scan every blob object in the repository for secret material.

Uses `git cat-file --batch-all-objects` so the whole object database is read in
a single pass rather than one subprocess per file. This checks *objects*, not
just paths reachable from a branch, so a secret that survived in an unreachable
object would still be caught.

Shape-based rules produce false positives on third-party assets: a syntax
highlighter legitimately contains `token: 'constant.language'`, and a licence
file contains the word "REDISTRIBUTE". Those are filtered below rather than
being left for a human to dismiss.

    python tools/scan_history.py
"""
import re
import subprocess
import sys

PATTERNS = [
    ("private key block", re.compile(rb"BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY")),
    ("putty key header", re.compile(rb"^PuTTY-User-Key-File", re.M)),
    ("json web key", re.compile(rb'"kty"\s*:\s*"(?:RSA|EC|OKP)"')),
    ("aws access key id", re.compile(rb"\bAKIA[0-9A-Z]{16}\b")),
    ("github token", re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("slack token", re.compile(rb"\bxox[baprs]-[0-9A-Za-z-]{10,}\b")),
    # A real Redis RDB starts with a version banner, not the bare word.
    ("redis dump", re.compile(rb"^REDIS\d{6}\x00", re.M)),
    (
        "django SECRET_KEY",
        re.compile(rb"(?i)\bSECRET_KEY\s*=\s*['\"][^'\"\s]{24,}['\"]"),
    ),
    (
        "hardcoded secret assignment",
        re.compile(
            rb"(?i)(?:api[_-]?key|access[_-]?key|password|token)"
            rb"\s*[=:]\s*['\"][^'\"\s]{12,}['\"]"
        ),
    ),
]

# Values that are obviously placeholders rather than credentials.
PLACEHOLDER = re.compile(
    rb"(django-insecure|example\.(com|org)|your[-_]|changeme|<[^>]+>|xxx+|\.\.\.|removed)",
    re.I,
)

# Values that only look secret-shaped because they are editor, CSS or build
# metadata ("token: 'constant.language'", accessKey: "advAccessKey").
BENIGN_VALUE = re.compile(
    rb"['\"]?(?:constant|support|punctuation|keyword|entity|variable|meta|"
    rb"storage|tag|attribute|string|comment|matchingbracket|adjacentbracket|"
    rb"bracket|invalid|number|builtin|section|selector|property|value|"
    rb"definition|namespace|markup|doctype|prolog|cdata|"
    rb"adv[A-Z]\w*)\b",
    re.I,
)

# Third-party asset trees: not project configuration, and shipping a vendored
# copy of someone else's bundle is the norm for this kind of site.
VENDOR_PATH = re.compile(
    rb"^(?:static/(?!.*(?:maked\.css))"
    rb"|media/|.*\.(?:min\.js|min\.css|map)$)",
    re.I,
)

SUSPICIOUS_NAMES = re.compile(
    r"(\.key$|\.pem$|\.p12$|\.pfx$|^\.env|credentials|id_rsa|dump\.rdb$)"
)


def is_noise(label, data, matched):
    """Decide whether a hit is a false positive."""
    if PLACEHOLDER.search(matched):
        return True
    if label in ("hardcoded secret assignment", "django SECRET_KEY"):
        if BENIGN_VALUE.search(matched):
            return True
        # A secret-shaped assignment inside a third-party bundle is not ours to
        # fix, but it is still worth reporting once with the path.
    return False


def main():
    # Enumerate blob objects.
    proc = subprocess.run(
        ["git", "cat-file", "--batch-all-objects", "--batch-check=%(objectname) %(objecttype)"],
        capture_output=True,
    )
    blobs = [
        line.split()[0].decode()
        for line in proc.stdout.splitlines()
        if line.endswith(b" blob")
    ]
    print("blob objects in repository: %d" % len(blobs))

    # Map each blob to a path so hits are actionable.
    path_of = {}
    for commit in subprocess.run(
        ["git", "rev-list", "--all"], capture_output=True
    ).stdout.decode().split():
        out = subprocess.run(
            ["git", "ls-tree", "-r", commit], capture_output=True
        ).stdout.decode("utf-8", "replace")
        for line in out.splitlines():
            parts = line.split("\t", 1)
            if len(parts) != 2:
                continue
            meta = parts[0].split()
            if len(meta) >= 3 and meta[1] == "blob":
                path_of.setdefault(meta[2], parts[1])

    hits = []
    checked = 0
    # One request, one response. Writing every oid before reading any response
    # deadlocks once the pipe buffer fills.
    reader = subprocess.Popen(
        ["git", "cat-file", "--batch"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    for oid in blobs:
        reader.stdin.write((oid + "\n").encode())
        reader.stdin.flush()
        header = reader.stdout.readline()
        if not header:
            break
        parts = header.split()
        if len(parts) < 3:
            continue
        data = reader.stdout.read(int(parts[2]))
        reader.stdout.read(1)  # trailing newline
        checked += 1
        for label, pattern in PATTERNS:
            m = pattern.search(data)
            if m and not is_noise(label, data, m.group(0)):
                hits.append((parts[0].decode()[:10], label, path_of.get(oid, "?")))
    reader.stdin.close()
    reader.wait()

    print("scanned %d blobs" % checked)
    if hits:
        print("\nFOUND %d match(es):" % len(hits))
        for oid, label, path in hits[:40]:
            print("  %s  %-28s  %s" % (oid, label, path[:60]))
        raise SystemExit(1)
    print("\nno secret material found in any object")


if __name__ == "__main__":
    main()
