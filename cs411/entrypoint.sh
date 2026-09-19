#!/bin/bash
# CS 411 (Database Systems) — untested draft (support file for Dockerfile.suggested), generated from public course materials; never run. Discussion starter only — see CommentsForClass.md in this directory; the working example is cs341/fa26/Dockerfile.
# First-boot initialisation of DB data dirs on the persistent /data volume,
# then exec the CMD (supervisord). Idempotent.
set -euo pipefail

STUDENT=${STUDENT:-student}
DB_PASSWORD=${DB_PASSWORD:-password}   # course examples use root/password, neo4j/password (inferred)

mkdir -p /data/mysql /data/mongodb /data/neo4j /var/run/mysqld /var/log/mongodb /var/log/supervisor
chown -R mysql:mysql /data/mysql /var/run/mysqld
chown -R mongodb:mongodb /data/mongodb /var/log/mongodb
chown -R neo4j:neo4j /data/neo4j

# MySQL: initialise datadir and give root a password (Ubuntu default is auth_socket).
if [ ! -d /data/mysql/mysql ]; then
  mysqld --initialize-insecure --user=mysql --datadir=/data/mysql
  mysqld --user=mysql --skip-networking --socket=/tmp/init.sock &
  pid=$!
  for i in $(seq 60); do mysqladmin --socket=/tmp/init.sock ping >/dev/null 2>&1 && break; sleep 1; done
  mysql --socket=/tmp/init.sock -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${DB_PASSWORD}';
CREATE DATABASE IF NOT EXISTS academicworld;
SQL
  mysqladmin --socket=/tmp/init.sock -uroot -p"${DB_PASSWORD}" shutdown
  wait $pid || true
fi

# Neo4j: set initial password before first start.
if [ ! -f /data/neo4j/.initialised ]; then
  su -s /bin/bash neo4j -c "NEO4J_CONF=/etc/neo4j neo4j-admin dbms set-initial-password '${DB_PASSWORD}'" || true
  touch /data/neo4j/.initialised && chown neo4j:neo4j /data/neo4j/.initialised
fi

# SSH keys: platform injects the student's public key via $SSH_PUBKEY.
if [ -n "${SSH_PUBKEY:-}" ]; then
  install -d -m 700 -o "$STUDENT" -g "$STUDENT" /home/$STUDENT/.ssh
  echo "$SSH_PUBKEY" > /home/$STUDENT/.ssh/authorized_keys
  chown "$STUDENT:$STUDENT" /home/$STUDENT/.ssh/authorized_keys
  chmod 600 /home/$STUDENT/.ssh/authorized_keys
fi
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A

exec "$@"
