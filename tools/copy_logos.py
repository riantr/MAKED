"""Copy the MAKED domain logos out of the legacy media tree into static/.

The original site stored its images in django-filer's hashed media tree. The
bootstrapped site references them as plain static files instead, so they are
copied once here rather than re-imported through the filer admin.
"""
import shutil
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
MEDIA = BASE / "media" / "filer_public"
TARGET = BASE / "mysite" / "static" / "img"

# letter -> legacy hashed filer path
LOGOS = {
    "m": "b9/0e/b90e5925-715d-4716-a919-2159b6356d03/logo-m.jpg",
    "a": "c8/6e/c86e46e7-5e35-43e3-a9d5-a385604a27fc/logo-a.jpg",
    "k": "f6/8a/f68a335c-83ee-4cb6-b491-b81477956bcb/logo-k.jpg",
    "e": "6b/6b/6b6b1968-ef94-48f4-aa61-0a976b60d898/logo-e.jpg",
    "d": "33/83/33834a79-9844-464d-9aba-d3b5b936a882/logo-d.jpg",
    "maked": "ef/c6/efc6b720-b873-43e6-b63e-4f691212b111/logo-maked.jpg",
}


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    missing = []
    for name, rel in LOGOS.items():
        src = MEDIA / rel
        dst = TARGET / f"logo-{name}.jpg"
        if not src.is_file():
            missing.append(str(src))
            print(f"MISSING  {src}")
            continue
        shutil.copyfile(src, dst)
        print(f"ok  {dst.name}  {dst.stat().st_size} bytes")
    if missing:
        raise SystemExit(f"{len(missing)} file(s) not found under {MEDIA}")


if __name__ == "__main__":
    main()
