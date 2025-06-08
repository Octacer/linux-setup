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

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check if running in interactive mode
is_interactive() {
    [[ -t 0 && -t 1 ]]
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
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        init_config
    fi
    
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
    print(data['services']['$service']['$key'])
except (KeyError, FileNotFoundError, json.JSONDecodeError):
    print('')
" 2>/dev/null || echo ""
}

# Function to update config
update_config() {
    local service=$1
    local key=$2
    local value=$3
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        init_config
    fi
    
    python3 -c "
import json
from datetime import datetime
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {'services': {}, 'last_updated': ''}

if '$service' not in data['services']:
    data['services']['$service'] = {}

data['services']['$service']['$key'] = '$value'
data['last_updated'] = datetime.now().isoformat()

with open('$CONFIG_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || print_error "Failed to update configuration"
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
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker ps &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker service."
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
    local allow_empty=${5:-false}
    
    local input=""
    
    while true; do
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
        
        # Use default if input is empty
        if [[ -z "$input" && -n "$default" ]]; then
            input="$default"
        fi
        
        # Check if empty input is allowed
        if [[ -z "$input" && "$allow_empty" != "true" ]]; then
            print_error "This field cannot be empty. Please enter a value."
            continue
        fi
        
        break
    done
    
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
    
    local choice
    while true; do
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
                ;;
        esac
    done
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
    local max_retries=${4:-30}
    
    print_status "Waiting for $service_name to be ready..."
    sleep "$wait_time"
    
    local retries=0
    while [[ $retries -lt $max_retries ]]; do
        if is_service_running "$container_name"; then
            print_success "$service_name is running successfully!"
            return 0
        fi
        
        sleep 2
        ((retries++))
        
        if [[ $((retries % 10)) -eq 0 ]]; then
            print_status "Still waiting for $service_name... ($retries/$max_retries)"
        fi
    done
    
    print_warning "$service_name may not be running properly. Check logs if needed."
    return 1
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
            print_success "Domain configuration completed successfully"
            return 0
        else
            print_warning "Domain configuration may have failed. Check manually if needed."
            return 1
        fi
    else
        print_warning "Domain script not available. Skipping domain configuration."
        return 1
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
        
        # Show additional container info
        local container_info=$(docker ps --filter "name=^${container_name}$" --format "table {{.Status}}\t{{.Ports}}" | tail -n +2)
        if [[ -n "$container_info" ]]; then
            echo "  Container: $container_info"
        fi
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
    
    # Remove protocol if present
    domain=$(echo "$domain" | sed 's|^https\?://||')
    
    # Basic domain validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_error "Invalid domain format: $domain"
        print_status "Domain should be like: example.com or subdomain.example.com"
        return 1
    fi
    return 0
}

# Function to validate email format
validate_email() {
    local email=$1
    
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Function to validate port number
validate_port() {
    local port=$1
    local port_name=${2:-"Port"}
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        print_error "$port_name must be a number between 1 and 65535"
        return 1
    fi
    return 0
}

# Function to check if PostgreSQL is available
check_postgres_available() {
    if ! is_service_running "postgres"; then
        print_warning "PostgreSQL is not running."
        print_status "Would you like to install PostgreSQL first?"
        
        local choice
        if is_interactive; then
            read -p "Install PostgreSQL? (y/N): " -n 1 -r choice
            echo
        else
            choice="y"
            print_status "Non-interactive mode: Installing PostgreSQL automatically."
        fi
        
        if [[ $choice =~ ^[Yy]$ ]]; then
            if [[ -f "./install-postgres.sh" ]]; then
                print_status "Running PostgreSQL installation..."
                if is_interactive; then
                    ./install-postgres.sh
                else
                    # Non-interactive PostgreSQL installation would need preset values
                    print_error "Non-interactive PostgreSQL installation not implemented yet."
                    exit 1
                fi
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
    local pg_database=$(get_config "postgres" "database")  # Get the main database

    if [[ -z "$pg_user" || -z "$pg_password" || -z "$pg_database" ]]; then
        print_error "PostgreSQL configuration not found. Please install PostgreSQL first."
        exit 1
    fi

    print_status "Creating database: $db_name"
    print_status "Connecting to PostgreSQL as user '$pg_user' on database '$pg_database'"

    # Connect to the main database first, then create the new database
    PGPASSWORD="$pg_password" docker exec postgres psql -U "$pg_user" -d "$pg_database" -c "CREATE DATABASE $db_name;" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Database '$db_name' created successfully."
    else
        print_error "Failed to create database '$db_name'."
        echo "Trying to see the detailed error:"
        PGPASSWORD="$pg_password" docker exec postgres psql -U "$pg_user" -d "$pg_database" -c "CREATE DATABASE $db_name;"
    fi
}

# Function to check if port is in use
check_port_available() {
    local port=$1
    local service_name=${2:-"Service"}
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        print_warning "Port $port is already in use."
        print_status "This might conflict with $service_name."
        return 1
    fi
    return 0
}

# Function to get container logs
get_container_logs() {
    local container_name=$1
    local lines=${2:-50}
    
    if is_service_running "$container_name"; then
        docker logs --tail="$lines" "$container_name"
    else
        print_error "Container '$container_name' is not running."
        return 1
    fi
}

# Function to restart container
restart_container() {
    local container_name=$1
    local service_name=${2:-$container_name}
    
    print_status "Restarting container: $container_name"
    
    if is_service_running "$container_name"; then
        docker restart "$container_name"
        if [[ $? -eq 0 ]]; then
            print_success "$service_name restarted successfully."
        else
            print_error "Failed to restart $service_name."
            return 1
        fi
    else
        print_warning "$service_name is not running. Cannot restart."
        return 1
    fi
}

# Function to backup service data
backup_service_data() {
    local service_name=$1
    local data_dir=$2
    local backup_base_dir=${3:-"./backups"}
    
    local backup_dir="$backup_base_dir/${service_name}_backup_$(date +%Y%m%d_%H%M%S)"
    
    print_status "Creating backup for $service_name..."
    mkdir -p "$backup_dir"
    
    if [[ -d "$data_dir" ]]; then
        cp -r "$data_dir" "$backup_dir/"
        print_success "Backup created: $backup_dir"
    else
        print_warning "Data directory not found: $data_dir"
        return 1
    fi
}

# Function to check system resources
check_system_resources() {
    print_status "Checking system resources..."
    
    # Check available memory
    local memory_mb=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [[ $memory_mb -lt 1024 ]]; then
        print_warning "Low available memory: ${memory_mb}MB. Recommended: 1GB+"
    fi
    
    # Check available disk space
    local disk_space=$(df . | awk 'NR==2{print $4}')
    local disk_space_gb=$((disk_space / 1024 / 1024))
    if [[ $disk_space_gb -lt 5 ]]; then
        print_warning "Low disk space: ${disk_space_gb}GB available. Recommended: 5GB+"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        print_warning "Low CPU cores: $cpu_cores. Recommended: 2+"
    fi
    
    print_status "System resources check completed."
}

# Function to cleanup old containers and images
cleanup_docker() {
    print_status "Cleaning up Docker resources..."
    
    # Remove stopped containers
    local stopped_containers=$(docker ps -aq --filter "status=exited")
    if [[ -n "$stopped_containers" ]]; then
        docker rm $stopped_containers
        print_status "Removed stopped containers."
    fi
    
    # Remove unused images
    docker image prune -f
    print_status "Removed unused images."
    
    # Remove unused volumes
    docker volume prune -f
    print_status "Removed unused volumes."
    
    print_success "Docker cleanup completed."
}

# Function to show help for common functions
show_common_help() {
    echo "Common Functions Library"
    echo "This file provides shared functions for all service installation scripts."
    echo ""
    echo "Available Functions:"
    echo "  Output Functions:"
    echo "    print_status, print_warning, print_error, print_header"
    echo "    print_question, print_config, print_confirm, print_success"
    echo ""
    echo "  System Functions:"
    echo "    check_root, is_interactive, check_prerequisites"
    echo "    check_system_resources, cleanup_docker"
    echo ""
    echo "  Configuration Functions:"
    echo "    init_config, get_config, update_config"
    echo "    prompt_input, confirm_config"
    echo ""
    echo "  Validation Functions:"
    echo "    validate_required, validate_domain, validate_email, validate_port"
    echo ""
    echo "  Service Management Functions:"
    echo "    is_service_running, wait_for_service, show_service_status"
    echo "    restart_container, get_container_logs"
    echo ""
    echo "  Database Functions:"
    echo "    check_postgres_available, create_database"
    echo ""
    echo "  Utility Functions:"
    echo "    create_directory, configure_domain, backup_service_data"
    echo "    check_port_available"
    echo ""
    echo "Usage: source ./common-functions.sh"
}

# Export functions for use in other scripts
export -f print_status print_warning print_error print_header print_question print_config print_confirm print_success
export -f check_root is_interactive init_config get_config update_config check_prerequisites
export -f prompt_input confirm_config create_directory is_service_running wait_for_service
export -f configure_domain show_service_status validate_required validate_domain validate_email validate_port
export -f check_postgres_available create_database check_port_available get_container_logs restart_container
export -f backup_service_data check_system_resources cleanup_docker show_common_help

# Main execution (if script is run directly instead of sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        "help"|"-h"|"--help")
            show_common_help
            ;;
        "test")
            print_status "Testing common functions..."
            check_prerequisites
            print_success "Common functions are working correctly!"
            ;;
        "init")
            print_status "Initializing configuration..."
            init_config
            print_success "Configuration file created: $CONFIG_FILE"
            ;;
        *)
            echo "Common Functions Library"
            echo "Usage: $0 [help|test|init]"
            echo "Or: source $0 (to load functions in another script)"
            ;;
    esac
fi