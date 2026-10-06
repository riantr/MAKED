"""Smoke-test the Django admin for every registered model.

verify_site.py proves the public pages render and that an admin can log in.
This checks the pages behind the login: the Data app is the only one with real
models, and django-celery-beat and django-filer contribute their own admin, so
those are the routes most likely to break on a framework upgrade.

The URL list is derived from the live admin registry rather than hard-coded.
That matters: the Data app's label is "Data" (capitalised), so its changelist
lives at /admin/Data/dataset/ and not /admin/data/dataset/, and celery-beat's
model is PeriodicTask, giving periodictask with no underscore. Hard-coding the
paths produced two false failures.

    python tools/verify_admin.py [base_url]
"""
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

import django  # noqa: E402

django.setup()

from django.contrib import admin  # noqa: E402

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8765").rstrip("/")

failures = []


def get(path, opener):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "maked-verify"})
    try:
        resp = opener.open(req, timeout=25)
        return resp.getcode(), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


def check(label, ok, detail=""):
    print("  %-4s %s%s" % ("PASS" if ok else "FAIL", label, ("  -- " + detail) if detail else ""))
    if not ok:
        failures.append(label)


def admin_urls():
    """Return (url, label, expected_reachable) for every registered model.

    django CMS plugins register their model so permissions work, but override
    has_module_permission() to False because the object is edited inside the
    page editor and has no standalone changelist -- cms.Placeholder and
    djangocms_link.Link both do this. For those a 404 is correct behaviour; a
    404 for anything else is a regression.
    """
    from django.contrib.auth.models import User
    from django.test import RequestFactory

    superuser = User.objects.filter(is_superuser=True).first()
    request = None
    if superuser is not None:
        request = RequestFactory().get("/admin/")
        request.user = superuser

    out = []
    for model, model_admin in admin.site._registry.items():
        opts = model._meta
        reachable = True
        if request is not None:
            reachable = bool(model_admin.has_module_permission(request))
        out.append(
            (
                "/admin/%s/%s/" % (opts.app_label, opts.model_name),
                "%s.%s" % (opts.app_label, opts.object_name),
                reachable,
            )
        )
    return sorted(out)


def login():
    jar = CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    code, body = get("/admin/login/", opener)
    m = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', body)
    if not m:
        raise SystemExit("could not read a CSRF token from the login page")
    data = urllib.parse.urlencode(
        {
            "username": os.environ.get("MAKED_ADMIN_USER", "admin"),
            "password": os.environ.get("MAKED_ADMIN_PASSWORD", ""),
            "csrfmiddlewaretoken": m.group(1),
            "next": "/admin/",
        }
    ).encode()
    req = urllib.request.Request(
        BASE + "/admin/login/",
        data=data,
        headers={"Referer": BASE + "/admin/login/", "User-Agent": "maked-verify"},
    )
    try:
        resp = opener.open(req, timeout=25)
        body = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
    return opener, "Log out" in body


def main():
    opener, logged_in = login()
    print("=== authentication ===")
    check("admin login", logged_in)
    if not logged_in:
        raise SystemExit("cannot continue without a session (set MAKED_ADMIN_PASSWORD)")

    urls = admin_urls()
    reachable = [u for u in urls if u[2]]
    hidden = [u for u in urls if not u[2]]

    print()
    print("=== %d reachable admin changelists ===" % len(reachable))
    for path, label, _ in reachable:
        code, body = get(path, opener)
        crashed = "Exception Type" in body or "Server Error" in body
        check("%-34s %s" % (label, path), code == 200 and not crashed, "got %s" % code)

    if hidden:
        # These are registered so permissions work, but they are not part of
        # the admin navigation: django CMS edits them inside the page editor.
        # Their URL response is an implementation detail (cms.Placeholder and
        # djangocms_link.Link 404, cms.Page answers 200), so assert nothing
        # about it -- just record that they were skipped.
        print()
        print("=== %d models not in the admin nav (skipped) ===" % len(hidden))
        for path, label, _ in hidden:
            print("  SKIP  %-34s %s" % (label, path))

    print()
    if failures:
        print("FAILED %d check(s): %s" % (len(failures), ", ".join(failures)))
        raise SystemExit(1)
    print(
        "ALL ADMIN CHECKS PASSED (%d pages, %d not in admin nav)"
        % (len(reachable), len(hidden))
    )


if __name__ == "__main__":
    main()
