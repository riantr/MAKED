# Generated by Django 2.0.13 on 2019-05-13 02:29

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0005_auto_20190513_1029'),
    ]

    operations = [
        migrations.AddField(
            model_name='imageinfo',
            name='image_channels',
            field=models.IntegerField(default=3, verbose_name='image channels'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='image_resolution',
            field=models.CharField(default='', max_length=13, verbose_name='image resolution'),
        ),
    ]
