# Generated by Django 2.0.13 on 2019-05-13 02:01

from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='Dataset',
            fields=[
                ('dataset_name', models.CharField(default='', max_length=50, primary_key=True, serialize=False, verbose_name='dataset name')),
                ('dataset_source', models.URLField(verbose_name='dataset source')),
                ('dataset_host', models.GenericIPAddressField(default='172.16.18.16', protocol='ipv4', verbose_name='dataset host')),
                ('dataset_address', models.FilePathField(verbose_name='dataset address')),
                ('trainging_images', models.IntegerField(default=0, verbose_name='training images')),
                ('test_images', models.IntegerField(default=0, verbose_name='test images')),
                ('dataset_images', models.IntegerField(default=0, verbose_name='dataset images')),
                ('dataset_category', models.CharField(choices=[('UNCT', 'uncategoried'), ('FACE', 'face recognize'), ('VEHI', 'vehicle recognize'), ('OBJ', 'object recognize')], default='UNCT', max_length=4, verbose_name='dataset category')),
                ('dataset_import_time', models.DateTimeField(auto_now_add=True, verbose_name='dataset import time')),
                ('data_classes', models.IntegerField(default=0, verbose_name='data classes')),
                ('data_labeled', models.BooleanField(default=True, verbose_name='data labeld')),
                ('train_file', models.CharField(default='train.txt', max_length=100, verbose_name='train label file')),
                ('test_file', models.CharField(default='test.txt', max_length=100, verbose_name='test label file')),
                ('val_file', models.CharField(default='val.txt', max_length=100, verbose_name='val label file')),
            ],
            options={
                'verbose_name': 'dataset',
                'verbose_name_plural': 'datasets',
            },
        ),
    ]
