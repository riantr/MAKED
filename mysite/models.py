from django.contrib.sites.models import Site
from django.contrib.sites.managers import CurrentSiteManager
from django.db import models
from django.utils import timezone


class SiteSettingArticle(models.Model):
    """A free-form article, authored in Markdown.

    The field was originally ``mdeditor.fields.MDTextField``, which is a
    TextField with a Markdown editor widget. django-mdeditor is unmaintained
    and has no release compatible with Django 5, so the plain TextField is
    used and the Markdown is rendered in the view layer (see mysite/views.py).
    """

    article_title = models.CharField(verbose_name='title', max_length=26)
    article_content = models.TextField(verbose_name='content', default='')
    article_create_time = models.DateTimeField(verbose_name='create time', default=timezone.now)
    article_modify_time = models.DateTimeField(verbose_name='modify time', auto_now=True)

    class Meta:
        verbose_name = 'Site Setting Article'
        verbose_name_plural = 'Site Setting Articles'

    def __str__(self):
        return self.article_title


class Photo(models.Model):
    photo = models.FileField(upload_to='photo')
    photo_name = models.CharField(verbose_name='name', max_length=26, default='')
    photographer_name = models.CharField(max_length=100)
    pub_date = models.DateField()
    site = models.ForeignKey(Site, on_delete=models.CASCADE)
    objects = models.Manager()
    on_site = CurrentSiteManager()

    def __str__(self):
        return self.photo_name

