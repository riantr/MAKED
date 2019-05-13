# Generated by Django 2.0.13 on 2019-05-13 02:29

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0003_imageinfo'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='imageinfo',
            name='color_space',
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='annotation_file',
            field=models.CharField(default='', max_length=50, verbose_name='annotation file'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='lable',
            field=models.IntegerField(default=0, verbose_name='image label'),
        ),
    ]