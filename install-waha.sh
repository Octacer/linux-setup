#!/bin/bash

# WAHA WhatsApp API Installation Script
# Usage: sudo ./install-waha.sh

set -e

# Source common functions
if [[ -f "./common-functions.sh" ]]; then
    source "./common-functions.sh"
else
    echo "Error: common-functions.sh not found in current directory"
    exit 1
fi

# WAHA specific variables
SERVICE_NAME="WAHA WhatsApp API"
CONTAINER_NAME="master_wahachat"
SERVICE_KEY="waha"
COMPOSE_FILE="waha-chat.yml"
PROJECT_NAME="waha-chat"

# Function to collect WAHA configuration
collect_waha_config() {
    local reconfigure=${1:-false}
    
    print_header "$SERVICE_NAME Configuration"
    
    # Get current values if they exist
    local current_domain=$(get_config "$SERVICE_KEY" "domain")
    local current_username=$(get_config "$SERVICE_KEY" "username")
    local current_password=$(get_config "$SERVICE_KEY" "password")
    
    # Set defaults if not configured
    [[ -z "$current_domain" ]] && current_domain="whatsapp.soulversecodes.com"
    [[ -z "$current_username" ]] && current_username="admin"
    [[ -z "$current_password" ]] && current_password="admin"
    
    while true; do
        print_status "Please provide the following information for $SERVICE_NAME:"
        echo ""
        
        # Collect configuration
        prompt_input "WAHA Domain (without https://)" "$current_domain" "waha_domain"
        validate_required "Domain" "$waha_domain" || continue
        validate_domain "$waha_domain" || continue
        
        prompt_input "Dashboard & Swagger Username" "$current_username" "waha_username"
        validate_required "Username" "$waha_username" || continue
        
        prompt_input "Dashboard & Swagger Password" "$current_password" "waha_password" true
        validate_required "Password" "$waha_password" || continue
        
        # Prepare configuration summary
        local config_summary=(
            "Domain: https://$waha_domain"
            "Dashboard Username: $waha_username"
            "Dashboard Password: [HIDDEN]"
            "Swagger Username: $waha_username (same as dashboard)"
            "Swagger Password: [HIDDEN] (same as dashboard)"
            "Port: 5002"
            "Container: $CONTAINER_NAME"
            "Engine: NOWEB (No browser required)"
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
    update_config "$SERVICE_KEY" "domain" "$waha_domain"
    update_config "$SERVICE_KEY" "username" "$waha_username"
    update_config "$SERVICE_KEY" "password" "$waha_password"
    
    print_config "Configuration saved for $SERVICE_NAME"
}

# Function to check for WAHA image
check_waha_image() {
    print_status "Checking for WAHA Plus image..."
    
    if ! docker images | grep -q "waha-plus"; then
        print_warning "WAHA Plus image not found!"
        print_status "You need to load the WAHA Plus image first."
        echo ""
        print_status "If you have the waha-plus.tar file, run:"
        echo "  docker load -i ./waha-plus.tar"
        echo ""
        print_status "Or pull from registry:"
        echo "  docker pull ghcr.io/octacer/waha-plus:noweb"
        echo ""
        
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled. Please load the WAHA Plus image first."
            exit 1
        fi
        
        print_warning "Continuing without image verification..."
    else
        print_status "WAHA Plus image found!"
    fi
}

# Function to generate WAHA Docker Compose file
generate_waha_compose() {
    print_status "Generating Docker Compose file: $COMPOSE_FILE"
    
    local waha_domain=$(get_config "$SERVICE_KEY" "domain")
    local waha_username=$(get_config "$SERVICE_KEY" "username")
    local waha_password=$(get_config "$SERVICE_KEY" "password")
    
    cat > "$COMPOSE_FILE" << EOF
version: '3'

services:
  master_wahachat:
    image: ghcr.io/octacer/waha-plus:noweb
    container_name: $CONTAINER_NAME
    ports:
      - "5002:3000"
    environment:
      WHATSAPP_DEFAULT_ENGINE: "NOWEB"
      WAHA_BASE_URL: "https://$waha_domain"
      WHATSAPP_RESTART_ALL_SESSIONS: "True"
      
      # Dashboard Configuration
      WAHA_DASHBOARD_ENABLED: "True"
      WAHA_DASHBOARD_USERNAME: "$waha_username"
      WAHA_DASHBOARD_PASSWORD: "$waha_password"
      
      # Swagger Configuration
      WHATSAPP_SWAGGER_TITLE: "Octacer WhatsApp API"
      WHATSAPP_SWAGGER_DESCRIPTION: "Octacer WhatsApp API Documentation"
      WHATSAPP_SWAGGER_EXTERNAL_DOC_URL: "https://octacer.com"
      WHATSAPP_SWAGGER_JPG_EXAMPLE_URL: "https://octacer.com/assets/images/logo.svg"
      WHATSAPP_SWAGGER_USERNAME: "$waha_username"
      WHATSAPP_SWAGGER_PASSWORD: "$waha_password"
      
    volumes:
      - './.sessions:/app/sessions'
    networks:
      - app_network
    restart: unless-stopped

networks:
  app_network:
    driver: bridge
EOF
    
    print_status "Docker Compose file generated successfully"
}

# Function to setup WAHA directories
setup_waha_directories() {
    print_status "Setting up $SERVICE_NAME directories..."
    create_directory "./.sessions" "1000:1000"
}

# Function to install WAHA
install_waha() {
    print_header "Installing $SERVICE_NAME"
    
    # Check if already running
    if is_service_running "$CONTAINER_NAME"; then
        print_warning "$SERVICE_NAME is already running."
        print_status "Would you like to restart it with new configuration?"
        read -p "Restart $SERVICE_NAME? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_waha
        else
            print_status "$SERVICE_NAME installation cancelled."
            exit 0
        fi
    fi
    
    # Check for WAHA image
    check_waha_image
    
    # Collect configuration
    collect_waha_config
    
    # Setup directories
    setup_waha_directories
    
    # Generate compose file
    generate_waha_compose
    
    # Start the service
    print_status "Starting $SERVICE_NAME container..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    # Wait for service to be ready
    wait_for_service "$SERVICE_NAME" "$CONTAINER_NAME" 20
    
    # Configure domain with SSL
    local waha_domain=$(get_config "$SERVICE_KEY" "domain")
    configure_domain "$waha_domain" 5002 5002 https
    
    # Update status
    update_config "$SERVICE_KEY" "status" "running"
    
    # Show success message
    print_header "$SERVICE_NAME Installation Completed!"
    
    print_config "Access Details:"
    echo "  URL: https://$waha_domain"
    echo "  Dashboard Username: $(get_config "$SERVICE_KEY" "username")"
    echo "  Dashboard Password: [stored in configuration]"
    echo "  Swagger Username: $(get_config "$SERVICE_KEY" "username")"
    echo "  Swagger Password: [stored in configuration]"
    echo "  Port: 5002"
    echo ""
    echo "  Container: $CONTAINER_NAME"
    echo "  Status: $(get_config "$SERVICE_KEY" "status")"
    echo "  Engine: NOWEB (No browser required)"
    echo ""
    
    print_status "API Endpoints:"
    echo "  Dashboard: https://$waha_domain/dashboard"
    echo "  Swagger Docs: https://$waha_domain/docs"
    echo "  API Base: https://$waha_domain/api"
    echo ""
    
    print_status "Sessions Directory: ./.sessions"
    print_status "Configuration saved in: $(realpath "$CONFIG_FILE")"
    echo ""
    
    print_status "$SERVICE_NAME is ready for WhatsApp integration!"
    print_warning "Note: Create WhatsApp sessions through the dashboard before sending messages."
}

# Function to stop WAHA
stop_waha() {
    print_status "Stopping $SERVICE_NAME..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    update_config "$SERVICE_KEY" "status" "stopped"
    print_status "$SERVICE_NAME stopped successfully."
}

# Function to show WAHA status
show_waha_status() {
    show_service_status "$SERVICE_NAME" "$CONTAINER_NAME" "$SERVICE_KEY"
    
    if is_service_running "$CONTAINER_NAME"; then
        print_status "Service health check:"
        local waha_domain=$(get_config "$SERVICE_KEY" "domain")
        
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5002/api/sessions" | grep -q "200\|401"; then
            echo -e "  API Service: ${GREEN}Running${NC}"
        else
            echo -e "  API Service: ${RED}Not responding${NC}"
        fi
        
        # Check sessions directory
        if [[ -d "./.sessions" ]]; then
            local session_count=$(find ./.sessions -name "*.json" 2>/dev/null | wc -l)
            echo -e "  Sessions: ${GREEN}Available${NC} ($session_count saved sessions)"
        else
            echo -e "  Sessions: ${RED}Directory missing${NC}"
        fi
        
        # Check if any WhatsApp sessions are active
        if curl -s "http://localhost:5002/api/sessions" 2>/dev/null | grep -q "session"; then
            echo -e "  WhatsApp Sessions: ${GREEN}Active${NC}"
        else
            echo -e "  WhatsApp Sessions: ${YELLOW}None active${NC}"
        fi
    fi
}

# Function to show WAHA logs
show_waha_logs() {
    local lines=${1:-50}
    print_status "Showing last $lines lines of $SERVICE_NAME logs..."
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs --tail="$lines" -f
}

# Function to restart WAHA
restart_waha() {
    print_status "Restarting $SERVICE_NAME..."
    stop_waha
    sleep 2
    install_waha
}

# Function to backup WAHA sessions
backup_waha() {
    local backup_dir="./waha_backup_$(date +%Y%m%d_%H%M%S)"
    
    print_status "Creating WAHA backup in: $backup_dir"
    
    mkdir -p "$backup_dir"
    
    # Backup sessions
    if [[ -d "./.sessions" ]]; then
        print_status "Backing up WhatsApp sessions..."
        cp -r "./.sessions" "$backup_dir/"
    fi
    
    # Backup configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        print_status "Backing up configuration..."
        cp "$CONFIG_FILE" "$backup_dir/"
    fi
    
    # Backup compose file
    if [[ -f "$COMPOSE_FILE" ]]; then
        print_status "Backing up Docker Compose file..."
        cp "$COMPOSE_FILE" "$backup_dir/"
    fi
    
    print_status "Backup completed: $backup_dir"
}

# Function to load WAHA image
load_waha_image() {
    local image_file=${1:-"./waha-plus.tar"}
    
    if [[ ! -f "$image_file" ]]; then
        print_error "Image file not found: $image_file"
        print_status "Please provide the path to the WAHA Plus image file."
        exit 1
    fi
    
    print_status "Loading WAHA Plus image from: $image_file"
    docker load -i "$image_file"
    
    if [[ $? -eq 0 ]]; then
        print_status "WAHA Plus image loaded successfully!"
    else
        print_error "Failed to load WAHA Plus image."
        exit 1
    fi
}

# Function to show sessions
show_sessions() {
    if ! is_service_running "$CONTAINER_NAME"; then
        print_error "$SERVICE_NAME is not running."
        exit 1
    fi
    
    print_status "WhatsApp Sessions:"
    
    local response=$(curl -s "http://localhost:5002/api/sessions" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        print_warning "Could not retrieve sessions. Service may not be ready yet."
    fi
}

# Function to create a new WhatsApp session
create_session() {
    local session_name=${1:-"default"}
    
    if ! is_service_running "$CONTAINER_NAME"; then
        print_error "$SERVICE_NAME is not running."
        exit 1
    fi
    
    print_status "Creating WhatsApp session: $session_name"
    
    local waha_username=$(get_config "$SERVICE_KEY" "username")
    local waha_password=$(get_config "$SERVICE_KEY" "password")
    
    local response=$(curl -s -u "$waha_username:$waha_password" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$session_name\"}" \
        "http://localhost:5002/api/sessions" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        print_status "Session creation initiated. Check the dashboard for QR code."
    else
        print_error "Failed to create session. Check credentials and service status."
    fi
}

# Function to delete a WhatsApp session
delete_session() {
    local session_name=${1:-"default"}
    
    if ! is_service_running "$CONTAINER_NAME"; then
        print_error "$SERVICE_NAME is not running."
        exit 1
    fi
    
    print_status "Deleting WhatsApp session: $session_name"
    
    local waha_username=$(get_config "$SERVICE_KEY" "username")
    local waha_password=$(get_config "$SERVICE_KEY" "password")
    
    local response=$(curl -s -u "$waha_username:$waha_password" \
        -X DELETE \
        "http://localhost:5002/api/sessions/$session_name" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        print_status "Session '$session_name' deleted successfully."
    else
        print_error "Failed to delete session. Check session name and credentials."
    fi
}

# Function to get session QR code
get_qr_code() {
    local session_name=${1:-"default"}
    
    if ! is_service_running "$CONTAINER_NAME"; then
        print_error "$SERVICE_NAME is not running."
        exit 1
    fi
    
    print_status "Getting QR code for session: $session_name"
    
    local waha_username=$(get_config "$SERVICE_KEY" "username")
    local waha_password=$(get_config "$SERVICE_KEY" "password")
    
    local response=$(curl -s -u "$waha_username:$waha_password" \
        "http://localhost:5002/api/sessions/$session_name/auth/qr" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        print_warning "Could not retrieve QR code. Session may not exist or be ready."
    fi
}

# Function to test webhook
test_webhook() {
    local session_name=${1:-"default"}
    local webhook_url=${2:-""}
    
    if [[ -z "$webhook_url" ]]; then
        print_error "Please provide webhook URL"
        echo "Usage: $0 test-webhook [session_name] [webhook_url]"
        exit 1
    fi
    
    if ! is_service_running "$CONTAINER_NAME"; then
        print_error "$SERVICE_NAME is not running."
        exit 1
    fi
    
    print_status "Testing webhook for session: $session_name"
    print_status "Webhook URL: $webhook_url"
    
    local waha_username=$(get_config "$SERVICE_KEY" "username")
    local waha_password=$(get_config "$SERVICE_KEY" "password")
    
    local response=$(curl -s -u "$waha_username:$waha_password" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"url\": \"$webhook_url\"}" \
        "http://localhost:5002/api/sessions/$session_name/webhooks" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        print_status "Webhook configuration updated."
    else
        print_error "Failed to configure webhook."
    fi
}

# Function to check API health
check_api_health() {
    if ! is_service_running "$CONTAINER_NAME"; then
        print_error "$SERVICE_NAME is not running."
        exit 1
    fi
    
    print_status "Checking API health..."
    
    # Check basic API endpoint
    local health=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5002/api/sessions" 2>/dev/null)
    
    if [[ "$health" == "200" || "$health" == "401" ]]; then
        echo -e "  API Status: ${GREEN}Healthy${NC}"
    else
        echo -e "  API Status: ${RED}Unhealthy (HTTP $health)${NC}"
    fi
    
    # Check dashboard
    local dashboard=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5002/dashboard" 2>/dev/null)
    
    if [[ "$dashboard" == "200" || "$dashboard" == "401" ]]; then
        echo -e "  Dashboard: ${GREEN}Available${NC}"
    else
        echo -e "  Dashboard: ${RED}Unavailable (HTTP $dashboard)${NC}"
    fi
    
    # Check swagger docs
    local swagger=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5002/docs" 2>/dev/null)
    
    if [[ "$swagger" == "200" ]]; then
        echo -e "  Swagger Docs: ${GREEN}Available${NC}"
    else
        echo -e "  Swagger Docs: ${RED}Unavailable (HTTP $swagger)${NC}"
    fi
}

# Function to clean sessions
clean_sessions() {
    print_status "Cleaning up session files..."
    
    if [[ -d "./.sessions" ]]; then
        local session_count=$(find ./.sessions -name "*.json" 2>/dev/null | wc -l)
        print_status "Found $session_count session files"
        
        if [[ $session_count -gt 0 ]]; then
            read -p "Delete all session files? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f ./.sessions/*.json
                print_status "Session files cleaned up."
            else
                print_status "Session cleanup cancelled."
            fi
        else
            print_status "No session files to clean."
        fi
    else
        print_warning "Sessions directory not found."
    fi
}

# Function to show help
show_help() {
    echo "WAHA WhatsApp API Installation Script"
    echo ""
    echo "Usage: sudo $0 [action] [options]"
    echo ""
    echo "Actions:"
    echo "  install           - Install and configure WAHA (default)"
    echo "  stop              - Stop WAHA service"
    echo "  restart           - Restart WAHA service"
    echo "  status            - Show WAHA status (no sudo required)"
    echo "  logs              - Show WAHA logs (no sudo required)"
    echo "  backup            - Backup WAHA sessions and config"
    echo "  sessions          - Show active WhatsApp sessions (no sudo required)"
    echo "  load-image        - Load WAHA Plus image from tar file"
    echo "  health            - Check API health (no sudo required)"
    echo "  clean             - Clean up session files"
    echo "  help              - Show this help message"
    echo ""
    echo "Session Management:"
    echo "  create-session [name]           - Create new WhatsApp session"
    echo "  delete-session [name]           - Delete WhatsApp session"
    echo "  qr-code [name]                  - Get QR code for session"
    echo "  test-webhook [name] [url]       - Test webhook configuration"
    echo ""
    echo "Examples:"
    echo "  sudo $0                               # Install with interactive configuration"
    echo "  sudo $0 install                      # Install with interactive configuration"
    echo "  sudo $0 restart                      # Restart WAHA"
    echo "  $0 status                            # Show status"
    echo "  $0 logs 100                          # Show last 100 log lines"
    echo "  sudo $0 backup                       # Create backup"
    echo "  $0 sessions                          # Show WhatsApp sessions"
    echo "  sudo $0 load-image ./waha.tar        # Load image from file"
    echo "  $0 health                            # Check API health"
    echo "  sudo $0 clean                        # Clean session files"
    echo ""
    echo "Session Examples:"
    echo "  sudo $0 create-session main          # Create session named 'main'"
    echo "  sudo $0 delete-session main          # Delete session named 'main'"
    echo "  $0 qr-code main                      # Get QR code for 'main' session"
    echo "  sudo $0 test-webhook main https://...# Test webhook for 'main' session"
    echo ""
    echo "Features:"
    echo "  • Interactive configuration with confirmation"
    echo "  • HTTPS domain configuration"
    echo "  • NOWEB engine (no browser required)"
    echo "  • Dashboard and Swagger UI"
    echo "  • Session persistence"
    echo "  • Automatic session restart"
    echo "  • Session backup and restore"
    echo "  • Webhook support"
    echo "  • API health monitoring"
    echo ""
    echo "API Access:"
    echo "  • Dashboard: https://your-domain/dashboard"
    echo "  • Swagger Docs: https://your-domain/docs"
    echo "  • API Base: https://your-domain/api"
    echo "  • Sessions: https://your-domain/api/sessions"
    echo ""
    echo "Authentication:"
    echo "  • All API endpoints require basic authentication"
    echo "  • Use dashboard/swagger username and password"
    echo "  • Credentials are stored in configuration file"
    echo ""
    echo "Note: Ensure you have the WAHA Plus image available before installation."
    echo "You can load it with: sudo $0 load-image /path/to/waha-plus.tar"
}

# Main script logic
main() {
    local action=${1:-install}
    local option1=$2
    local option2=$3
    
    case $action in
        "install"|"")
            check_root
            check_prerequisites
            install_waha
            ;;
        "stop")
            check_root
            stop_waha
            ;;
        "restart")
            check_root
            check_prerequisites
            restart_waha
            ;;
        "status")
            show_waha_status
            ;;
        "logs")
            local lines=${option1:-50}
            show_waha_logs "$lines"
            ;;
        "backup")
            check_root
            backup_waha
            ;;
        "sessions")
            show_sessions
            ;;
        "load-image")
            check_root
            load_waha_image "$option1"
            ;;
        "health")
            check_api_health
            ;;
        "clean")
            check_root
            clean_sessions
            ;;
        "create-session")
            check_root
            create_session "$option1"
            ;;
        "delete-session")
            check_root
            delete_session "$option1"
            ;;
        "qr-code")
            get_qr_code "$option1"
            ;;
        "test-webhook")
            check_root
            test_webhook "$option1" "$option2"
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