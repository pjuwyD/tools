#!/bin/sh
/opt/tr069controller/.venv/bin/uwsgi --wsgi-file /opt/tr069controller/src/ax/tr069controller/tr069controller.py \
    --http :9675 \
    --http-keepalive \
    --uid axess \
    --gid axess \
    --gevent 1000 \
    --gevent-early-monkey-patch \
    --pyargv "-c /opt/tr069controller/project -s"