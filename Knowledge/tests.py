"""Tests for the Knowledge domain's background task.

Run:  python manage.py test Knowledge
"""
from unittest import mock

from django.test import TestCase

from mysite.models import SiteSettingArticle
from Knowledge.tasks import _parse_entries, fetch_article


class ParseEntriesTests(TestCase):
    def test_json_feed(self):
        payload = (
            '{"items": ['
            '{"title": "First", "content_html": "<p>one</p>"},'
            '{"title": "Second", "content_text": "two"}'
            "]}"
        )
        self.assertEqual(
            _parse_entries(payload),
            [("First", "<p>one</p>"), ("Second", "two")],
        )

    def test_json_content_html_wins_over_text(self):
        payload = '{"items": [{"title": "T", "content_html": "<b>h</b>", "content_text": "t"}]}'
        self.assertEqual(_parse_entries(payload), [("T", "<b>h</b>")])

    def test_malformed_json_is_ignored(self):
        self.assertEqual(_parse_entries('{"items": [ broken'), [])

    def test_tab_separated_lines(self):
        self.assertEqual(
            _parse_entries("Alpha\tbody a\nBeta\tbody b"),
            [("Alpha", "body a"), ("Beta", "body b")],
        )

    def test_pipe_separated_lines(self):
        self.assertEqual(_parse_entries("Alpha|body a"), [("Alpha", "body a")])

    def test_comments_and_blanks_skipped(self):
        self.assertEqual(_parse_entries("# note\n\nAlpha\tx\n"), [("Alpha", "x")])

    def test_empty_input(self):
        self.assertEqual(_parse_entries(""), [])
        self.assertEqual(_parse_entries("   \n"), [])


class FetchArticleTests(TestCase):
    def test_no_source_configured_is_inert(self):
        """The task must be a safe no-op when no feed is configured."""
        with mock.patch.dict("os.environ", {}, clear=False):
            import os

            os.environ.pop("MAKED_KNOWLEDGE_SOURCE_URL", None)
            result = fetch_article()
        self.assertEqual(result["created"], 0)
        self.assertIn("no source", result["reason"])
        self.assertEqual(SiteSettingArticle.objects.count(), 0)

    def test_creates_articles_and_skips_existing_titles(self):
        payload = (
            '{"items": ['
            '{"title": "Alpha", "content_html": "<p>a</p>"},'
            '{"title": "Beta", "content_html": "<p>b</p>"}'
            "]}"
        )
        with mock.patch("Knowledge.tasks.requests.get") as get:
            get.return_value = mock.Mock(
                text=payload, raise_for_status=mock.Mock()
            )
            with mock.patch.dict(
                "os.environ", {"MAKED_KNOWLEDGE_SOURCE_URL": "http://example/feed"}
            ):
                first = fetch_article()
        self.assertEqual(first["created"], 2)
        self.assertEqual(SiteSettingArticle.objects.count(), 2)

        # A second run must not duplicate: the task runs every 5 minutes.
        with mock.patch("Knowledge.tasks.requests.get") as get:
            get.return_value = mock.Mock(
                text=payload, raise_for_status=mock.Mock()
            )
            with mock.patch.dict(
                "os.environ", {"MAKED_KNOWLEDGE_SOURCE_URL": "http://example/feed"}
            ):
                second = fetch_article()
        self.assertEqual(second["created"], 0)
        self.assertEqual(second["skipped"], 2)
        self.assertEqual(SiteSettingArticle.objects.count(), 2)

    def test_network_error_does_not_raise(self):
        import requests

        with mock.patch("Knowledge.tasks.requests.get") as get:
            get.side_effect = requests.ConnectionError("no route to host")
            with mock.patch.dict(
                "os.environ", {"MAKED_KNOWLEDGE_SOURCE_URL": "http://example/feed"}
            ):
                result = fetch_article()
        self.assertEqual(result["created"], 0)
        self.assertIn("no route", result["reason"])

    def test_http_error_does_not_raise(self):
        import requests

        with mock.patch("Knowledge.tasks.requests.get") as get:
            get.side_effect = requests.HTTPError("500 Server Error")
            with mock.patch.dict(
                "os.environ", {"MAKED_KNOWLEDGE_SOURCE_URL": "http://example/feed"}
            ):
                result = fetch_article()
        self.assertEqual(result["created"], 0)
        self.assertIn("500", result["reason"])

    def test_titles_truncated_to_field_max_length(self):
        long_title = "T" * 60
        payload = '{"items": [{"title": "%s", "content_html": "x"}]}' % long_title
        with mock.patch("Knowledge.tasks.requests.get") as get:
            get.return_value = mock.Mock(
                text=payload, raise_for_status=mock.Mock()
            )
            with mock.patch.dict(
                "os.environ", {"MAKED_KNOWLEDGE_SOURCE_URL": "http://example/feed"}
            ):
                fetch_article()
        article = SiteSettingArticle.objects.get()
        self.assertLessEqual(len(article.article_title), 26)
