#!/bin/bash

echo "=== MySQL Database Setup ==="

# Prompt for database credentials
read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
echo
read -p "Enter database name: " MYSQL_DATABASE
read -p "Enter MySQL username: " MYSQL_USER
read -s -p "Enter MySQL user password: " MYSQL_PASSWORD
echo

# Create directories
echo "Creating directories..."
sudo mkdir -p /var/database/mysql

# Set permissions
echo "Setting permissions..."
sudo chown -R 999:999 /var/database/mysql
sudo chmod -R 755 /var/database/mysql

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
cat > /var/database/docker-compose-mysql.yml << EOF
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: database-mysql-server
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_DATABASE: $MYSQL_DATABASE
      MYSQL_USER: $MYSQL_USER
      MYSQL_PASSWORD: $MYSQL_PASSWORD
    ports:
      - "0.0.0.0:3306:3306"
    volumes:
      - /var/database/mysql:/var/lib/mysql
    command: --default-authentication-plugin=mysql_native_password --bind-address=0.0.0.0
    restart: unless-stopped

volumes:
  mysql_data:
    driver: local
EOF

echo "MySQL setup complete!"
echo "To start: cd /var/database && docker-compose -f docker-compose-mysql.yml up -d"
echo "To stop: cd /var/database && docker-compose -f docker-compose-mysql.yml down"