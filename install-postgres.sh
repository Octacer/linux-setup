#!/bin/bash

# PostgreSQL Installation Script
# Usage: sudo ./install-postgres.sh

set -e

# Source common functions
if [[ -f "./common-functions.sh" ]]; then
    source "./common-functions.sh"
else
    echo "Error: common-functions.sh not found in current directory"
    exit 1
fi

# PostgreSQL specific variables
SERVICE_NAME="PostgreSQL"
CONTAINER_NAME="postgres"
SERVICE_KEY="postgres"
COMPOSE_FILE="postgres.yml"
PROJECT_NAME="postgres"

# Function to collect PostgreSQL configuration
collect_postgres_config() {
    local reconfigure=${1:-false}
    
    print_header "$SERVICE_NAME Configuration"
    
    # Get current values if they exist
    local current_user=$(get_config "$SERVICE_KEY" "user")
    local current_db=$(get_config "$SERVICE_KEY" "database")
    local current_password=$(get_config "$SERVICE_KEY" "password")
    
    # Set defaults if not configured
    [[ -z "$current_user" ]] && current_user="postgres"
    [[ -z "$current_db" ]] && current_db="mydatabase"
    [[ -z "$current_password" ]] && current_password="postgres"
    
    while true; do
        print_status "Please provide the following information for $SERVICE_NAME:"
        echo ""
        
        # Collect configuration
        prompt_input "PostgreSQL Username" "$current_user" "pg_user"
        validate_required "Username" "$pg_user" || continue
        
        prompt_input "PostgreSQL Database Name" "$current_db" "pg_database"
        validate_required "Database Name" "$pg_database" || continue
        
        prompt_input "PostgreSQL Password" "$current_password" "pg_password" true
        validate_required "Password" "$pg_password" || continue
        
        # Prepare configuration summary
        local config_summary=(
            "Username: $pg_user"
            "Database: $pg_database"
            "Password: [HIDDEN]"
            "Port: 5432"
            "Host: localhost"
            "Container: $CONTAINER_NAME"
        )
        
        # Confirm configuration
        if confirm_config "$SERVICE_NAME" "${config_summary[@]}"; then
            break
        fi
        
        # If user chose to reconfigure, continue loop
        print_status "Let's reconfigure $SERVICE_NAME..."
        echo ""
    done
    
    # Store configuration
    update_config "$SERVICE_KEY" "user" "$pg_user"
    update_config "$SERVICE_KEY" "database" "$pg_database"
    update_config "$SERVICE_KEY" "password" "$pg_password"
    
    print_config "Configuration saved for $SERVICE_NAME"
}

# Function to generate PostgreSQL Docker Compose file
generate_postgres_compose() {
    print_status "Generating Docker Compose file: $COMPOSE_FILE"
    
    local pg_user=$(get_config "$SERVICE_KEY" "user")
    local pg_database=$(get_config "$SERVICE_KEY" "database")
    local pg_password=$(get_config "$SERVICE_KEY" "password")
    
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  postgres:
    image: postgres:15
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: $pg_database
      POSTGRES_USER: $pg_user
      POSTGRES_PASSWORD: $pg_password
    volumes:
      - ./postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
EOF
    
    print_status "Docker Compose file generated successfully"
}

# Function to setup PostgreSQL directories
setup_postgres_directories() {
    print_status "Setting up $SERVICE_NAME directories..."
    create_directory "./postgres_data"
}

