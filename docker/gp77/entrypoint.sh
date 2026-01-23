#!/bin/bash
set -e

# 1. Start SSH (Required)
sudo /usr/sbin/sshd

# 2. Hostname Workaround
if [ -f /home/gpadmin/.build_hostname ]; then
    BUILD_HOSTNAME=$(cat /home/gpadmin/.build_hostname)
    echo "127.0.0.1 $BUILD_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

# 3. Start Greenplum
source /usr/local/greenplum-db/greenplum_path.sh
echo "--- Starting Greenplum (Initialized on $BUILD_HOSTNAME) ---"
gpstart -a || { cat $COORDINATOR_DATA_DIRECTORY/log/* ; exit 1;}

# 4. Create Custom Database and User (Configurable via ENV)
# --------------------------------------------------------
# Set defaults if env vars are not provided
: ${POSTGRES_DB:=postgres}
: ${POSTGRES_USER:=postgres}
: ${POSTGRES_PASSWORD:=postgres}

echo "--- Configuring Custom DB: $POSTGRES_DB and User: $POSTGRES_USER ---"

# Create Database (ignore error if exists)
createdb "$POSTGRES_DB" || true

# Create User and Grant Privileges
# We use a DO block to handle "CREATE USER IF NOT EXISTS" gracefully
psql -d "$POSTGRES_DB" -c "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$POSTGRES_USER') THEN
        CREATE USER \"$POSTGRES_USER\" SUPERUSER LOGIN PASSWORD '$POSTGRES_PASSWORD';
    ELSE
        ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '$POSTGRES_PASSWORD';
    END IF;
END
\$\$;"

psql -d "$POSTGRES_DB" -c "GRANT ALL PRIVILEGES ON DATABASE \"$POSTGRES_DB\" TO \"$POSTGRES_USER\""

# 5. Tail logs
tail -f $COORDINATOR_DATA_DIRECTORY/log/gpdb-*.csv