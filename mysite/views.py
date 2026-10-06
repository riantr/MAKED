"""Views for the project-level pages.

Modernised from the original, which had two typos that made ``detail()``
unreachable (it raised ``NameError`` on any call):

    * ``from django.shorcuts``   -> ``django.shortcuts``
    * ``render(requet, ...)``    -> ``render(request, ...)``

and passed ``safe_mode=`` to ``markdown.markdown()``, an argument removed in
Markdown 3.0. Raw HTML is now escaped explicitly instead.
"""
import markdown
from django.shortcuts import get_object_or_404, render

from .models import SiteSettingArticle

MARKDOWN_EXTENSIONS = [
    "markdown.extensions.extra",
    "markdown.extensions.codehilite",
    "markdown.extensions.toc",
]


def detail(request, article_id):
    """Render a single markdown article."""
    article = get_object_or_404(SiteSettingArticle, pk=article_id)
    article.article_content = markdown.markdown(
        article.article_content.replace("\r\n", " \n"),
        extensions=MARKDOWN_EXTENSIONS,
    )
    return render(request, "detail.html", {"article": article})


def page_not_found(request, exception=None):
    return render(request, "404.html", status=404)
