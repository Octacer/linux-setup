#!/bin/bash

echo "=== PostgreSQL Database Setup ==="

# Prompt for database credentials
read -p "Enter PostgreSQL username: " POSTGRES_USER
read -s -p "Enter PostgreSQL password: " POSTGRES_PASSWORD
echo
read -p "Enter database name: " POSTGRES_DB

# Create directories
echo "Creating directories..."
sudo mkdir -p /var/database/postgres/data
sudo mkdir -p /var/database/postgres/init

# Set permissions
echo "Setting permissions..."
sudo chown -R 999:999 /var/database/postgres/data
sudo chmod -R 755 /var/database/postgres

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
cat > /var/database/docker-compose-postgres.yml << EOF
version: '3.8'

services:
  postgres:
    image: postgres:latest
    container_name: database-postgres-server
    environment:
      POSTGRES_USER: $POSTGRES_USER
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
      POSTGRES_DB: $POSTGRES_DB
    ports:
      - "0.0.0.0:5432:5432"
    volumes:
      - /var/database/postgres/data:/var/lib/postgresql/data
      - /var/database/postgres/init:/docker-entrypoint-initdb.d
    command: postgres -c listen_addresses='*'
    restart: unless-stopped

volumes:
  postgres_data:
    driver: local
EOF

echo "PostgreSQL setup complete!"
echo "To start: cd /var/database && docker-compose -f docker-compose-postgres.yml up -d"
echo "To stop: cd /var/database && docker-compose -f docker-compose-postgres.yml down"