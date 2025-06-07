#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script with sudo or as root"
    exit 1
fi

# Check if arguments are passed
if [ -z "$1" ]; then
    read -p "Enter Domain: " DOMAIN_NAME
else
    DOMAIN_NAME=$1
fi

if [ -z "$2" ]; then
    read -p "Enter Backend Port (the port your application runs on): " BACKEND_PORT
else
    BACKEND_PORT=$2
fi

# Ask for protocol type
if [ -z "$3" ]; then
    echo "Select backend protocol:"
    echo "1) HTTP (default)"
    echo "2) HTTPS"
    read -p "Enter choice (1 or 2): " PROTOCOL_CHOICE
    if [ "$PROTOCOL_CHOICE" = "2" ]; then
        BACKEND_PROTOCOL="https"
    else
        BACKEND_PROTOCOL="http"
    fi
else
    if [ "$3" = "https" ]; then
        BACKEND_PROTOCOL="https"
    else
        BACKEND_PROTOCOL="http"
    fi
fi

# Ask about IPv6 support
read -p "Enable IPv6 support? (y/N): " IPV6_SUPPORT
if [[ "$IPV6_SUPPORT" =~ ^[Yy]$ ]]; then
    ENABLE_IPV6=true
else
    ENABLE_IPV6=false
fi

# Ask about SSE/WebSocket support
read -p "Enable Server-Sent Events (SSE) or WebSocket support? (y/N): " SSE_SUPPORT
if [[ "$SSE_SUPPORT" =~ ^[Yy]$ ]]; then
    ENABLE_SSE=true
else
    ENABLE_SSE=false
fi

# Validate inputs
if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]] && [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$ ]]; then
    print_warning "Domain name format might be invalid: $DOMAIN_NAME"
    read -p "Continue anyway? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if ! [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]] || [ "$BACKEND_PORT" -lt 1 ] || [ "$BACKEND_PORT" -gt 65535 ]; then
    print_error "Invalid port number: $BACKEND_PORT"
    exit 1
fi

# Output the values
print_status "Configuration Summary:"
echo "Domain: $DOMAIN_NAME"
echo "Backend Port: $BACKEND_PORT"
echo "Backend Protocol: $BACKEND_PROTOCOL"
echo "IPv6 Support: $ENABLE_IPV6"
echo "SSE/WebSocket Support: $ENABLE_SSE"
echo

# Confirm before proceeding
read -p "Proceed with this configuration? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_status "Aborted by user"
    exit 0
fi

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    print_error "Nginx is not installed. Please install nginx first."
    exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    print_error "Certbot is not installed. Please install certbot first."
    exit 1
fi

# Stop Nginx
print_status "Stopping Nginx..."
systemctl stop nginx

# Kill any processes using ports 80 and 443
print_status "Freeing up ports 80 and 443..."
fuser -k 80/tcp 2>/dev/null || true
fuser -k 443/tcp 2>/dev/null || true

# Wait a moment for processes to stop
sleep 2

# Install SSL certificate
print_status "Obtaining SSL certificate for $DOMAIN_NAME..."
if ! certbot certonly --standalone -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email; then
    print_error "Failed to obtain SSL certificate"
    systemctl start nginx
    exit 1
fi

# Build nginx configuration
build_nginx_config() {
    local config=""
    
    # HTTP server block (redirect to HTTPS)
    config+="server {
    listen 80;"
    
    if [ "$ENABLE_IPV6" = true ]; then
        config+="
    listen [::]:80;"
    fi
    
    config+="
    server_name $DOMAIN_NAME;
    return 301 https://\$host\$request_uri;
}

"

    # HTTPS server block
    config+="server {
    listen 443 ssl;"
    
    if [ "$ENABLE_IPV6" = true ]; then
        config+="
    listen [::]:443 ssl;"
    fi
    
    config+="
    server_name $DOMAIN_NAME;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_session_cache builtin:1000 shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection \"1; mode=block\";
    add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\";
    
    # Gzip compression
    gzip on;
    gzip_http_version 1.1;
    gzip_vary on;
    gzip_comp_level 6;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/x-javascript
        application/xml
        application/rss+xml
        application/atom+xml
        application/rdf+xml;
    gzip_buffers 16 8k;
    gzip_disable \"MSIE [1-6]\.(?!.*SV1)\";
    
    # Proxy configuration
    location / {
        proxy_pass $BACKEND_PROTOCOL://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;"
        
    if [ "$ENABLE_SSE" = true ]; then
        config+="
        proxy_set_header Connection \$connection_upgrade;"
    else
        config+="
        proxy_set_header Connection keep-alive;"
    fi
    
    config+="
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;"
        
    if [ "$ENABLE_SSE" = true ]; then
        config+="
        
        # SSE/WebSocket specific settings
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_cache off;"
    fi
    
    config+="
    }
}"

    echo "$config"
}

