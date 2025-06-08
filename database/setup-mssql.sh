#!/bin/bash

echo "=== SQL Server Database Setup ==="

# Prompt for SA password
echo "SQL Server SA password requirements:"
echo "- At least 8 characters"
echo "- Must contain uppercase, lowercase, numbers, and symbols"
echo
read -s -p "Enter SQL Server SA password: " MSSQL_SA_PASSWORD
echo

# Validate password strength (basic check)
if [[ ${#MSSQL_SA_PASSWORD} -lt 8 ]]; then
    echo "Error: Password must be at least 8 characters long"
    exit 1
fi

# Create directories
echo "Creating directories..."
sudo mkdir -p /var/database/mssql

# Set permissions
echo "Setting permissions..."
sudo chown -R 10001:0 /var/database/mssql
sudo chmod -R 755 /var/database/mssql

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
cat > /var/database/docker-compose-mssql.yml << EOF
version: '3.8'

services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: database-mssql-server
    environment:
      ACCEPT_EULA: Y
      MSSQL_SA_PASSWORD: $MSSQL_SA_PASSWORD
      MSSQL_PID: Developer
      MSSQL_AGENT_ENABLED: "1"
    ports:
      - "0.0.0.0:1433:1433"
    volumes:
      - /var/database/mssql:/var/opt/mssql/data
    command: /opt/mssql/bin/sqlservr
    restart: unless-stopped

volumes:
  mssql_data:
    driver: local
EOF

echo "SQL Server setup complete!"
echo "To start: cd /var/database && docker-compose -f docker-compose-mssql.yml up -d"
echo "To stop: cd /var/database && docker-compose -f docker-compose-mssql.yml down"
echo "Default login: sa / [your password]"