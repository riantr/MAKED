# Generated by Django 2.0.13 on 2019-05-13 02:48

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0008_auto_20190513_1040'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='image',
            name='image_hash',
        ),
    ]
