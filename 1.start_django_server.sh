#!/bin/bash
echo "Usage: 0.start_django_server.sh  <port>"
python3 manage.py runserver 127.0.0.1:$1
