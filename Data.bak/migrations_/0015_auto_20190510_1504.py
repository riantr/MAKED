# Generated by Django 2.0.13 on 2019-05-10 07:04

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0014_auto_20190510_1502'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='image',
            name='image_belongto',
        ),
        migrations.DeleteModel(
            name='Dataset',
        ),
        migrations.DeleteModel(
            name='Image',
        ),
    ]
