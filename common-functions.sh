#!/bin/bash

# Common Functions for Service Installation Scripts
# This file contains shared functions used by all service scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOMAIN_SCRIPT="./domain.sh"
SETUP_DIR="$(pwd)"
CONFIG_FILE="./services-config.json"

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

print_header() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================${NC}"
}

print_question() {
    echo -e "${PURPLE}[INPUT]${NC} $1"
}

print_config() {
    echo -e "${CYAN}[CONFIG]${NC} $1"
}

print_confirm() {
    echo -e "${YELLOW}[CONFIRM]${NC} $1"
}

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to initialize config file
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_status "Creating configuration file..."
        cat > "$CONFIG_FILE" << 'EOF'
{
  "services": {
    "postgres": {
      "status": "not_configured",
      "user": "",
      "database": "",
      "password": "",
      "port": "5432",
      "host": "localhost"
    },
    "n8n": {
      "status": "not_configured",
      "domain": "",
      "username": "",
      "password": "",
      "port": "5001",
      "db_name": "n8n"
    },
    "directus": {
      "status": "not_configured",
      "domain": "",
      "username": "",
      "password": "",
      "port": "5000",
      "db_name": "directus"
    },
    "waha": {
      "status": "not_configured",
      "domain": "",
      "username": "",
      "password": "",
      "port": "5002"
    },
    "selenium": {
      "status": "not_configured",
      "port": "4444",
      "vnc_port": "7900",
      "scale_chrome": "2",
      "scale_firefox": "2"
    }
  },
  "last_updated": ""
}
EOF
    fi
}

# Function to read config value
get_config() {
    local service=$1
    local key=$2
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
    print(data['services']['$service']['$key'])
except:
    print('')
" 2>/dev/null
}

# Function to update config
update_config() {
    local service=$1
    local key=$2
    local value=$3
    python3 -c "
import json
from datetime import datetime
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
    data['services']['$service']['$key'] = '$value'
    data['last_updated'] = datetime.now().isoformat()
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print('Error updating config:', e)
"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Python3 is installed
    if ! command -v python3 &> /dev/null; then
        print_error "Python3 is required for configuration management. Please install Python3."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if domain.sh exists and is executable
    if [[ ! -f "$DOMAIN_SCRIPT" ]]; then
        print_warning "domain.sh not found. Domain configuration will be skipped."
    elif [[ ! -x "$DOMAIN_SCRIPT" ]]; then
        print_status "Making domain.sh executable..."
        chmod +x "$DOMAIN_SCRIPT"
    fi
    
    init_config
    print_status "Prerequisites check completed."
}

# Function to prompt for input with default value
prompt_input() {
    local prompt=$1
    local default=$2
    local var_name=$3
    local is_password=${4:-false}
    
    if [[ "$is_password" == "true" ]]; then
        print_question "$prompt"
        read -s -p "Enter value: " input
        echo
    else
        if [[ -n "$default" ]]; then
            print_question "$prompt (default: $default)"
            read -p "Enter value: " input
        else
            print_question "$prompt"
            read -p "Enter value: " input
        fi
    fi
    
    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    
    eval "$var_name='$input'"
}

# Function to confirm configuration
confirm_config() {
    local service_name=$1
    shift
    local config_items=("$@")
    
    print_header "Configuration Summary for $service_name"
    
    for item in "${config_items[@]}"; do
        echo "  $item"
    done
    
    echo ""
    print_confirm "Do you want to proceed with this configuration?"
    echo "1) Yes, install with these settings"
    echo "2) No, let me reconfigure"
    echo "3) Cancel installation"
    
    read -p "Choose option (1-3): " choice
    
    case $choice in
        1)
            return 0
            ;;
        2)
            return 1
            ;;
        3)
            print_status "Installation cancelled."
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please select 1, 2, or 3."
            confirm_config "$service_name" "${config_items[@]}"
            ;;
    esac
}

