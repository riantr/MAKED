# Generated by Django 2.0.13 on 2019-05-10 06:58

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0011_auto_20190510_1455'),
    ]

    operations = [
        migrations.AddField(
            model_name='imageinfo',
            name='bndbox_xmax',
            field=models.IntegerField(default=1, verbose_name='bndbox xMax'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='bndbox_xmin',
            field=models.IntegerField(default=1, verbose_name='bndbox xMin'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='bndbox_ymax',
            field=models.IntegerField(default=1, verbose_name='bndbox yMax'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='bndbox_ymin',
            field=models.IntegerField(default=1, verbose_name='bndbox yMin'),
        ),
        migrations.AlterField(
            model_name='imageinfo',
            name='image_height',
            field=models.CharField(default='', max_length=4, verbose_name='image height'),
        ),
        migrations.AlterField(
            model_name='imageinfo',
            name='image_width',
            field=models.CharField(default='', max_length=4, verbose_name='image width'),
        ),
    ]
