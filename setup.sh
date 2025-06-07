#!/bin/bash

# Ubuntu Server Setup Script
# Installs nginx, certbot, and docker
# Run with: sudo bash install_script.sh

set -e  # Exit on any error

echo "🚀 Starting Ubuntu Server Setup..."
echo "This script will install nginx, certbot, and docker"
echo "----------------------------------------"

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Update system packages
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install common dependencies
print_status "Installing common dependencies..."
apt install -y curl wget gnupg lsb-release ca-certificates software-properties-common apt-transport-https

echo ""
echo "========================================="
echo "📦 INSTALLING NGINX"
echo "========================================="

# Install nginx
print_status "Installing nginx..."
apt install -y nginx

# Start and enable nginx
print_status "Starting and enabling nginx..."
systemctl start nginx
systemctl enable nginx

# Configure firewall for nginx
print_status "Configuring firewall for nginx..."
ufw allow 'Nginx Full'
ufw allow ssh
ufw --force enable

print_status "✅ Nginx installed successfully!"

echo ""
echo "========================================="
echo "🔒 INSTALLING CERTBOT"
echo "========================================="

# Install snapd if not present
if ! command -v snap &> /dev/null; then
    print_status "Installing snapd..."
    apt install -y snapd
fi

# Install certbot via snap (recommended method)
print_status "Installing certbot via snap..."
snap install core; snap refresh core
snap install --classic certbot

# Create symlink for certbot
print_status "Creating certbot symlink..."
ln -sf /snap/bin/certbot /usr/bin/certbot

print_status "✅ Certbot installed successfully!"

echo ""
echo "========================================="
echo "🐳 INSTALLING DOCKER"
echo "========================================="

# Remove old docker installations
print_status "Removing old docker installations..."
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
print_status "Adding Docker's GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
print_status "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index
print_status "Updating package index..."
apt update

# Install Docker Engine
print_status "Installing Docker Engine..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
print_status "Starting and enabling Docker..."
systemctl start docker
systemctl enable docker

# Add current user to docker group (if not root)
if [ "$SUDO_USER" ]; then
    print_status "Adding user $SUDO_USER to docker group..."
    usermod -aG docker $SUDO_USER
    print_warning "You'll need to log out and back in for docker group changes to take effect"
fi

print_status "✅ Docker installed successfully!"

echo ""
echo "========================================="
echo "🔍 INSTALLATION VERIFICATION"
echo "========================================="

# Verify installations
print_status "Verifying nginx installation..."
nginx -v

print_status "Verifying certbot installation..."
certbot --version

print_status "Verifying docker installation..."
docker --version
docker compose version

# Show service status
print_status "Checking service status..."
echo "Nginx status:"
systemctl is-active nginx
echo "Docker status:"
systemctl is-active docker

echo ""
echo "========================================="
echo "✅ INSTALLATION COMPLETE!"
echo "========================================="

print_status "All services installed successfully!"
echo ""
echo "📋 Next Steps:"
echo "1. Configure nginx virtual hosts in /etc/nginx/sites-available/"
echo "2. Use 'certbot --nginx -d yourdomain.com' to get SSL certificates"
echo "3. Start using Docker with 'docker run hello-world'"
echo ""
echo "🔧 Useful commands:"
echo "- nginx -t                    # Test nginx configuration"
echo "- systemctl reload nginx      # Reload nginx"
echo "- certbot renew --dry-run     # Test certificate renewal"
echo "- docker ps                   # List running containers"
echo ""
echo "📁 Important paths:"
echo "- Nginx config: /etc/nginx/"
echo "- Nginx sites: /etc/nginx/sites-available/"
echo "- Nginx logs: /var/log/nginx/"
echo ""

if [ "$SUDO_USER" ]; then
    print_warning "Remember to log out and back in to use docker without sudo!"
fi

echo "🎉 Setup complete! Your server is ready to use."
