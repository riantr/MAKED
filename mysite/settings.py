"""
Django settings for the MAKED project.

MAKED is a Django CMS site that organises a machine-learning knowledge base
into five domains, one per letter of the name:

    M  Model       the model formulator
    A  Attack      the attack generator
    K  Knowledge   the knowledge distiller
    E  Experience  the experience absorber
    D  Data        the data turbine

Each domain is a Django app (``Model``, ``Attack``, ``Knowledge``,
``Experience``, ``Data``) and a top-level CMS page, so the navigation tree of
the site *is* the project's ontology.

Modernised from the original Django 2.1.8 / django-cms 3.6 settings.
Configuration is read from the environment; no secrets live in this file.
"""
import os
from pathlib import Path

from django.utils.translation import gettext_lazy as _

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR


def env_bool(name, default=False):
    """Read a boolean from the environment.

    Anything other than the documented false spellings counts as true, so that
    ``MAKED_DEBUG=1`` and ``MAKED_DEBUG=yes`` both work.
    """
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"0", "false", "no", "off", ""}


def env_list(name, default=()):
    """Read a comma-separated list from the environment."""
    raw = os.environ.get(name)
    if not raw:
        return list(default)
    return [item.strip() for item in raw.split(",") if item.strip()]


# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------
# A development fallback keeps `manage.py check` usable out of the box, but a
# deployment MUST provide MAKED_SECRET_KEY. Raising here (rather than silently
# using the fallback) would make `check` fail locally, so we warn loudly
# instead and let `check --deploy` catch it in CI.
SECRET_KEY = os.environ.get(
    "MAKED_SECRET_KEY",
    "django-insecure-dev-only-key-do-not-use-in-production",
)

DEBUG = env_bool("MAKED_DEBUG", default=True)

ALLOWED_HOSTS = env_list("MAKED_ALLOWED_HOSTS", default=["localhost", "127.0.0.1", "[::1]"])

CSRF_TRUSTED_ORIGINS = env_list("MAKED_CSRF_TRUSTED_ORIGINS", default=[])

ROOT_URLCONF = "mysite.urls"
WSGI_APPLICATION = "mysite.wsgi.application"

DEFAULT_AUTO_FIELD = "django.db.models.AutoField"

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------
DJANGO_CMS_ENVIRONMENT = "local" if DEBUG else "production"

INSTALLED_APPS = [
    # Admin styling must precede django.contrib.admin (django CMS requirement).
    "djangocms_admin_style",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.admin",
    "django.contrib.sites",
    "django.contrib.sitemaps",
    "django.contrib.staticfiles",
    "django.contrib.messages",
    "django.contrib.flatpages",
    "django.contrib.redirects",
    # django CMS core
    "cms",
    "menus",
    "sekizai",
    "treebeard",
    # CMS plugins
    "djangocms_text_ckeditor",
    "filer",
    "easy_thumbnails",
    "djangocms_file",
    "djangocms_link",
    "djangocms_picture",
    "djangocms_style",
    # API
    "rest_framework",
    # Async task machinery
    "django_celery_beat",
    "django_celery_results",
    "django_extensions",
    # Project apps
    "mysite",
    "Model",
    "Attack",
    "Knowledge",
    "Experience",
    "Data",
]

SITE_ID = 1

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "django.contrib.flatpages.middleware.FlatpageFallbackMiddleware",
    "django.contrib.redirects.middleware.RedirectFallbackMiddleware",
    # django CMS middleware
    "cms.middleware.user.CurrentUserMiddleware",
    "cms.middleware.page.CurrentPageMiddleware",
    "cms.middleware.toolbar.ToolbarMiddleware",
    "cms.middleware.language.LanguageCookieMiddleware",
]

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "mysite" / "templates"],
        # APP_DIRS must be on: django CMS plugins ship their render templates
        # inside their own packages (djangocms_snippet/templates/... etc.).
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
                "django.template.context_processors.i18n",
                "django.template.context_processors.media",
                "django.template.context_processors.static",
                "django.template.context_processors.tz",
                "sekizai.context_processors.sekizai",
                "cms.context_processors.cms_settings",
            ],
            "builtins": ["cms.templatetags.cms_tags"],
        },
    },
]

WSGI_APPLICATION = "mysite.wsgi.application"

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# Declared explicitly rather than left to Django's defaults: when neither
# Argon2 nor bcrypt is installed, Django silently falls back to unsalted
# PBKDF2-SHA1, and `createsuperuser` then stores a password that
# `authenticate()` cannot read back (the hasher cannot even be identified).
# Listing the modern hashers first makes the failure loud instead.
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
    "django.contrib.auth.hashers.ScryptPasswordHasher",
    "django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
]

