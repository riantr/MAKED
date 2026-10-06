"""Scan every blob in the repository's history for leftover secret material.

Run after `git filter-repo` to prove the rewrite actually removed key material,
not just the paths that were listed.

    python tools/scan_history.py
"""
import re
import subprocess
import sys

PATTERNS = [
    ("private key block", re.compile(rb"BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY")),
    ("PuTTY/OpenSSH key header", re.compile(rb"^PuTTY-User-Key-File", re.M)),
    ("jwk / json web key", re.compile(rb'"kty"\s*:\s*"(?:RSA|EC|OKP)"')),
    ("aws access key id", re.compile(rb"\bAKIA[0-9A-Z]{16}\b")),
    ("github token", re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("slack token", re.compile(rb"\bxox[baprs]-[0-9A-Za-z-]{10,}\b")),
    ("generic assignment", re.compile(rb"(?i)(?:secret|password|api[_-]?key|token)\s*[=:]\s*['\"][^'\"\s]{12,}['\"]")),
    ("redis dump magic", re.compile(rb"^REDIS", re.M)),
]

SUSPICIOUS_NAMES = re.compile(
    r"(\.key$|\.pem$|\.p12$|\.pfx$|^\.env|credentials|id_rsa)"
)


def run(*args):
    return subprocess.run(args, capture_output=True).stdout


def main():
    commits = run("git", "rev-list", "--all").decode().split()
    print("scanning %d commits" % len(commits))

    hits = []
    checked = 0
    for commit in commits:
        listing = run("git", "ls-tree", "-r", commit, "--name-only").decode("utf-8", "replace")
        names = [n for n in listing.splitlines() if n]
        for name in names:
            if SUSPICIOUS_NAMES.search(name):
                hits.append((commit[:8], name, "suspicious filename"))
            blob = run("git", "cat-file", "blob", "%s:%s" % (commit, name))
            if not blob:
                continue
            checked += 1
            for label, pattern in PATTERNS:
                if pattern.search(blob):
                    hits.append((commit[:8], name, label))

    print("checked %d blobs" % checked)
    if hits:
        print("\nFOUND %d suspicious item(s):" % len(hits))
        seen = set()
        for commit, name, label in hits:
            key = (name, label)
            if key in seen:
                continue
            seen.add(key)
            print("  %s  %-50s  %s" % (commit, name[:50], label))
        raise SystemExit(1)
    print("\nno secret material found in any commit")


if __name__ == "__main__":
    main()
