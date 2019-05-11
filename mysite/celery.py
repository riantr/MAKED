from __future__ import absolute_import, unicode_literals
import os
from celery import Celery
from django.utils import timezone
from kombu import Exchange
from kombu import Queue
import datetime
import requests
from . import settings
#__ PS: 
# https://www.jianshu.com/p/745d469652b9
# https://blog.csdn.net/enlangs/article/details/87936600
# https://blog.csdn.net/weixin_42174361/article/details/83154130

DJANGO_SETTINGS_MODULE = os.environ.get('DJANGO_SETTINGS_MODULE')
#__ automatic detect project_name 
#project_name = os.path.split(os.path.abspath('.'))[-1]
#project_settings = '%s.settings' % project_name
#os.environ.setdefault('DJANGO_SETTINGS_MODULE', project_settings)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', DJANGO_SETTINGS_MODULE if DJANGO_SETTINGS_MODULE else 'mysite.settings')
app = Celery('mysite')

app.now = timezone.now

#__ config by a seperate file
#import mysite.celery_config
#app.config_from_object(mysite.celery_config)
app.config_from_object('django.conf:settings', namespace='CELERY')

#app.autodiscover_tasks()
#__ load all registrated app
app.autodiscover_tasks(lambda:settings.INSTALLED_APPS)

#from logging import Logger
#logger: Logger = get_task_logger(__name__)

#__ logger should define in tasks.py
#from celery.utils.log import get_task_logger
#logger = get_task_logger(__name__)

#__ settings 
#CELERYD_HIJACK_ROOT_LOGGER true
#CELERYD_LOG_COLOR 
#CELERYD_LOG_FORMAT
#CELERY_TASK_LOG_FORMAT
#CELERY_REDIRECT_STDOUTS
#CELERY_REDIRECT_STDOUTS_LEVEL

app.conf.task_queues = [
    Queue('tasks', Exchange('tasks'), routing_key='tasks',
        queue_arguments={'x-max-priority': 10}),
]
app.conf.task_queue_max_priority = 10
task_exchange = Exchange('tasks', type='direct')

task_queues = [Queue('hipri', task_exchange, routing_key='hipri'),
                Queue('midpri', task_exchange, routing_key='midpri'),
                Queue('lopri', task_exchange, routing_key='lopri')]

@app.task(bind=True)
def debug_task(self):
    print('Request: {0!r}'.format(self.request))
#def monitor_device_task(device_ip):
#    logger.info('monitor device task: %s' % device_ip)

