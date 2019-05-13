from django.db import models
from django.utils.deconstruct import deconstructible

#from django.core.files.storage import FileSystemStorage

class Dataset(models.Model):
    DATASET_UNCATEGORIED = 'UNCT'
    DATASET_FACE_RECOGNIZE = 'FACE'
    DATASET_VEHICLE_RECOGNIZE = 'VEHI'
    DATASET_OBJECT_RECOGNIZE = 'OBJ'
    DATASET_CATEGORIES = (
        (DATASET_UNCATEGORIED, 'uncategoried'),
        (DATASET_FACE_RECOGNIZE, 'face recognize'),
        (DATASET_VEHICLE_RECOGNIZE, 'vehicle recognize'),
        (DATASET_OBJECT_RECOGNIZE, 'object recognize'),
    )
    # dataset_id = models.AutoField(primary_key=True)
    dataset_name = models.CharField(verbose_name='dataset name', primary_key=True, max_length=50, default='')
    dataset_source = models.URLField(verbose_name='dataset source')
    #dataset_host = model.CharField(verbose_name='dataset host', max_length=20, default='localhost:')
    dataset_host = models.GenericIPAddressField(verbose_name='dataset host', protocol='ipv4', default='172.16.18.16')
    dataset_address = models.CharField(verbose_name='dataset address', max_length=100)
    #dataset_address = models.FilePathField(verbose_name='dataset address')
    trainging_images = models.IntegerField(verbose_name='training images', default=0)
    test_images = models.IntegerField(verbose_name='test images', default=0)
    dataset_images = models.IntegerField(verbose_name='dataset images', default=0)
    dataset_category = models.CharField(verbose_name='dataset category', max_length=4, choices=DATASET_CATEGORIES, default=DATASET_UNCATEGORIED)
    dataset_import_time = models.DateTimeField(verbose_name='dataset import time',  auto_now_add=True)
    data_classes = models.IntegerField(verbose_name='data classes', default=0)
    data_labeled = models.BooleanField(verbose_name='data labeld', default=True)
    train_file = models.CharField(verbose_name='train label file', max_length=100, default='train.txt')
    test_file = models.CharField(verbose_name='test label file', max_length=100, default='test.txt')
    val_file = models.CharField(verbose_name='val label file', max_length=100, default='val.txt')
   
    class Meta:
        verbose_name = 'dataset'
        verbose_name_plural = 'datasets'

    def __str__(self):
        return self.dataset_name

class Image(models.Model):
    image_id = models.UUIDField(primary_key=True)
    image = models.ImageField(verbose_name='image')
    image_name = models.CharField(verbose_name='image name', max_length=50)
    image_path = models.CharField(verbose_name='image path', max_length=150)
    image_hash = models.CharField(verbose_name='image hash', max_length=34)
    image_belongto = models.ForeignKey(Dataset, on_delete=models.CASCADE)

    class Meta:
        verbose_name = 'dataset image'
        verbose_name_plural = 'dataset images'

    def __str__(self):
        return self.image_name

