"""Celery application for MAKED.

Modernised from the original, which set ``app.now = timezone.now`` (Celery has
no such attribute; the setting was dead code) and configured queues on both
``app.conf`` and a module-level ``task_queues`` name, so only one of the two
priority schemes was ever in effect.
"""
import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

app = Celery("mysite")

# All Celery settings are namespaced under CELERY_ in mysite/settings.py.
app.config_from_object("django.conf:settings", namespace="CELERY")

# Load tasks.py from every installed app.
app.autodiscover_tasks()


@app.task(bind=True)
def debug_task(self):
    """Print the task request; useful for verifying worker connectivity."""
    print(f"Request: {self.request!r}")
    return repr(self.request)
