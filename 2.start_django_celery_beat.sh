# nohup celery -A mysite beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler &
#celery -A mysite beat -l info -f /home/renyongxiang/work/MAKED/tmp/tutorial-project/log --scheduler django_celery_beat.schedulers:DatabaseScheduler
celery -A mysite beat -l info -f log/cerlery_beat.log