# Function to install PostgreSQL
install_postgres() {
    print_header "Installing $SERVICE_NAME"
    
    # Check if already running
    if is_service_running "$CONTAINER_NAME"; then
        print_warning "$SERVICE_NAME is already running."
        print_status "Would you like to restart it with new configuration?"
        read -p "Restart $SERVICE_NAME? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_postgres
        else
            print_status "$SERVICE_NAME installation cancelled."
            exit 0
        fi
    fi
    
    # Collect configuration
    collect_postgres_config
    
    # Setup directories
    setup_postgres_directories
    
    # Generate compose file
    generate_postgres_compose
    
    # Start the service
    print_status "Starting $SERVICE_NAME container..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    # Wait for service to be ready
    wait_for_service "$SERVICE_NAME" "$CONTAINER_NAME" 15
    
    # Update status
    update_config "$SERVICE_KEY" "status" "running"
    
    # Show success message
    print_header "$SERVICE_NAME Installation Completed!"
    
    print_config "Connection Details:"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  Database: $(get_config "$SERVICE_KEY" "database")"
    echo "  Username: $(get_config "$SERVICE_KEY" "user")"
    echo "  Password: [stored in configuration]"
    echo ""
    echo "  Container: $CONTAINER_NAME"
    echo "  Status: $(get_config "$SERVICE_KEY" "status")"
    echo ""
    
    print_status "You can connect to PostgreSQL using:"
    echo "  docker exec -it $CONTAINER_NAME psql -U $(get_config "$SERVICE_KEY" "user") -d $(get_config "$SERVICE_KEY" "database")"
    echo ""
    
    print_status "Configuration saved in: $(realpath "$CONFIG_FILE")"
    print_status "$SERVICE_NAME is ready for use by other services!"
}

# Function to stop PostgreSQL
stop_postgres() {
    print_status "Stopping $SERVICE_NAME..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    update_config "$SERVICE_KEY" "status" "stopped"
    print_status "$SERVICE_NAME stopped successfully."
}

# Function to show PostgreSQL status
show_postgres_status() {
    show_service_status "$SERVICE_NAME" "$CONTAINER_NAME" "$SERVICE_KEY"
    
    if is_service_running "$CONTAINER_NAME"; then
        print_status "Database connection test:"
        local pg_user=$(get_config "$SERVICE_KEY" "user")
        local pg_password=$(get_config "$SERVICE_KEY" "password")
        
        if PGPASSWORD="$pg_password" docker exec "$CONTAINER_NAME" psql -U "$pg_user" -c "SELECT version();" > /dev/null 2>&1; then
            echo -e "  Database: ${GREEN}Connected${NC}"
        else
            echo -e "  Database: ${RED}Connection Failed${NC}"
        fi
    fi
}

# Function to show PostgreSQL logs
show_postgres_logs() {
    local lines=${1:-50}
    print_status "Showing last $lines lines of $SERVICE_NAME logs..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs --tail="$lines" -f
}

# Function to restart PostgreSQL
restart_postgres() {
    print_status "Restarting $SERVICE_NAME..."
    stop_postgres
    sleep 2
    install_postgres
}

# Function to show help
show_help() {
    echo "PostgreSQL Installation Script"
    echo ""
    echo "Usage: sudo $0 [action]"
    echo ""
    echo "Actions:"
    echo "  install  - Install and configure PostgreSQL (default)"
    echo "  stop     - Stop PostgreSQL service"
    echo "  restart  - Restart PostgreSQL service"
    echo "  status   - Show PostgreSQL status (no sudo required)"
    echo "  logs     - Show PostgreSQL logs (no sudo required)"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0                    # Install with interactive configuration"
    echo "  sudo $0 install           # Install with interactive configuration"
    echo "  sudo $0 restart           # Restart PostgreSQL"
    echo "  $0 status                 # Show status"
    echo "  $0 logs 100               # Show last 100 log lines"
    echo ""
    echo "Features:"
    echo "  • Interactive configuration with confirmation"
    echo "  • Persistent configuration storage"
    echo "  • Automatic directory setup"
    echo "  • Service status monitoring"
    echo "  • Easy connection testing"
}

# Main script logic
main() {
    local action=${1:-install}
    
    case $action in
        "install"|"")
            check_root
            check_prerequisites
            install_postgres
            ;;
        "stop")
            check_root
            stop_postgres
            ;;
        "restart")
            check_root
            check_prerequisites
            restart_postgres
            ;;
        "status")
            show_postgres_status
            ;;
        "logs")
            local lines=${2:-50}
            show_postgres_logs "$lines"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"