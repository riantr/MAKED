from django.contrib.sites.models import Site
from django.contrib.sites.managers import CurrentSiteManager
from django.utils import timezone
from django.db import models
from mdeditor.fields import MDTextField

#class Category(models.Model):
#    category_name = models.CharField(verbose_name='category', max_length=26, default='')
#    category_number = models.IntegerField(verbose_name='category number',default=1)
#    
#    class Meta:
#        verbose_name = 'category'
#        verbose_name_plural = 'categories'
#
#    def __str__(self):
#        return self.name
#
#class Tag(models.Model):
#    tag_name = models.CharField(verbose_name='tag', max_length=26)
#    tag_number = models.IntegerField(verbose_name='tag number',default=1)
#    
#    class Meta:
#        verbose_name = 'tag'
#        verbose_name_plural = 'tags'
#
#    def __str__(self):
#        return self.name
#
class SiteSettingArticle(models.Model):
    article_title = models.CharField(verbose_name='title',max_length=26)
    article_content = MDTextField(verbose_name='content', default='')
    article_create_time = models.DateTimeField(verbose_name='create time', default=timezone.now)
    article_modify_time = models.DateTimeField(verbose_name='modify time', auto_now=True)
#    article_category = models.ForeignKey(Category, verbose_name='category', default='', on_delete=models.CASCADE)
#    article_tag = models.ManyToManyField(Tag, verbose_name='tag')

    class Meta:
        verbose_name = 'Site Setting Article'
        verbose_name_plural = 'Site Setting Articles'
    def __str__(self):
        return self.article_title

class Photo(models.Model):
    photo = models.FileField(upload_to='photo')
    photo_name = models.CharField(verbose_name='name',max_length=26, default='')
    photographer_name = models.CharField(max_length=100)
    pub_date = models.DateField()
    site = models.ForeignKey(Site, on_delete=models.CASCADE)
    objects = models.Manager()
    on_site = CurrentSiteManager()

    def __str__(self):
        return self.photo_name

