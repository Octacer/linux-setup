#!/bin/bash

# Directus Installation Script
# Usage: sudo ./install-directus.sh

set -e

# Source common functions
if [[ -f "./common-functions.sh" ]]; then
    source "./common-functions.sh"
else
    echo "Error: common-functions.sh not found in current directory"
    exit 1
fi

# Directus specific variables
SERVICE_NAME="Directus"
CONTAINER_NAME="octacer_directus"
SERVICE_KEY="directus"
COMPOSE_FILE="master-directus.yml"
PROJECT_NAME="master-directus"

# Function to collect Directus configuration
collect_directus_config() {
    local reconfigure=${1:-false}
    
    print_header "$SERVICE_NAME Configuration"
    
    # Get current values if they exist
    local current_domain=$(get_config "$SERVICE_KEY" "domain")
    local current_username=$(get_config "$SERVICE_KEY" "username")
    local current_password=$(get_config "$SERVICE_KEY" "password")
    
    # Set defaults if not configured
    [[ -z "$current_domain" ]] && current_domain="cms.soulversecodes.com"
    [[ -z "$current_username" ]] && current_username="admin@admin.com"
    [[ -z "$current_password" ]] && current_password="P@ss1234"
    
    while true; do
        print_status "Please provide the following information for $SERVICE_NAME:"
        echo ""
        
        # Collect configuration
        prompt_input "Directus Domain (without https://)" "$current_domain" "directus_domain"
        validate_required "Domain" "$directus_domain" || continue
        validate_domain "$directus_domain" || continue
        
        prompt_input "Directus Admin Email" "$current_username" "directus_username"
        validate_required "Admin Email" "$directus_username" || continue
        
        # Validate email format
        if [[ ! "$directus_username" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Please enter a valid email address"
            continue
        fi
        
        prompt_input "Directus Admin Password" "$current_password" "directus_password" true
        validate_required "Password" "$directus_password" || continue
        
        # Prepare configuration summary
        local config_summary=(
            "Domain: https://$directus_domain"
            "Admin Email: $directus_username"
            "Admin Password: [HIDDEN]"
            "Port: 5000"
            "Database: directus (auto-created)"
            "Container: $CONTAINER_NAME"
            "File Upload Limit: 100MB"
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
    update_config "$SERVICE_KEY" "domain" "$directus_domain"
    update_config "$SERVICE_KEY" "username" "$directus_username"
    update_config "$SERVICE_KEY" "password" "$directus_password"
    
    print_config "Configuration saved for $SERVICE_NAME"
}

# Function to generate Directus Docker Compose file
generate_directus_compose() {
    print_status "Generating Docker Compose file: $COMPOSE_FILE"
    
    local directus_domain=$(get_config "$SERVICE_KEY" "domain")
    local directus_username=$(get_config "$SERVICE_KEY" "username")
    local directus_password=$(get_config "$SERVICE_KEY" "password")
    local pg_user=$(get_config "postgres" "user")
    local pg_password=$(get_config "postgres" "password")
    
    cat > "$COMPOSE_FILE" << EOF
services:
  octacer_directus_service:
    image: directus/directus:latest
    container_name: $CONTAINER_NAME
    ports:
      - "5000:8055"
    environment:
      DB_CLIENT: 'pg'
      DB_HOST: localhost
      DB_PORT: 5432
      DB_DATABASE: directus
      DB_USER: $pg_user
      DB_PASSWORD: $pg_password

      FILES_MAX_UPLOAD_SIZE: 100mb
      
      # Security
      KEY: 'directus-super-secret-key-$(date +%s)'
      SECRET: 'directus-secret-$(date +%s)'

      # Admin account
      ADMIN_EMAIL: "$directus_username"
      ADMIN_PASSWORD: "$directus_password"
      
      # Public URL
      PUBLIC_URL: "https://$directus_domain"

    volumes:
      - ./directus/uploads:/directus/uploads
      - ./directus/extensions:/directus/extensions
    network_mode: host
    restart: unless-stopped
EOF
    
    print_status "Docker Compose file generated successfully"
}

# Function to setup Directus directories
setup_directus_directories() {
    print_status "Setting up $SERVICE_NAME directories..."
    create_directory "./directus/uploads" "1000:1000"
    create_directory "./directus/extensions" "1000:1000"
}

# Function to install Directus
install_directus() {
    print_header "Installing $SERVICE_NAME"
    
    # Check if already running
    if is_service_running "$CONTAINER_NAME"; then
        print_warning "$SERVICE_NAME is already running."
        print_status "Would you like to restart it with new configuration?"
        read -p "Restart $SERVICE_NAME? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_directus
        else
            print_status "$SERVICE_NAME installation cancelled."
            exit 0
        fi
    fi
    
    # Check if PostgreSQL is available
    check_postgres_available
    
    # Collect configuration
    collect_directus_config
    
    # Create directus database
    create_database "directus"
    
    # Setup directories
    setup_directus_directories
    
    # Generate compose file
    generate_directus_compose
    
    # Start the service
    print_status "Starting $SERVICE_NAME container..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    # Wait for service to be ready
    wait_for_service "$SERVICE_NAME" "$CONTAINER_NAME" 30
    
    # Configure domain with SSL
    local directus_domain=$(get_config "$SERVICE_KEY" "domain")
    configure_domain "$directus_domain" 5000 5000 https
    
    # Update status
    update_config "$SERVICE_KEY" "status" "running"
    
    # Show success message
    print_header "$SERVICE_NAME Installation Completed!"
    
    print_config "Access Details:"
    echo "  URL: https://$directus_domain"
    echo "  Admin Email: $(get_config "$SERVICE_KEY" "username")"
    echo "  Admin Password: [stored in configuration]"
    echo "  Port: 5000"
    echo "  Database: directus"
    echo ""
    echo "  Container: $CONTAINER_NAME"
    echo "  Status: $(get_config "$SERVICE_KEY" "status")"
    echo ""
    
    print_status "File Upload Limit: 100MB"
    print_status "Uploads Directory: ./directus/uploads"
    print_status "Extensions Directory: ./directus/extensions"
    echo ""
    
    print_status "Configuration saved in: $(realpath "$CONFIG_FILE")"
    print_status "$SERVICE_NAME is ready for headless CMS operations!"
    
    print_warning "Note: It may take a few minutes for Directus to fully initialize the database."
    print_status "Check the logs if you experience any issues: $0 logs"
}

# Function to stop Directus
stop_directus() {
    print_status "Stopping $SERVICE_NAME..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    update_config "$SERVICE_KEY" "status" "stopped"
    print_status "$SERVICE_NAME stopped successfully."
}

# Function to show Directus status
show_directus_status() {
    show_service_status "$SERVICE_NAME" "$CONTAINER_NAME" "$SERVICE_KEY"
    
    if is_service_running "$CONTAINER_NAME"; then
        print_status "Service health check:"
        local directus_domain=$(get_config "$SERVICE_KEY" "domain")
        
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000/admin" | grep -q "200\|302"; then
            echo -e "  HTTP Service: ${GREEN}Running${NC}"
        else
            echo -e "  HTTP Service: ${RED}Not responding${NC}"
        fi
        
        # Check database connection
        local pg_user=$(get_config "postgres" "user")
        local pg_password=$(get_config "postgres" "password")
        
        if PGPASSWORD="$pg_password" docker exec postgres psql -U "$pg_user" -d directus -c "SELECT COUNT(*) FROM directus_users;" > /dev/null 2>&1; then
            echo -e "  Database: ${GREEN}Connected${NC}"
        else
            echo -e "  Database: ${YELLOW}Initializing${NC}"
        fi
        
        # Check uploads directory
        if [[ -d "./directus/uploads" ]]; then
            local upload_size=$(du -sh ./directus/uploads 2>/dev/null | cut -f1)
            echo -e "  Uploads: ${GREEN}Available${NC} ($upload_size used)"
        else
            echo -e "  Uploads: ${RED}Directory missing${NC}"
        fi
    fi
}

# Function to show Directus logs
show_directus_logs() {
    local lines=${1:-50}
    print_status "Showing last $lines lines of $SERVICE_NAME logs..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs --tail="$lines" -f
}

# Function to restart Directus
restart_directus() {
    print_status "Restarting $SERVICE_NAME..."
    stop_directus
    sleep 2
    install_directus
}

# Function to backup Directus data
backup_directus() {
    if ! is_service_running "$CONTAINER_NAME"; then
        print_error "$SERVICE_NAME is not running. Cannot perform backup."
        exit 1
    fi
    
    local backup_dir="./directus_backup_$(date +%Y%m%d_%H%M%S)"
    local pg_user=$(get_config "postgres" "user")
    local pg_password=$(get_config "postgres" "password")
    
    print_status "Creating Directus backup in: $backup_dir"
    
    mkdir -p "$backup_dir"
    
    # Backup database
    print_status "Backing up database..."
    PGPASSWORD="$pg_password" docker exec postgres pg_dump -U "$pg_user" directus > "$backup_dir/directus_db.sql"
    
    # Backup uploads
    if [[ -d "./directus/uploads" ]]; then
        print_status "Backing up uploads..."
        cp -r "./directus/uploads" "$backup_dir/"
    fi
    
    # Backup configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        print_status "Backing up configuration..."
        cp "$CONFIG_FILE" "$backup_dir/"
    fi
    
    print_status "Backup completed: $backup_dir"
}

# Function to show help
show_help() {
    echo "Directus Headless CMS Installation Script"
    echo ""
    echo "Usage: sudo $0 [action]"
    echo ""
    echo "Actions:"
    echo "  install  - Install and configure Directus (default)"
    echo "  stop     - Stop Directus service"
    echo "  restart  - Restart Directus service"
    echo "  status   - Show Directus status (no sudo required)"
    echo "  logs     - Show Directus logs (no sudo required)"
    echo "  backup   - Backup Directus data and uploads"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0                    # Install with interactive configuration"
    echo "  sudo $0 install           # Install with interactive configuration"
    echo "  sudo $0 restart           # Restart Directus"
    echo "  $0 status                 # Show status"
    echo "  $0 logs 100               # Show last 100 log lines"
    echo "  sudo $0 backup            # Create backup"
    echo ""
    echo "Prerequisites:"
    echo "  • PostgreSQL must be running (auto-installs if needed)"
    echo "  • Domain configuration script (domain.sh) for HTTPS setup"
    echo ""
    echo "Features:"
    echo "  • Interactive configuration with confirmation"
    echo "  • Automatic database creation"
    echo "  • HTTPS domain configuration"
    echo "  • File upload support (100MB limit)"
    echo "  • Extension support"
    echo "  • Database and file backup"
    echo "  • Email validation for admin account"
}

# Main script logic
main() {
    local action=${1:-install}
    
    case $action in
        "install"|"")
            check_root
            check_prerequisites
            install_directus
            ;;
        "stop")
            check_root
            stop_directus
            ;;
        "restart")
            check_root
            check_prerequisites
            restart_directus
            ;;
        "status")
            show_directus_status
            ;;
        "logs")
            local lines=${2:-50}
            show_directus_logs "$lines"
            ;;
        "backup")
            check_root
            backup_directus
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