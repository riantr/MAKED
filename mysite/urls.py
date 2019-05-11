# -*- coding: utf-8 -*-
from __future__ import absolute_import, print_function, unicode_literals

import os
from cms.sitemaps import CMSSitemap
from django.conf import settings
from django.conf.urls import include, url
from django.conf.urls.static import static
from django.contrib import admin
from django.contrib.sites.models import Site
from django.contrib.auth.models import User
from django.contrib.sitemaps.views import sitemap
from django.contrib.staticfiles.urls import staticfiles_urlpatterns
from django.views.static import serve
from rest_framework import serializers, viewsets, routers
from django.contrib.flatpages import views
from django.contrib.flatpages.admin import FlatPageAdmin
from django.contrib.flatpages.models import FlatPage
from django.utils.translation import gettext_lazy as _
from django.views.generic.base import RedirectView

#Register Photo and SiteSettingArticle FlatpageAdmin to admin page

from mysite.models import Photo
admin.site.register(Photo) 

# Register models and use MarkdownEditor 
from django.urls import path
from django.db import models
from mdeditor.widgets import MDEditorWidget
from mysite.models import SiteSettingArticle

class MDEditor(admin.ModelAdmin):
    formfield_overrides = {
        models.TextField:{'widget': MDEditorWidget}
    }

admin.site.register(SiteSettingArticle, MDEditor)

# FlatPage start
# Define a new FlatPageAdmin
class FlatPageAdmin(FlatPageAdmin):
    fieldsets = (
        (None, {'fields': ('url', 'title', 'content', 'sites')}),
        (_('Advanced options'), {
            'classes': ('collapse',),
            'fields': (
                'enable_comments',
                'registration_required',
                'template_name',
            ),
        }),
    )

# Re-register FlatPageAdmin
admin.site.unregister(FlatPage)
admin.site.register(FlatPage, FlatPageAdmin)

admin.autodiscover()
admin.site.unregister(Site)
class SiteAdmin(admin.ModelAdmin):
    fields = ('id', 'name', 'domain')
    readonly_fields = ('id',)
    list_display = ('id', 'name', 'domain')
    list_display_links = ('name',)
    search_fields = ('name', 'domain')
admin.site.register(Site, SiteAdmin)

## REST framework settings
# Serializers define the API representation.
class UserSerializer(serializers.HyperlinkedModelSerializer):
    class Meta:
        model = User
        fields = ('url', 'username', 'email', 'is_staff')


# ViewSets define the view behavior.
class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
 
# Routers provide a way of automatically determining the URL conf.
router = routers.DefaultRouter()
router.register(r'users', UserViewSet)

# applications URL
urlpatterns = [
   # path('Model/',include('Model.urls')),
   # path('Attack/',include('Attack.urls')),
   # path('Knowledge/',include('Knowledge.urls')),
   # path('Experience/',include('Experience.urls')),
   # path('Data/',include('Data.urls')),
]

# Sitemap URL
urlpatterns += [
    url(r'^sitemap\.xml$', sitemap,
        {'sitemaps': {'cmspages': CMSSitemap}}),
]

# Admin URL
urlpatterns += [
    url(r'^admin/', admin.site.urls),  # NOQA
]

# RESTapi URL
urlpatterns += [
    url(r'^api/', include(router.urls)),
    url(r'^api-auth/', include('rest_framework.urls', namespace='rest_framework')),
]

# DjangoCMS URL
urlpatterns += [
    url(r'^', include('cms.urls')),
]

# MarkdownEditor URL
urlpatterns += [
    url(r'mdeditor/', include('mdeditor.urls')),
]

# Flatpage URL
urlpatterns += [
    #url(r'pages/', include('django.contrib.flatpages.urls')),
    #url('<path:url>', views.flatpage),
    url(r'^(?P<url>.*/)$', views.flatpage),
]

MEDIA_ROOT = os.path.join(settings.BASE_DIR,'media')
urlpatterns += static('/media/', document_root=MEDIA_ROOT)

# This is only needed when using runserver.
if settings.DEBUG:
    urlpatterns = [
        url(r'^media/(?P<path>.*)$', serve,
            {'document_root': settings.MEDIA_ROOT, 'show_indexes': True}),
        ] + staticfiles_urlpatterns() + urlpatterns
    urlpatterns += static(settings.MEDIA_URL,document_root=settings.MEDIA_ROOT)
    urlpatterns += [
        url(r'^favicon\.ico$', RedirectView.as_view(url=r'static/img/favicon.ico')),
    ]