# Check if configuration already exists
CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN_NAME"
ENABLED_LINK="/etc/nginx/sites-enabled/$DOMAIN_NAME"

if [ -f "$CONFIG_FILE" ]; then
    print_warning "Configuration file already exists: $CONFIG_FILE"
    echo "Choose an option:"
    echo "1) Backup existing and create new (recommended)"
    echo "2) Overwrite existing configuration"
    echo "3) View existing configuration and exit"
    echo "4) Exit without changes"
    read -p "Enter choice (1-4): " FILE_CHOICE
    
    case $FILE_CHOICE in
        1)
            BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
            print_status "Creating backup: $BACKUP_FILE"
            cp "$CONFIG_FILE" "$BACKUP_FILE"
            print_status "Backup created successfully"
            ;;
        2)
            print_warning "Existing configuration will be overwritten"
            ;;
        3)
            print_status "Current configuration:"
            echo "----------------------------------------"
            cat "$CONFIG_FILE"
            echo "----------------------------------------"
            exit 0
            ;;
        4)
            print_status "Exiting without changes"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
fi

# Generate nginx configuration
print_status "Generating Nginx configuration..."
NGINX_CONFIG=$(build_nginx_config)

# Write configuration to file
echo "$NGINX_CONFIG" > "$CONFIG_FILE"
print_status "Configuration written to: $CONFIG_FILE"

# Check if symbolic link exists and handle it
if [ -L "$ENABLED_LINK" ]; then
    if [ -e "$ENABLED_LINK" ]; then
        print_status "Updating existing symbolic link"
    else
        print_warning "Removing broken symbolic link"
        rm "$ENABLED_LINK"
    fi
elif [ -f "$ENABLED_LINK" ]; then
    print_warning "Found regular file instead of symbolic link at $ENABLED_LINK"
    LINK_BACKUP="${ENABLED_LINK}.backup.$(date +%Y%m%d_%H%M%S)"
    print_status "Creating backup: $LINK_BACKUP"
    mv "$ENABLED_LINK" "$LINK_BACKUP"
fi

# Create symbolic link
print_status "Enabling site configuration..."
ln -sf "/etc/nginx/sites-available/$DOMAIN_NAME" "/etc/nginx/sites-enabled/$DOMAIN_NAME"

# Add connection_upgrade map if SSE is enabled and not already present
if [ "$ENABLE_SSE" = true ]; then
    if ! grep -q "connection_upgrade" /etc/nginx/nginx.conf; then
        print_status "Adding connection upgrade map to nginx.conf..."
        sed -i '/http {/a\\n    # WebSocket and SSE support\n    map $http_upgrade $connection_upgrade {\n        default upgrade;\n        '\'''\'' close;\n    }\n' /etc/nginx/nginx.conf
    fi
fi

# Test nginx configuration
print_status "Testing Nginx configuration..."
if ! nginx -t; then
    print_error "Nginx configuration test failed"
    rm -f "/etc/nginx/sites-enabled/$DOMAIN_NAME"
    exit 1
fi

# Start Nginx
print_status "Starting Nginx..."
if ! systemctl start nginx; then
    print_error "Failed to start Nginx"
    exit 1
fi

if ! systemctl enable nginx; then
    print_warning "Failed to enable Nginx auto-start"
fi

# Verify the setup
print_status "Verifying setup..."
sleep 3

# Check if ports are listening
if ss -tuln | grep -q ":80 "; then
    print_status "✓ HTTP port 80 is listening"
else
    print_warning "✗ HTTP port 80 is not listening"
fi

if ss -tuln | grep -q ":443 "; then
    print_status "✓ HTTPS port 443 is listening"
else
    print_warning "✗ HTTPS port 443 is not listening"
fi

# Final status
print_status "Setup completed successfully!"
echo
echo "Your SSL-enabled nginx configuration for $DOMAIN_NAME is now active."
echo "Configuration file: $CONFIG_FILE"
if [ -n "$BACKUP_FILE" ]; then
    echo "Previous configuration backed up to: $BACKUP_FILE"
fi
echo "Backend: $BACKEND_PROTOCOL://localhost:$BACKEND_PORT"
echo
echo "Test your setup:"
echo "  HTTP redirect: curl -I http://$DOMAIN_NAME"
echo "  HTTPS access: curl -I https://$DOMAIN_NAME"
echo
print_warning "Remember to:"
echo "  - Ensure your application is running on port $BACKEND_PORT"
echo "  - Set up automatic SSL renewal: certbot renew --dry-run"
echo "  - Configure your firewall to allow ports 80 and 443"
echo
print_status "Additional commands:"
echo "  - View current config: cat $CONFIG_FILE"
echo "  - Edit config: nano $CONFIG_FILE"
echo "  - Test nginx config: nginx -t"
echo "  - Reload nginx: systemctl reload nginx"
if [ -n "$BACKUP_FILE" ]; then
    echo "  - Restore backup: cp $BACKUP_FILE $CONFIG_FILE && systemctl reload nginx"
fi