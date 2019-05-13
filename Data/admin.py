from django.contrib import admin
from Data.models import Dataset, Image, ImageInfo
#from Data.models import Dataset, Image

admin.site.register(Dataset)
admin.site.register(Image)
admin.site.register(ImageInfo)

