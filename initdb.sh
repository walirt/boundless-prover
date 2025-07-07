#!/bin/bash

DB_USER="worker"
DB_PASSWORD="password"
DB_NAME="taskdb"

echo "Creating PostgreSQL user '$DB_USER' and database '$DB_NAME'..."

echo "Attempting to create user '$DB_USER'..."
su - postgres -c "psql -v ON_ERROR_STOP=1 -d postgres <<'EOF'
DO
\$do\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
      CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';
      RAISE NOTICE 'User $DB_USER created.';
   ELSE
      RAISE NOTICE 'User $DB_USER already exists, skipping creation.';
   END IF;
END
\$do\$;
EOF"

if [ $? -ne 0 ]; then
    echo "Error creating PostgreSQL user '$DB_USER'. Aborting."
    exit 1
fi

echo "Attempting to create database '$DB_NAME' and assign ownership to '$DB_USER'..."
su - postgres -c "psql -v ON_ERROR_STOP=1 -d postgres <<'EOF'
SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';
EOF" | grep -q 1

if [ $? -eq 0 ]; then
    echo "NOTICE: Database $DB_NAME already exists, skipping creation."
else
    su - postgres -c "psql -v ON_ERROR_STOP=1 -d postgres -c 'CREATE DATABASE $DB_NAME OWNER $DB_USER;'"
    if [ $? -ne 0 ]; then
        echo "Error creating PostgreSQL database '$DB_NAME'. Aborting."
        exit 1
    else
        echo "NOTICE: Database $DB_NAME created and owned by $DB_USER."
    fi
fi

echo "PostgreSQL user '$DB_USER' and database '$DB_NAME' setup complete."
