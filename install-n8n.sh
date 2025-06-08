#!/bin/bash

# n8n Installation Script
# Usage: sudo ./install-n8n.sh

set -e

# Source common functions
if [[ -f "./common-functions.sh" ]]; then
    source "./common-functions.sh"
else
    echo "Error: common-functions.sh not found in current directory"
    exit 1
fi

# n8n specific variables
SERVICE_NAME="n8n"
CONTAINER_NAME="master_n8n"
SERVICE_KEY="n8n"
COMPOSE_FILE="master-n8n.yml"
PROJECT_NAME="master-n8n"

# Function to collect n8n configuration
collect_n8n_config() {
    local reconfigure=${1:-false}
    
    print_header "$SERVICE_NAME Configuration"
    
    # Get current values if they exist
    local current_domain=$(get_config "$SERVICE_KEY" "domain")
    local current_username=$(get_config "$SERVICE_KEY" "username")
    local current_password=$(get_config "$SERVICE_KEY" "password")
    
    # Set defaults if not configured
    [[ -z "$current_domain" ]] && current_domain="server.soulversecodes.com"
    [[ -z "$current_username" ]] && current_username="admin@n8n.com"
    [[ -z "$current_password" ]] && current_password="P@ss1234"
    
    while true; do
        print_status "Please provide the following information for $SERVICE_NAME:"
        echo ""
        
        # Collect configuration
        prompt_input "n8n Domain (without https://)" "$current_domain" "n8n_domain"
        validate_required "Domain" "$n8n_domain" || continue
        validate_domain "$n8n_domain" || continue
        
        prompt_input "n8n Username/Email" "$current_username" "n8n_username"
        validate_required "Username" "$n8n_username" || continue
        
        prompt_input "n8n Password" "$current_password" "n8n_password" true
        validate_required "Password" "$n8n_password" || continue
        
        # Prepare configuration summary
        local config_summary=(
            "Domain: https://$n8n_domain"
            "Username: $n8n_username"
            "Password: [HIDDEN]"
            "Port: 5001"
            "Database: n8n (auto-created)"
            "Container: $CONTAINER_NAME"
            "Webhook URL: https://$n8n_domain"
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
    update_config "$SERVICE_KEY" "domain" "$n8n_domain"
    update_config "$SERVICE_KEY" "username" "$n8n_username"
    update_config "$SERVICE_KEY" "password" "$n8n_password"
    
    print_config "Configuration saved for $SERVICE_NAME"
}

# Function to generate n8n Docker Compose file
generate_n8n_compose() {
    print_status "Generating Docker Compose file: $COMPOSE_FILE"
    
    local n8n_domain=$(get_config "$SERVICE_KEY" "domain")
    local n8n_username=$(get_config "$SERVICE_KEY" "username")
    local n8n_password=$(get_config "$SERVICE_KEY" "password")
    local pg_user=$(get_config "postgres" "user")
    local pg_password=$(get_config "postgres" "password")
    
    cat > "$COMPOSE_FILE" << EOF
services:
  master_n8n:
    image: n8nio/n8n:latest
    container_name: $CONTAINER_NAME
    ports:
      - "5001:5678"
    environment:
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: "true"
      N8N_LOG_LEVEL: debug
      LOG_LEVEL: debug
      
      N8N_BASIC_AUTH_ACTIVE: 1
      N8N_BASIC_AUTH_USER: $n8n_username
      N8N_BASIC_AUTH_PASSWORD: $n8n_password
      WEBHOOK_URL: https://$n8n_domain
      GENERIC_TIMEZONE: UTC

      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: localhost
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: $pg_user
      DB_POSTGRESDB_PASSWORD: $pg_password

    volumes:
      - ./.n8n_data/data:/home/node/.n8n
      - ./.n8n_data/custom-templates:/custom-templates
      - /var/run/docker.sock:/var/run/docker.sock
    restart: always
EOF
    
    print_status "Docker Compose file generated successfully"
}

# Function to setup n8n directories
setup_n8n_directories() {
    print_status "Setting up $SERVICE_NAME directories..."
    create_directory "./.n8n_data/data" "1000:1000"
    create_directory "./.n8n_data/custom-templates" "1000:1000"
    create_directory "./.redis_data"
}

# Function to install n8n
install_n8n() {
    print_header "Installing $SERVICE_NAME"
    
    # Check if already running
    if is_service_running "$CONTAINER_NAME"; then
        print_warning "$SERVICE_NAME is already running."
        print_status "Would you like to restart it with new configuration?"
        read -p "Restart $SERVICE_NAME? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_n8n
        else
            print_status "$SERVICE_NAME installation cancelled."
            exit 0
        fi
    fi
    
    # Check if PostgreSQL is available
    check_postgres_available
    
    # Collect configuration
    collect_n8n_config
    
    # Create n8n database
    create_database "n8n"
    
    # Setup directories
    setup_n8n_directories
    
    # Generate compose file
    generate_n8n_compose
    
    # Start the service
    print_status "Starting $SERVICE_NAME container..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    # Wait for service to be ready
    wait_for_service "$SERVICE_NAME" "$CONTAINER_NAME" 20
    
    # Configure domain with SSL
    local n8n_domain=$(get_config "$SERVICE_KEY" "domain")
    configure_domain "$n8n_domain" 5001 5001 https
    
    # Update status
    update_config "$SERVICE_KEY" "status" "running"
    
    # Show success message
    print_header "$SERVICE_NAME Installation Completed!"
    
    print_config "Access Details:"
    echo "  URL: https://$n8n_domain"
    echo "  Username: $(get_config "$SERVICE_KEY" "username")"
    echo "  Password: [stored in configuration]"
    echo "  Port: 5001"
    echo "  Database: n8n"
    echo ""
    echo "  Container: $CONTAINER_NAME"
    echo "  Status: $(get_config "$SERVICE_KEY" "status")"
    echo ""
    
    print_status "Webhook URLs will use: https://$n8n_domain"
    print_status "Redis is also running for caching and queues"
    echo ""
    
    print_status "Configuration saved in: $(realpath "$CONFIG_FILE")"
    print_status "$SERVICE_NAME is ready for workflow automation!"
}

# Function to stop n8n
stop_n8n() {
    print_status "Stopping $SERVICE_NAME..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    update_config "$SERVICE_KEY" "status" "stopped"
    print_status "$SERVICE_NAME stopped successfully."
}

# Function to show n8n status
show_n8n_status() {
    show_service_status "$SERVICE_NAME" "$CONTAINER_NAME" "$SERVICE_KEY"
    
    if is_service_running "$CONTAINER_NAME"; then
        print_status "Service health check:"
        local n8n_domain=$(get_config "$SERVICE_KEY" "domain")
        
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5001" | grep -q "200\|401"; then
            echo -e "  HTTP Service: ${GREEN}Running${NC}"
        else
            echo -e "  HTTP Service: ${RED}Not responding${NC}"
        fi
        
        if is_service_running "redis"; then
            echo -e "  Redis Cache: ${GREEN}Running${NC}"
        else
            echo -e "  Redis Cache: ${RED}Stopped${NC}"
        fi
    fi
}

# Function to show n8n logs
show_n8n_logs() {
    local lines=${1:-50}
    print_status "Showing last $lines lines of $SERVICE_NAME logs..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs --tail="$lines" -f
}

# Function to restart n8n
restart_n8n() {
    print_status "Restarting $SERVICE_NAME..."
    stop_n8n
    sleep 2
    
    # Start the service
    print_status "Restarting $SERVICE_NAME container..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
}

# Function to show help
show_help() {
    echo "n8n Workflow Automation Installation Script"
    echo ""
    echo "Usage: sudo $0 [action]"
    echo ""
    echo "Actions:"
    echo "  install  - Install and configure n8n (default)"
    echo "  stop     - Stop n8n service"
    echo "  restart  - Restart n8n service"
    echo "  status   - Show n8n status (no sudo required)"
    echo "  logs     - Show n8n logs (no sudo required)"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0                    # Install with interactive configuration"
    echo "  sudo $0 install           # Install with interactive configuration"
    echo "  sudo $0 restart           # Restart n8n"
    echo "  $0 status                 # Show status"
    echo "  $0 logs 100               # Show last 100 log lines"
    echo ""
    echo "Prerequisites:"
    echo "  • PostgreSQL must be running (auto-installs if needed)"
    echo "  • Domain configuration script (domain.sh) for HTTPS setup"
    echo ""
    echo "Features:"
    echo "  • Interactive configuration with confirmation"
    echo "  • Automatic database creation"
    echo "  • HTTPS domain configuration"
    echo "  • Redis integration for performance"
    echo "  • Webhook URL configuration"
    echo "  • Persistent data storage"
}

# Main script logic
main() {
    local action=${1:-install}
    
    case $action in
        "install"|"")
            check_root
            check_prerequisites
            install_n8n
            ;;
        "stop")
            check_root
            stop_n8n
            ;;
        "restart")
            check_root
            check_prerequisites
            restart_n8n
            ;;
        "status")
            show_n8n_status
            ;;
        "logs")
            local lines=${2:-50}
            show_n8n_logs "$lines"
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