# Function to create directories with proper permissions
create_directory() {
    local dir_path=$1
    local owner=${2:-""}
    
    print_status "Creating directory: $dir_path"
    mkdir -p "$dir_path"
    
    if [[ -n "$owner" ]]; then
        print_status "Setting ownership to $owner for $dir_path"
        chown -R "$owner" "$dir_path"
    fi
}

# Function to check if service is running
is_service_running() {
    local container_name=$1
    docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name=$1
    local container_name=$2
    local wait_time=${3:-10}
    
    print_status "Waiting for $service_name to be ready..."
    sleep "$wait_time"
    
    if is_service_running "$container_name"; then
        print_status "$service_name is running successfully!"
        return 0
    else
        print_warning "$service_name may not be running properly. Check logs if needed."
        return 1
    fi
}

# Function to configure domain with SSL
configure_domain() {
    local domain=$1
    local internal_port=$2
    local external_port=$3
    local protocol=${4:-https}
    
    if [[ -x "$DOMAIN_SCRIPT" ]]; then
        print_status "Configuring domain: $domain"
        print_status "Running: $DOMAIN_SCRIPT $domain $internal_port $external_port $protocol"
        "$DOMAIN_SCRIPT" "$domain" "$internal_port" "$external_port" "$protocol"
        
        if [[ $? -eq 0 ]]; then
            print_status "Domain configuration completed successfully"
        else
            print_warning "Domain configuration may have failed. Check manually if needed."
        fi
    else
        print_warning "Domain script not available. Skipping domain configuration."
    fi
}

# Function to show service status
show_service_status() {
    local service_name=$1
    local container_name=$2
    local service_key=$3
    
    echo -e "${BLUE}$service_name:${NC}"
    if is_service_running "$container_name"; then
        echo -e "  Status: ${GREEN}Running${NC}"
    else
        echo -e "  Status: ${RED}Stopped${NC}"
    fi
    
    if [[ -n "$service_key" ]]; then
        local domain=$(get_config "$service_key" "domain")
        local port=$(get_config "$service_key" "port")
        local username=$(get_config "$service_key" "username")
        
        [[ -n "$domain" ]] && echo "  Domain: https://$domain"
        [[ -n "$port" ]] && echo "  Port: $port"
        [[ -n "$username" ]] && echo "  Username: $username"
    fi
    echo ""
}

# Function to validate required fields
validate_required() {
    local field_name=$1
    local field_value=$2
    
    if [[ -z "$field_value" ]]; then
        print_error "$field_name is required and cannot be empty."
        return 1
    fi
    return 0
}

# Function to validate domain format
validate_domain() {
    local domain=$1
    
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_error "Invalid domain format: $domain"
        return 1
    fi
    return 0
}

# Function to check if PostgreSQL is available
check_postgres_available() {
    if ! is_service_running "postgres"; then
        print_warning "PostgreSQL is not running."
        print_status "Would you like to install PostgreSQL first?"
        read -p "Install PostgreSQL? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [[ -f "./install-postgres.sh" ]]; then
                print_status "Running PostgreSQL installation..."
                sudo ./install-postgres.sh
            else
                print_error "PostgreSQL installation script not found."
                exit 1
            fi
        else
            print_error "PostgreSQL is required for this service."
            exit 1
        fi
    fi
}

# Function to create database
create_database() {
    local db_name=$1
    local pg_user=$(get_config "postgres" "user")
    local pg_password=$(get_config "postgres" "password")
    
    if [[ -z "$pg_user" || -z "$pg_password" ]]; then
        print_error "PostgreSQL configuration not found. Please install PostgreSQL first."
        exit 1
    fi
    
    print_status "Creating database: $db_name"
    PGPASSWORD="$pg_password" docker exec postgres psql -U "$pg_user" -c "CREATE DATABASE $db_name;" 2>/dev/null || {
        print_warning "Database '$db_name' might already exist or there was an error creating it."
    }
}

# Export functions for use in other scripts
export -f print_status print_warning print_error print_header print_question print_config print_confirm
export -f check_root init_config get_config update_config check_prerequisites
export -f prompt_input confirm_config create_directory is_service_running wait_for_service
export -f configure_domain show_service_status validate_required validate_domain
export -f check_postgres_available create_database