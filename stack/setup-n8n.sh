#!/bin/bash

echo "=== n8n Workflow Automation Setup ==="

# Prompt for basic authentication
echo "Setting up n8n Basic Authentication:"
read -p "Enter n8n username: " N8N_BASIC_AUTH_USER
read -s -p "Enter n8n password: " N8N_BASIC_AUTH_PASSWORD
echo

# Prompt for webhook URL
echo
read -p "Enter webhook URL (e.g., https://your-domain.com): " WEBHOOK_URL

# Prompt for PostgreSQL database connection
echo
echo "PostgreSQL Database Configuration:"
read -p "Enter PostgreSQL host (e.g., localhost or IP): " DB_POSTGRESDB_HOST
read -p "Enter PostgreSQL database name: " DB_POSTGRESDB_DATABASE
read -p "Enter PostgreSQL username: " DB_POSTGRESDB_USER
read -s -p "Enter PostgreSQL password: " DB_POSTGRESDB_PASSWORD
echo

# Prompt for port (optional)
echo
read -p "Enter n8n port (default 6001): " N8N_PORT
N8N_PORT=${N8N_PORT:-6001}

# Create directories
echo "Creating directories..."
sudo mkdir -p /var/data/n8n_data/data
sudo mkdir -p /var/data/n8n_data/custom-templates
sudo mkdir -p /var/data/n8n_data/redis_data

# Set permissions
echo "Setting permissions..."
sudo chown -R 1000:1000 /var/data/n8n_data/data
sudo chown -R 1000:1000 /var/data/n8n_data/custom-templates
sudo chown -R 999:999 /var/data/n8n_data/redis_data
sudo chmod -R 755 /var/data

# Create custom template file (optional)
cat > /var/data/n8n_data/custom-templates/custom.js << 'EOF'
// Custom n8n templates and configurations
console.log('Custom n8n templates loaded');
EOF

sudo chown 1000:1000 /var/data/n8n_data/custom-templates/custom.js

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
cat > /var/data/docker-compose-n8n.yml << EOF
version: '3.8'

services:
  master_n8n:
    image: n8nio/n8n:latest
    container_name: master_n8n
    ports:
      - "$N8N_PORT:5678"
    environment:
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: "true"
      N8N_LOG_LEVEL: debug
      LOG_LEVEL: debug
      N8N_BASIC_AUTH_ACTIVE: 1
      N8N_BASIC_AUTH_USER: $N8N_BASIC_AUTH_USER
      N8N_BASIC_AUTH_PASSWORD: $N8N_BASIC_AUTH_PASSWORD
      WEBHOOK_URL: $WEBHOOK_URL
      GENERIC_TIMEZONE: UTC
      N8N_CUSTOM_TEMPLATE_HEADER: /custom-templates/custom.js
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: $DB_POSTGRESDB_HOST
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: $DB_POSTGRESDB_DATABASE
      DB_POSTGRESDB_USER: $DB_POSTGRESDB_USER
      DB_POSTGRESDB_PASSWORD: $DB_POSTGRESDB_PASSWORD
    volumes:
      - /var/data/n8n_data/data:/home/node/.n8n
      - /var/data/n8n_data/custom-templates:/custom-templates
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - redis
    restart: always

  redis:
    image: redis:latest
    container_name: redis
    command: redis-server --maxmemory 1gb --maxmemory-policy allkeys-lru
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - /var/data/n8n_data/redis_data:/data

volumes:
  n8n_data:
    driver: local
  redis_data:
    driver: local
EOF

echo
echo "n8n setup complete!"
echo "========================================="
echo "Configuration Summary:"
echo "- n8n URL: http://localhost:$N8N_PORT"
echo "- Username: $N8N_BASIC_AUTH_USER"
echo "- Redis Port: 6379"
echo "- Data Directory: /var/data/n8n_data"
echo "- Redis Directory: /var/data/n8n_data/redis_data"
echo
echo "Commands:"
echo "To start: cd /var/data && docker-compose -f docker-compose-n8n.yml up -d"
echo "To stop: cd /var/data && docker-compose -f docker-compose-n8n.yml down"
echo "To view logs: cd /var/data && docker-compose -f docker-compose-n8n.yml logs -f"
echo
echo "Important Notes:"
echo "1. Make sure PostgreSQL database is running and accessible"
echo "2. Database will be automatically initialized on first startup"
echo "3. Custom templates can be added to /var/data/n8n_data/custom-templates/"
echo "4. n8n data persists in /var/data/n8n_data/data/"
echo "5. Redis data persists in /var/data/n8n_data/redis_data/"