# Generated by Django 2.0.13 on 2019-05-13 02:49

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0009_remove_image_image_hash'),
    ]

    operations = [
        migrations.RenameField(
            model_name='imageinfo',
            old_name='parents',
            new_name='parent',
        ),
        migrations.RenameField(
            model_name='imageinfo',
            old_name='parents_hash',
            new_name='parent_hash',
        ),
        migrations.RenameField(
            model_name='imageinfo',
            old_name='selfhash',
            new_name='self_hash',
        ),
    ]