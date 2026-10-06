"""Background tasks for the Knowledge domain.

The Knowledge domain is the project's "knowledge distiller": it ingests
written material so the other four domains have something to reason from.

The original project scheduled ``Knowledge.tasks.fetch_article`` every five
minutes for 131,739 runs (the count is still in the old database), but the
task body was a bare ``print``. It is implemented here for real, and is
inert unless a source is configured.
"""
import logging
import os

import requests
from celery import shared_task
from django.utils import timezone

from mysite.models import SiteSettingArticle

logger = logging.getLogger(__name__)

# Keep the request short: this runs on a schedule and must not hold a worker.
FETCH_TIMEOUT = float(os.environ.get("MAKED_FETCH_TIMEOUT", "10"))
MAX_ARTICLES = int(os.environ.get("MAKED_FETCH_MAX", "20"))


def _source_url():
    """The feed to ingest from, or None when none is configured.

    Deliberately environment-driven: the original hard-coded a private LAN
    address (http://172.16.18.16:8080) that is unreachable outside that
    network, so the task could only ever print its debug line.
    """
    return os.environ.get("MAKED_KNOWLEDGE_SOURCE_URL", "").strip() or None


@shared_task(name="Knowledge.tasks.fetch_article")
def fetch_article():
    """Fetch articles from the configured source and store them.

    Returns a small summary dict so the result is visible in celery's result
    backend and in django-celery-results.
    """
    source = _source_url()
    if not source:
        msg = "MAKED_KNOWLEDGE_SOURCE_URL is not set; nothing to fetch."
        logger.info(msg)
        return {"fetched": 0, "created": 0, "skipped": 0, "reason": "no source configured"}

    try:
        response = requests.get(source, timeout=FETCH_TIMEOUT)
        response.raise_for_status()
    except requests.RequestException as exc:
        # A scheduled task must never raise: an exception would mark the run
        # failed every five minutes and fill the result table with noise.
        logger.warning("knowledge fetch failed for %s: %s", source, exc)
        return {"fetched": 0, "created": 0, "skipped": 0, "reason": str(exc)}

    entries = _parse_entries(response.text)[:MAX_ARTICLES]
    created = 0
    for title, body in entries:
        if SiteSettingArticle.objects.filter(article_title=title).exists():
            continue
        SiteSettingArticle.objects.create(
            article_title=title[:26],
            article_content=body,
            article_create_time=timezone.now(),
        )
        created += 1

    logger.info("knowledge fetch: %d entries, %d new", len(entries), created)
    return {
        "fetched": len(entries),
        "created": created,
        "skipped": len(entries) - created,
        "reason": "",
    }


def _parse_entries(text):
    """Parse a feed into (title, body) pairs.

    Understands JSON Feed (``{"items": [{"title", "content_html"}]}``) and a
    simple line format (``TITLE<TAB>body``), so the source can be either a real
    feed or a plain generated file.
    """
    import json

    text = (text or "").strip()
    if not text:
        return []

    if text.startswith("{"):
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            logger.warning("knowledge source looked like JSON but did not parse")
            return []
        items = data.get("items") or data.get("entries") or []
        out = []
        for item in items:
            if not isinstance(item, dict):
                continue
            title = (item.get("title") or "").strip()
            body = (item.get("content_html") or item.get("content_text")
                    or item.get("summary") or "")
            if title:
                out.append((title, body))
        return out

    entries = []
    for line in text.splitlines():
        line = line.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        title, _, body = line.partition("\t")
        if not body:
            title, _, body = line.partition("|")
        title = title.strip()
        if title:
            entries.append((title, body.strip()))
    return entries
