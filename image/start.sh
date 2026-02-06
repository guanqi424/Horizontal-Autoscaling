#!/bin/sh
set -e

# start cpu burner API in background (port 8082)
./cpu-burner &
# start cpu work API in background (port 8081)
./cpu-work &

# run nginx in foreground (port 80)
exec nginx -g 'daemon off;'