#@deconstructible
class ImageInfo(models.Model):
    COLORSPACE_sRGB = 'sRGB'
    COLORSPACE_AdobeRGB = 'AdobeRGB'
    COLORSPACE_AppleRGB = 'AppleRGB'
    COLORSPACE_ColorMatchRGB = 'ColorMatchRGB'
    COLORSPACE_CMYK = 'CMYK'
    COLORSPACE_YIQ = 'YIQ'
    COLORSPACE_YUV = 'YUV|YCrCb'
    COLORSPACE_HSV = 'HSV'
    COLORSPACE_HSI = 'HSI|HSL'
    COLORSPACE_Lab = 'L*a*b'
    COLORSPACE_CIERGB = 'CIERGB'
    COLORSPACE_CIELUV = 'CIELUV'
    COLORSPACE_CIELAB = 'CIELAB'
    COLORSPACE_CIEXYZ = 'CIE1931XYZ'
    COLORSPACE_CIEUVW = 'CIE1964UVW'

    COLORSPACE_CATEGORIES = (
        (COLORSPACE_sRGB, 'sRGB'),
        (COLORSPACE_AdobeRGB, 'AdobeRGB'),
        (COLORSPACE_AppleRGB, 'AppleRGB'),
        (COLORSPACE_ColorMatchRGB, 'ColorMatchRGB'),
        (COLORSPACE_CMYK, 'CMYK'),
        (COLORSPACE_YIQ, 'YIQ'),
        (COLORSPACE_YUV, 'YUV|YCrCb'),
        (COLORSPACE_HSV, 'HSV'),
        (COLORSPACE_HSI, 'HSI|HSL'),
        (COLORSPACE_Lab, 'L*a*b'),
        (COLORSPACE_CIERGB, 'CIERGB'),
        (COLORSPACE_CIELUV, 'CIELUV'),
        (COLORSPACE_CIELAB, 'CIELAB'),
        (COLORSPACE_CIEXYZ, 'CIE1931XYZ'),
        (COLORSPACE_CIEUVW, 'CIE1964UVW'),
    )
    TYPE_JPEG = 'JPG|JPEG'
    TYPE_BMP = 'BMP'
    TYPE_PNG = 'PNG'
    TYPE_CATEGORIES = (
        (TYPE_JPEG, 'JPG|JPEG'),
        (TYPE_BMP, 'BMP'),
        (TYPE_PNG, 'PNG'),
    )

    #name = models.ForeignKey(Image.image_name,verbose_name='image name', primary_key=True, on_delete=models.CASCADE)
    name = models.OneToOneField(Image, verbose_name='image name', primary_key=True, on_delete=models.CASCADE)
    lable = models.IntegerField(verbose_name='image label',default=0)
    annotation_file = models.CharField(verbose_name='annotation file', max_length=50, default=name)
    image_type = models.CharField(verbose_name='image type', max_length=10, choices=TYPE_CATEGORIES, default=TYPE_JPEG)
    image_size = models.CharField(verbose_name='image size', max_length=10)
    image_width = models.IntegerField(verbose_name='image width', default=1)
    image_height = models.IntegerField(verbose_name='image height', default=1)
    color_space = models.CharField(verbose_name='color space', max_length=10, choices=COLORSPACE_CATEGORIES, default=COLORSPACE_sRGB)
    image_resolution = models.CharField(verbose_name='image resolution', max_length=13)
    image_channels = models.IntegerField(verbose_name='image channels',default=3)
    selfhash = models.CharField(verbose_name='self hash', max_length=34, default=Image.image_hash)
    parents = models.CharField(verbose_name='image parents', max_length=50, blank=True)
    parents_hash = models.CharField(verbose_name='parents hash', max_length=34, blank=True)
    bndbox_xmin = models.IntegerField(verbose_name='bndbox xMin',default=1, blank=True)
    bndbox_xmax = models.IntegerField(verbose_name='bndbox xMax',default=image_width, blank=True)
    bndbox_ymin = models.IntegerField(verbose_name='bndbox yMin',default=1, blank=True)
    bndbox_ymax = models.IntegerField(verbose_name='bndbox yMax',default=image_height, blank=True)
    
    class Meta:
        verbose_name = 'image info'
        verbose_name_plural = 'image infos'

    def __str__(self):
        return self.selfhash

#    def __init__(self, name='')
#        self.name = name
#
#    def __eq__(self, other):
#        return self.name == other.name

#class ImageStorage(FileSystemStorage):
#    from django.conf import settings
#
#    def __init__(self, location=settings.MEDIA_ROOT, base_url=settings.MEDIA_URL):
#        super(ImageStorage, self).__init__(location, base_url)
#
#    def _save(self, name, content):
#        import os, time, random
#        ext = os.path.splitext(name)[1]
#        d = os.path.dirname(name)
#        fn = time.strftime('%Y%m%d%H%M%S')
#        fn = fn + '_%d' % random.randinit(0,100)
#        name = os.path.join(d, fn + ext)
#        return super(ImageStorage, self)._save(name, content)

