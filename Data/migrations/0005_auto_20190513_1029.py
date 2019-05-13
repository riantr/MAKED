# Generated by Django 2.0.13 on 2019-05-13 02:29

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Data', '0004_auto_20190513_1029'),
    ]

    operations = [
        migrations.AddField(
            model_name='imageinfo',
            name='color_space',
            field=models.CharField(choices=[('sRGB', 'sRGB'), ('AdobeRGB', 'AdobeRGB'), ('AppleRGB', 'AppleRGB'), ('ColorMatchRGB', 'ColorMatchRGB'), ('CMYK', 'CMYK'), ('YIQ', 'YIQ'), ('YUV|YCrCb', 'YUV|YCrCb'), ('HSV', 'HSV'), ('HSI|HSL', 'HSI|HSL'), ('L*a*b', 'L*a*b'), ('CIERGB', 'CIERGB'), ('CIELUV', 'CIELUV'), ('CIELAB', 'CIELAB'), ('CIE1931XYZ', 'CIE1931XYZ'), ('CIE1964UVW', 'CIE1964UVW')], default='sRGB', max_length=10, verbose_name='color space'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='image_height',
            field=models.IntegerField(default=1, verbose_name='image height'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='image_size',
            field=models.CharField(default='', max_length=10, verbose_name='image size'),
        ),
        migrations.AddField(
            model_name='imageinfo',
            name='image_width',
            field=models.IntegerField(default=1, verbose_name='image width'),
        ),
    ]