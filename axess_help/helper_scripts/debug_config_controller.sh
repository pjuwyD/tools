#!/bin/sh
/opt/configcontroller/bin/uwsgi --wsgi-file /opt/configcontroller/src/ax/configcontroller/configcontroller.py \
    --http :9677 \
    --http-keepalive \
    --uid axess \
    --gid axess \
    --gevent 1000 \
    --gevent-early-monkey-patch \
    --pyargv "-c /opt/configcontroller/project -s"