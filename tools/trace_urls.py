"""Trace what actually happens for each URL, using Django's test client.

Run:  python tools/trace_urls.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

import django  # noqa: E402

django.setup()

from django.test import Client  # noqa: E402

from cms.models import Page  # noqa: E402

print("=== page tree ===")
for p in Page.objects.all().order_by("path"):
    print(
        "  id=%-3s path=%-10s depth=%s parent=%s is_home=%s url=%r"
        % (
            p.pk,
            p.path,
            p.depth,
            p.parent_id,
            p.is_home,
            p.get_absolute_url(),
        )
    )

print()
print("=== redirect trace ===")
client = Client(follow=False, SERVER_NAME="127.0.0.1", HTTP_HOST="127.0.0.1:8765")
for url in ["/", "/index/", "/model/", "/about/"]:
    r = client.get(url)
    chain = [(r.status_code, r.get("Location", ""))]
    cur = r
    hops = 0
    while cur.status_code in (301, 302) and hops < 5:
        loc = cur["Location"]
        if not loc.startswith("/"):
            break
        cur = client.get(loc)
        chain.append((cur.status_code, cur.get("Location", "")))
        hops += 1
    print("  %-12s -> %s" % (url, "  ".join(
        "%d%s" % (c, (" " + l) if l else "") for c, l in chain
    )))
    body = cur.content.decode("utf-8", "replace")
    has_nav = "maked-nav" in body
    has_domain = "maked-domain" in body
    title = ""
    if "<title>" in body:
        title = body.split("<title>")[1].split("</title>")[0].strip()
    print("               title=%r  nav=%s  domains=%s  len=%d"
          % (title[:40], has_nav, has_domain, len(body)))
