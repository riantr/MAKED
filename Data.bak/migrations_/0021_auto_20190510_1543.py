# Generated by Django 2.0.13 on 2019-05-10 07:43

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0020_auto_20190510_1529'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='imageinfo',
            name='name',
        ),
        migrations.DeleteModel(
            name='ImageInfo',
        ),
    ]