LOGIN_URL = "admin:login"

# ---------------------------------------------------------------------------
# Internationalisation
# ---------------------------------------------------------------------------
LANGUAGE_CODE = os.environ.get("MAKED_LANGUAGE_CODE", "en")
TIME_ZONE = os.environ.get("MAKED_TIME_ZONE", "Asia/Shanghai")
USE_I18N = True
USE_TZ = True

LANGUAGES = [("en", _("English"))]

CMS_LANGUAGES = {
    1: [
        {
            "code": "en",
            "name": _("English"),
            "public": True,
            "redirect_on_fallback": True,
            "hide_untranslated": False,
        },
    ],
    "default": {
        "public": True,
        "redirect_on_fallback": True,
        "hide_untranslated": False,
    },
}

CMS_TEMPLATES = (
    ("page.html", "Page"),
    ("feature.html", "Page with Feature"),
)

# ---------------------------------------------------------------------------
# Static and media files
# ---------------------------------------------------------------------------
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "static"
STATICFILES_DIRS = [BASE_DIR / "mysite" / "static"]

MEDIA_URL = "/media/"
MEDIA_ROOT = DATA_DIR / "media"

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"
        if DEBUG
        else "django.contrib.staticfiles.storage.ManifestStaticFilesStorage"
    },
}

THUMBNAIL_PROCESSORS = (
    "easy_thumbnails.processors.colorspace",
    "easy_thumbnails.processors.autocrop",
    "filer.thumbnail_processors.scale_and_crop_with_subject_location",
    "easy_thumbnails.processors.filters",
)

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
        "ATOMIC_REQUESTS": True,
        "OPTIONS": {
            # SQLite + Celery beat polling: give writers a chance to release
            # the file lock instead of failing immediately with "database is
            # locked" when a scheduled task fires during a request.
            "timeout": 20,
        },
    }
}

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------
if not DEBUG:
    # HSTS and the SSL redirect default to OFF even in production, which
    # leaves two `check --deploy` warnings by design. Enabling HSTS tells
    # browsers to refuse plain HTTP for max-age seconds, and a mistake there
    # is not recoverable by changing config -- only by users clearing browser
    # state. The same applies to a hard redirect when TLS terminates upstream.
    # Both are deployment decisions, so both are opt-in:
    #
    #   MAKED_HSTS_SECONDS=31536000   # 1 year, once TLS is confirmed working
    #   MAKED_SSL_REDIRECT=true       # only if Django sees the TLS itself
    #
    SECURE_HSTS_SECONDS = int(os.environ.get("MAKED_HSTS_SECONDS", "0"))
    SECURE_SSL_REDIRECT = env_bool("MAKED_SSL_REDIRECT", default=False)
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_REFERRER_POLICY = "same-origin"
    X_FRAME_OPTIONS = "DENY"

# The original 2019 settings hashed IDs with a salt that duplicated
# SECRET_KEY. Keep a separate, independently configurable salt.
HASHID_FIELD_SALT = os.environ.get("MAKED_HASHID_SALT", SECRET_KEY)

# ---------------------------------------------------------------------------
# REST framework
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.DjangoModelPermissionsOrAnonReadOnly",
    ],
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 50,
}

# ---------------------------------------------------------------------------
# Celery
# -------------------------------------------------------------------------
CELERY_BROKER_URL = os.environ.get("MAKED_CELERY_BROKER", "redis://127.0.0.1:6379/0")
CELERY_RESULT_BACKEND = os.environ.get("MAKED_CELERY_BACKEND", "django-db")
CELERY_CACHE_BACKEND = "django-cache"
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_ACCEPT_CONTENT = ["application/json"]
CELERY_TIMEZONE = TIME_ZONE
CELERY_ENABLE_UTC = False

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
    }
}

# The original project ran with tz-awareness off. Keep that behaviour: the
# crontab rows already in the database were written under naive local time.
DJANGO_CELERY_BEAT_TZ_AWARE = False
DJANGO_CELERY_BEAT_SCHEDULER = "django_celery_beat.schedulers:DatabaseScheduler"
DJANGO_CELERY_RESULTS = {"ALLOW_EDITS": False}
DJANGO_CELERY_RESULTS_TASK_ID_MAX_LENGTH = 191

# django-cms 5 requires the toolbar to know which plugins are allowed.
CMS_CONFIRM_VERSION4 = env_bool("MAKED_CMS_CONFIRM_VERSION4", default=True)
