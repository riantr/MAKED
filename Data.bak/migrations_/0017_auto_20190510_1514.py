# Generated by Django 2.0.13 on 2019-05-10 07:14

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0016_auto_20190510_1509'),
    ]

    operations = [
        migrations.AlterField(
            model_name='imageinfo',
            name='lable',
            field=models.IntegerField(default=0, verbose_name='image label'),
        ),
    ]
