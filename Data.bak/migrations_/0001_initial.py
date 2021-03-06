# Generated by Django 2.0.13 on 2019-05-07 03:08

from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


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
                ('dataset_images', models.IntegerField(default=0, verbose_name='dataset_images')),
                ('dataset_category', models.CharField(choices=[('UNCT', 'uncategoried'), ('FACE', 'face recognize'), ('VEHI', 'vehicle recognize')], default='UNCT', max_length=4, verbose_name='dataset category')),
                ('dataset_import_time', models.DateTimeField(default=django.utils.timezone.now, verbose_name='dataset import time')),
                ('data_categories', models.IntegerField(default=1, verbose_name='data categories')),
                ('data_labeled', models.BooleanField(default=True, verbose_name='data labeld')),
                ('train_file', models.CharField(max_length=100, verbose_name='train label file')),
                ('val_file', models.CharField(max_length=100, verbose_name='val label file')),
                ('test_file', models.CharField(max_length=100, verbose_name='test label file')),
            ],
            options={
                'verbose_name': 'datasets',
            },
        ),
        migrations.CreateModel(
            name='Image',
            fields=[
                ('image_id', models.UUIDField(primary_key=True, serialize=False)),
                ('image', models.ImageField(upload_to='', verbose_name='image')),
                ('image_name', models.CharField(max_length=50, verbose_name='image name')),
                ('image_path', models.CharField(max_length=150, verbose_name='image path')),
                ('image_hash', models.CharField(max_length=34, verbose_name='image hash')),
            ],
            options={
                'verbose_name': 'dataset image',
                'verbose_name_plural': 'dataset images',
            },
        ),
        migrations.CreateModel(
            name='ImageInfo',
            fields=[
                ('name', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, primary_key=True, serialize=False, to='Data.Image', verbose_name='image name')),
                ('lable', models.CharField(max_length=50, verbose_name='image label')),
                ('image_type', models.CharField(max_length=10, verbose_name='image type')),
                ('image_size', models.CharField(max_length=10, verbose_name='image size')),
                ('image_depth', models.IntegerField(verbose_name='image depth')),
                ('image_resolution', models.CharField(max_length=13, verbose_name='image resolution')),
                ('image_channels', models.IntegerField(verbose_name='image channels')),
                ('parents', models.CharField(default='', max_length=50, verbose_name='image parents')),
                ('parents_hash', models.CharField(max_length=34, verbose_name='parents hash')),
            ],
            options={
                'verbose_name': 'image info',
                'verbose_name_plural': 'image infos',
            },
        ),
        migrations.AddField(
            model_name='image',
            name='image_belongto',
            field=models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to='Data.Dataset'),
        ),
    ]
