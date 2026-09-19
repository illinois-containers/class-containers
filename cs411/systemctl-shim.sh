#!/bin/sh
# CS 411 (Database Systems) — untested draft (support file for Dockerfile.suggested), generated from public course materials; never run. Discussion starter only — see CommentsForClass.md in this directory; the working example is cs341/fa26/Dockerfile.
# Minimal systemctl -> supervisorctl shim so course instructions such as
# `sudo systemctl restart neo4j` / `systemctl status mysql` keep working.
action="$1"; shift 2>/dev/null
svc=$(echo "${1:-}" | sed 's/\.service$//; s/^mongodb$/mongod/; s/^mysqld$/mysql/')
case "$action" in
  start|stop|restart|status) exec supervisorctl "$action" ${svc:+"$svc"} ;;
  enable|disable|daemon-reload) echo "systemctl shim: '$action' is a no-op in this container"; exit 0 ;;
  is-active) supervisorctl status "$svc" | grep -q RUNNING && { echo active; exit 0; } || { echo inactive; exit 3; } ;;
  *) echo "systemctl shim: unsupported '$action' (services: mysql mongod neo4j sshd)"; exit 1 ;;
esac
