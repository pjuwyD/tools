#!/bin/sh
/etc/init.d/redis-server status
/etc/init.d/elasticsearch status
/etc/init.d/collectd status
/etc/init.d/axess status
/etc/init.d/openresty status
/etc/init.d/axess_northbound status
/etc/init.d/ax.configcontroller status
/etc/init.d/ax.tr069controller status
/etc/init.d/ax.process_runner status
/etc/init.d/filebeat status
/etc/init.d/ax.graphite-web status
/etc/init.d/grafana-server status
/etc/init.d/clickhouse-server status