# Generated by Django 2.0.13 on 2019-05-13 02:03

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='Image',
            fields=[
                ('id', models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('image', models.ImageField(upload_to='', verbose_name='image')),
                ('image_name', models.CharField(max_length=50, verbose_name='image name')),
                ('image_path', models.CharField(max_length=150, verbose_name='image path')),
                ('image_hash', models.CharField(max_length=34, verbose_name='image hash')),
                ('image_belongto', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to='Data.Dataset')),
            ],
            options={
                'verbose_name': 'dataset image',
                'verbose_name_plural': 'dataset images',
            },
        ),
    ]
