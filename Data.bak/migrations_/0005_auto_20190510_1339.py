# Generated by Django 2.0.13 on 2019-05-10 05:39

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0004_auto_20190510_1130'),
    ]

    operations = [
        migrations.AddField(
            model_name='dataset',
            name='test_images',
            field=models.IntegerField(default=0, verbose_name='test images'),
        ),
        migrations.AddField(
            model_name='dataset',
            name='trainging_images',
            field=models.IntegerField(default=0, verbose_name='training images'),
        ),
        migrations.AlterField(
            model_name='dataset',
            name='dataset_images',
            field=models.IntegerField(default=0, verbose_name='dataset images'),
        ),
    ]
