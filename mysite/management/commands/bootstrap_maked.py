"""Rebuild the MAKED page tree on the modernised django CMS.

The original database was created with django CMS 3.6, which stored a separate
draft and published row for every page (the "publisher"). django CMS 4.0
removed the publisher entirely, so that schema cannot be migrated forward.
This command recreates the site's structure and content on the current schema.

The page tree mirrors the project's name: one page per letter of MAKED, in the
order the logo draws them around the centre, plus the utility pages the
original site carried.

    python manage.py bootstrap_maked

The command is idempotent: running it twice will not duplicate pages.
"""
import os

from django.core.management.base import BaseCommand

from cms.api import add_plugin, create_page
from cms.models import CMSPlugin, Page
from cms.utils import get_current_site

# The five domains, in the clockwise order the logo draws them, with the role
# the original site's placeholder text gave each one.
DOMAINS = [
    ("model", "Model", "M", "the model formulator"),
    ("attack", "Attack", "A", "the attack generator"),
    ("knowledge", "Knowledge", "K", "the knowledge distiller"),
    ("experience", "Experience", "E", "the experience absorber"),
    ("data", "Data", "D", "the data turbine"),
]

HOME_BODY = """
<p style="text-align:center;">
  <img src="/static/img/logo-maked.jpg" alt="MAKED" width="260">
</p>
<h2>What this is</h2>
<p>MAKED is a framework for automated AI testing. It organises the work into
five domains, one for each letter of its name, and keeps them in a cycle: each
domain consumes what the previous one produced.</p>
<div class="maked-domains">
  <div class="maked-domain maked-domain--M">
    <span class="letter">M</span><span class="name">Model</span>
    <span class="role">the model formulator</span>
  </div>
  <div class="maked-domain maked-domain--D">
    <span class="letter">D</span><span class="name">Data</span>
    <span class="role">the data turbine</span>
  </div>
  <div class="maked-domain maked-domain--E">
    <span class="letter">E</span><span class="name">Experience</span>
    <span class="role">the experience absorber</span>
  </div>
  <div class="maked-domain maked-domain--A">
    <span class="letter">A</span><span class="name">Attack</span>
    <span class="role">the attack generator</span>
  </div>
  <div class="maked-domain maked-domain--K">
    <span class="letter">K</span><span class="name">Knowledge</span>
    <span class="role">the knowledge distiller</span>
  </div>
</div>
"""

ABOUT_BODY = """
<h2>About MAKED</h2>
<p>MAKED &mdash; <strong>M</strong>odel, <strong>A</strong>ttack,
<strong>K</strong>nowledge, <strong>E</strong>xperience,
<strong>D</strong>ata &mdash; is a Django CMS site that serves as a knowledge
base for automated AI testing.</p>
<p>The five domains are the project's ontology. Each is a Django application
and a top-level page, so the navigation of the site is the structure of the
work itself.</p>
<p>This deployment runs on Django 5.2 and django CMS 5.1.</p>
"""

TUTORIAL_BODY = """
<h2>Getting started</h2>
<p>Log in at <a href="/admin/">/admin/</a> to edit any page. Each domain page
has a <em>content</em> placeholder that accepts text, images and links.</p>
<p>Background work is handled by Celery. Start a worker with
<code>celery -A mysite worker</code> and the scheduler with
<code>celery -A mysite beat</code>.</p>
"""

MONITOR_BODY = """
<h2>Celery task monitor</h2>
<p>Task monitoring is served by <a href="http://127.0.0.1:5555">flower</a>,
started separately with:</p>
<pre>celery -A mysite flower --address=127.0.0.1 --port=5555</pre>
"""


class Command(BaseCommand):
    help = "Create the MAKED page tree and its initial content."

    def add_arguments(self, parser):
        parser.add_argument(
            "--delete",
            action="store_true",
            help="Delete every existing CMS page first (destructive).",
        )

    def handle(self, *args, **options):
        site = get_current_site()

        if options["delete"]:
            count, _ = Page.objects.all().delete()
            self.stdout.write(f"Deleted {count} page objects.")
            # Removing pages orphans their plugins; clear them explicitly so a
            # second run does not accumulate dead rows.
            CMSPlugin.objects.all().delete()

        if Page.objects.exists() and not options["delete"]:
            self.stdout.write(
                self.style.WARNING(
                    "Pages already exist; nothing to do. "
                    "Use --delete to rebuild from scratch."
                )
            )
            return

        self._ensure_site(site)
        # The home page must exist (with its root URL) before its children are
        # created: a child's PageUrl.path is derived from its parent's.
        home = self._create_home(site)
        self._create_domains(site, home)
        self._create_utility_pages(site, home)

        self.stdout.write(
            self.style.SUCCESS(
                f"MAKED bootstrapped: {Page.objects.count()} pages created."
            )
        )

    # -- helpers ------------------------------------------------------------
    def _ensure_site(self, site):
        if site is None:
            raise SystemExit("No Site found; run `manage.py migrate` first.")
        site.domain = os.environ.get("MAKED_SITE_DOMAIN", "127.0.0.1:8000")
        site.name = "MAKED"
        site.save()

    def _content_placeholder(self, page):
        """Return the "content" placeholder of a freshly created page.

        django CMS 5 removed ``Page.placeholders``; placeholders are queried by
        language through ``Page.get_placeholders()``.
        """
        for placeholder in page.get_placeholders("en"):
            if placeholder.slot == "content":
                return placeholder
        raise RuntimeError(f"no 'content' placeholder on page {page!r}")

    def _create_page_with_body(
        self, site, parent, title, slug, body, in_navigation, is_home=False
    ):
        page = create_page(
            title,
            "page.html",
            language="en",
            site=site,
            slug=slug,
            in_navigation=in_navigation,
            parent=parent,
        )
        if is_home:
            # django CMS 5 routes requests by the PageUrl.path column, not by
            # the slug, and Page.get_path_for_slug() only returns "" (the root
            # path) for a page that is ALREADY flagged as home. Flipping the
            # flag after create_page() therefore leaves PageUrl.path ==
            # "index", and "/" 302s to the page-content admin instead of
            # rendering. So: set the flag, then re-derive the URL row.
            page.is_home = True
            page.save()
            page.update_urls(language="en", path="")
        add_plugin(
            self._content_placeholder(page),
            "TextPlugin",
            language="en",
            body=body,
        )
        self.stdout.write(f"  + {title}  /{slug}/")
        return page

    def _create_home(self, site):
        return self._create_page_with_body(
            site,
            None,
            "Index",
            "index",
            HOME_BODY,
            in_navigation=False,
            is_home=True,
        )

    def _create_domains(self, site, parent):
        for slug, title, letter, role in DOMAINS:
            body = (
                f'<p><img src="/static/img/logo-{letter.lower()}.jpg" '
                f'alt="MAKED logo: {letter}" width="80" align="left" '
                f'style="margin-right:18px;"></p>'
                f"<p><strong>{title}</strong> &mdash; {role}.</p>"
            )
            self._create_page_with_body(
                site, parent, title, slug, body, in_navigation=True
            )

    def _create_utility_pages(self, site, parent):
        for slug, title, body in (
            ("tutorial", "Tutorial", TUTORIAL_BODY),
            ("about", "About", ABOUT_BODY),
            ("celery-task-monitor", "celery task monitor", MONITOR_BODY),
        ):
            self._create_page_with_body(
                site, parent, title, slug, body, in_navigation=True
            )
