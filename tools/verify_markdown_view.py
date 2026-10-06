"""Verify the Markdown article view renders end to end.

Exercises mysite.views.detail through the full middleware stack, which is what
the RequestFactory cannot do (menus.cache_key needs request.user, installed by
AuthenticationMiddleware).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

import django  # noqa: E402

django.setup()

from django.test import Client  # noqa: E402

from mysite.models import SiteSettingArticle  # noqa: E402

article = SiteSettingArticle.objects.create(
    article_title="Render check",
    article_content=(
        "# Heading\n\nSome **markdown** with a [link](https://example.com).\n"
    ),
)

# mysite.urls already routes /articles/<id>/ to mysite.views.detail.
client = Client(SERVER_NAME="127.0.0.1", HTTP_HOST="127.0.0.1:8765")
resp = client.get("/articles/%d/" % article.pk)
body = resp.content.decode("utf-8", "replace")

checks = [
    ("status 200", resp.status_code == 200),
    # The toc extension adds an id to headings, so match the tag, not "<h1>".
    ("<h1> from markdown heading", "<h1" in body and ">Heading</h1>" in body),
    ("<strong> from markdown bold", "<strong>markdown</strong>" in body),
    ("<a href> from markdown link", '<a href="https://example.com">link</a>' in body),
    ("page extends base layout", "maked-header" in body),
    ("title rendered", "Render check" in body),
]

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print("  %-4s %s" % ("PASS" if ok else "FAIL", name))

article.delete()
raise SystemExit(1 if failed else 0)
