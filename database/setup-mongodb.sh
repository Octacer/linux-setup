#!/bin/bash

echo "=== MongoDB Database Setup ==="

# Prompt for MongoDB credentials
read -p "Enter MongoDB root username: " MONGO_INITDB_ROOT_USERNAME
read -s -p "Enter MongoDB root password: " MONGO_INITDB_ROOT_PASSWORD
echo

# Create directories
echo "Creating directories..."
sudo mkdir -p /var/database/mongodb

# Set permissions
echo "Setting permissions..."
sudo chown -R 999:999 /var/database/mongodb
sudo chmod -R 755 /var/database/mongodb

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
cat > /var/database/docker-compose-mongodb.yml << EOF
version: '3.8'

services:
  mongodb:
    image: mongo:latest
    container_name: database-mongodb-server
    environment:
      MONGO_INITDB_ROOT_USERNAME: $MONGO_INITDB_ROOT_USERNAME
      MONGO_INITDB_ROOT_PASSWORD: $MONGO_INITDB_ROOT_PASSWORD
    ports:
      - "0.0.0.0:27017:27017"
    volumes:
      - /var/database/mongodb:/data/db
    restart: unless-stopped

volumes:
  mongodb_data:
    driver: local
EOF

echo "MongoDB setup complete!"
echo "To start: cd /var/database && docker-compose -f docker-compose-mongodb.yml up -d"
echo "To stop: cd /var/database && docker-compose-f docker-compose-mongodb.yml down"
echo "Connect with: mongo mongodb://$MONGO_INITDB_ROOT_USERNAME:[password]@localhost:27017"