# Generated by Django 2.0.13 on 2019-05-10 08:16

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0021_auto_20190510_1543'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='image',
            name='image_belongto',
        ),
        migrations.DeleteModel(
            name='Image',
        ),
    ]
