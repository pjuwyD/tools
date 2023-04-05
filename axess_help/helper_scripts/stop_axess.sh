#!/bin/sh
/etc/init.d/redis-server stop
/etc/init.d/elasticsearch stop
/etc/init.d/collectd stop
/etc/init.d/axess stop
/etc/init.d/nginx stop
/etc/init.d/axess_northbound stop
/etc/init.d/ax.configcontroller stop
/etc/init.d/ax.tr069controller stop
/etc/init.d/ax.process_runner stop
/etc/init.d/filebeat stop
/etc/init.d/ax.graphite-web stop
/etc/init.d/grafana-server stop
/etc/init.d/clickhouse-server stop