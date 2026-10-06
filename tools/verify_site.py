"""End-to-end verification of the running MAKED site.

Checks the pages actually render their content (not just HTTP 200), that the
navigation exposes all five domains, and that an authenticated admin session
can reach the django CMS page admin.

Run:  python tools/verify_site.py [base_url]
"""
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8765").rstrip("/")

DOMAINS = {
    "model": "Model",
    "attack": "Attack",
    "knowledge": "Knowledge",
    "experience": "Experience",
    "data": "Data",
}

failures = []


def get(path, opener=None):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "maked-verify"})
    try:
        resp = opener.open(req, timeout=25) if opener else urllib.request.urlopen(req, timeout=25)
        return resp.getcode(), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


def check(label, ok, detail=""):
    print("  %-4s %s%s" % ("PASS" if ok else "FAIL", label, ("  -- " + detail) if detail else ""))
    if not ok:
        failures.append(label)


print("=== pages render content ===")
code, home = get("/")
check("GET / -> 200", code == 200, "got %s" % code)
check("home has the five domain cards", home.count("maked-domain--") == 5,
      "found %d" % home.count("maked-domain--"))
check("home has the tagline", "automated AI testing" in home)
check("home shows the MAKED logo", "logo-maked.jpg" in home)

for slug, title in DOMAINS.items():
    code, body = get("/%s/" % slug)
    ok = code == 200 and title in body
    check("GET /%s/ renders %s" % (slug, title), ok, "got %s" % code)
    check("  %s page shows its own logo" % slug, "logo-%s.jpg" % slug[0].lower() in body)

print()
print("=== navigation ===")
code, body = get("/")
nav = re.findall(r'<a href="(/[^"]*)">\s*([^<]+?)\s*</a>', body)
found = {href.strip("/"): label.strip() for href, label in nav if href.startswith("/")}
for slug, title in DOMAINS.items():
    check("nav links to /%s/" % slug, slug in found, "nav=%s" % sorted(found))

print()
print("=== admin ===")
code, body = get("/admin/login/")
check("admin login page", code == 200 and "login-form" in body, "got %s" % code)

jar = CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
code, body = get("/admin/login/", opener)
token = ""
m = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', body)
if m:
    token = m.group(1)
check("csrf token present", bool(token))

import os

user = os.environ.get("MAKED_ADMIN_USER", "admin")
pw = os.environ.get("MAKED_ADMIN_PASSWORD", "")
if not pw:
    print("  SKIP admin login (set MAKED_ADMIN_PASSWORD)")
else:
    data = urllib.parse.urlencode(
        {"username": user, "password": pw, "csrfmiddlewaretoken": token, "next": "/admin/"}
    ).encode()
    req = urllib.request.Request(
        BASE + "/admin/login/", data=data,
        headers={"Referer": BASE + "/admin/login/", "User-Agent": "maked-verify"},
    )
    try:
        resp = opener.open(req, timeout=25)
        code, body = resp.getcode(), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        code, body = exc.code, exc.read().decode("utf-8", "replace")
    check("admin login accepted", code == 200 and "Log out" in body, "got %s" % code)

    code, body = get("/admin/cms/pagecontent/", opener)
    check("django CMS page admin reachable", code == 200, "got %s" % code)

print()
print("=== infrastructure ===")
for path, label in (
    ("/sitemap.xml", "sitemap"),
    ("/api/", "REST API root"),
    ("/static/css/maked.css", "site stylesheet"),
):
    code, _ = get(path)
    check("GET %s (%s)" % (path, label), code == 200, "got %s" % code)

print()
if failures:
    print("FAILED %d check(s): %s" % (len(failures), ", ".join(failures)))
    raise SystemExit(1)
print("ALL CHECKS PASSED")
