#!/bin/sh
/etc/init.d/redis-server start
/etc/init.d/elasticsearch start
/etc/init.d/collectd start
/etc/init.d/axess start
/etc/init.d/nginx start
/etc/init.d/axess_northbound start
/etc/init.d/ax.configcontroller start
/etc/init.d/ax.tr069controller start
/etc/init.d/ax.process_runner start
/etc/init.d/filebeat start
/etc/init.d/ax.graphite-web start
/etc/init.d/grafana-server start
/etc/init.d/clickhouse-server start