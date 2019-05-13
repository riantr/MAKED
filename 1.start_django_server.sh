#!/bin/bash
echo "Usage: 0.start_django_server.sh  <port>"
python3 manage.py runserver 172.16.18.16:$1
