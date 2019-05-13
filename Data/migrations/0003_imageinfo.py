# Generated by Django 2.0.13 on 2019-05-13 02:25

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0002_image'),
    ]

    operations = [
        migrations.CreateModel(
            name='ImageInfo',
            fields=[
                ('info_id', models.AutoField(primary_key=True, serialize=False)),
                ('image_type', models.CharField(choices=[('JPG|JPEG', 'JPG|JPEG'), ('BMP', 'BMP'), ('PNG', 'PNG')], default='JPG|JPEG', max_length=10, verbose_name='image type')),
                ('color_space', models.CharField(choices=[('sRGB', 'sRGB'), ('AdobeRGB', 'AdobeRGB'), ('AppleRGB', 'AppleRGB'), ('ColorMatchRGB', 'ColorMatchRGB'), ('CMYK', 'CMYK'), ('YIQ', 'YIQ'), ('YUV|YCrCb', 'YUV|YCrCb'), ('HSV', 'HSV'), ('HSI|HSL', 'HSI|HSL'), ('L*a*b', 'L*a*b'), ('CIERGB', 'CIERGB'), ('CIELUV', 'CIELUV'), ('CIELAB', 'CIELAB'), ('CIE1931XYZ', 'CIE1931XYZ'), ('CIE1964UVW', 'CIE1964UVW')], default='sRGB', max_length=10, verbose_name='color space')),
            ],
            options={
                'verbose_name': 'image info',
                'verbose_name_plural': 'image infos',
            },
        ),
    ]
