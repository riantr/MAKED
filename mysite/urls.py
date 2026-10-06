"""URL configuration for the MAKED project.

Modernised from the original configuration, which used the removed
``django.conf.urls.url()`` alias and registered admin models at import time
before ``admin.autodiscover()`` had run.
"""
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.contrib.auth.models import User
from django.contrib.flatpages import views as flatpages_views
from django.contrib.flatpages.models import FlatPage
from django.contrib.sitemaps.views import sitemap
from django.contrib.sites.models import Site
from django.db import models
from django.urls import include, path, re_path
from django.utils.translation import gettext_lazy as _
from django.views.generic.base import RedirectView
from cms.sitemaps import CMSSitemap
from rest_framework import routers, serializers, viewsets

# ---------------------------------------------------------------------------
# Admin customisation
#
# These are registered on import, which Django's admin autodiscovery also
# imports. Registering in mysite/admin.py instead would be tidier, but the
# original project kept the customisations here and they are part of the
# project's shape.
# ---------------------------------------------------------------------------
from mysite import views
from mysite.models import Photo, SiteSettingArticle  # noqa: E402


class MarkdownAdmin(admin.ModelAdmin):
    """Render the markdown source field with the plain textarea widget.

    The original used ``mdeditor.widgets.MDEditorWidget`` from the abandoned
    django-mdeditor package, which has no release compatible with Django 5.
    """

    formfield_overrides = {models.TextField: {"widget": None}}


class FlatPageAdminCustom(admin.ModelAdmin):
    fieldsets = (
        (None, {"fields": ("url", "title", "content", "sites")}),
        (
            _("Advanced options"),
            {
                "classes": ("collapse",),
                "fields": (
                    "enable_comments",
                    "registration_required",
                    "template_name",
                ),
            },
        ),
    )


class SiteAdminCustom(admin.ModelAdmin):
    fields = ("id", "name", "domain")
    readonly_fields = ("id",)
    list_display = ("id", "name", "domain")
    list_display_links = ("name",)
    search_fields = ("name", "domain")


admin.site.register(Photo)
admin.site.register(SiteSettingArticle, MarkdownAdmin)
admin.site.unregister(FlatPage)
admin.site.register(FlatPage, FlatPageAdminCustom)
admin.site.unregister(Site)
admin.site.register(Site, SiteAdminCustom)

# ---------------------------------------------------------------------------
# REST API
# ---------------------------------------------------------------------------
class UserSerializer(serializers.HyperlinkedModelSerializer):
    class Meta:
        model = User
        fields = ("url", "username", "email", "is_staff")


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer


router = routers.DefaultRouter()
router.register(r"users", UserViewSet)

# ---------------------------------------------------------------------------
# URL patterns
# ---------------------------------------------------------------------------
urlpatterns = [
    # Sitemap
    re_path(r"^sitemap\.xml$", sitemap, {"sitemaps": {"cmspages": CMSSitemap}}),
    # Admin
    path("admin/", admin.site.urls),
    # REST API
    path("api/", include(router.urls)),
    path("api-auth/", include("rest_framework.urls", namespace="rest_framework")),
    # Markdown articles. The original project defined this view but never
    # routed it -- the only path() calls in its urlpatterns list were
    # commented out, so detail() was unreachable.
    path("articles/<int:article_id>/", views.detail, name="article-detail"),
    # django CMS must be included near the end so its catch-all does not
    # shadow the more specific patterns above.
    path("", include("cms.urls")),
    # Flat pages: the original used a catch-all that requires a trailing slash.
    re_path(r"^(?P<url>.*/)$", flatpages_views.flatpage),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
    urlpatterns += [
        re_path(
            r"^favicon\.ico$",
            RedirectView.as_view(url=settings.STATIC_URL + "img/favicon.ico"),
        ),
    ]
