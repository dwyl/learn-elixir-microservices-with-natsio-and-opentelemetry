#!/bin/bash
# Production Deployment Script for Microservices System
# Usage: ./deploy.sh [command]
# Commands: setup, start, stop, restart, logs, status, update

set -e

COMPOSE_FILE="docker-compose-prod.yml"
ENV_FILE=".env.staging"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function check_env() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file $ENV_FILE not found!"
        log_info "Copy .env.production to .env.staging and configure it:"
        log_info "  cp .env.production .env.staging"
        log_info "  nano .env.staging"
        exit 1
    fi

    # Check for default passwords
    if grep -q "CHANGE_ME" "$ENV_FILE"; then
        log_error "Found default passwords in $ENV_FILE!"
        log_error "Please replace all 'CHANGE_ME' values with secure passwords."
        log_info "Generate secure passwords with: openssl rand -base64 32"
        exit 1
    fi

    log_info "Environment file validated ✓"
}

function check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed!"
        log_info "Install Docker: https://docs.docker.com/engine/install/"
        exit 1
    fi

    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose plugin is not installed!"
        log_info "Install Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi

    log_info "Docker and Docker Compose are installed ✓"
}

function setup() {
    log_info "Setting up production environment..."

    check_docker

    # Create .env.staging if it doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        log_info "Creating $ENV_FILE from template..."
        cp .env.production "$ENV_FILE"
        log_warn "Please edit $ENV_FILE and replace all CHANGE_ME values!"
        log_info "Generate secure passwords with: openssl rand -base64 32"
        exit 0
    fi

    check_env

    log_info "Setup complete! You can now run: ./deploy.sh start"
}

function build() {
    log_info "Building Docker images..."
    check_env
    docker compose -f "$COMPOSE_FILE" build
    log_info "Build complete ✓"
}

function start() {
    log_info "Starting all services..."
    check_env
    docker compose -f "$COMPOSE_FILE" up -d
    log_info "Services started ✓"
    log_info ""
    status
}

function stop() {
    log_info "Stopping all services..."
    docker compose -f "$COMPOSE_FILE" stop
    log_info "Services stopped ✓"
}

function restart() {
    log_info "Restarting all services..."
    docker compose -f "$COMPOSE_FILE" restart
    log_info "Services restarted ✓"
}

function down() {
    log_warn "This will stop and remove all containers (volumes will be preserved)"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose -f "$COMPOSE_FILE" down
        log_info "Containers removed ✓"
    else
        log_info "Cancelled"
    fi
}

function logs() {
    if [ -n "$2" ]; then
        # Show logs for specific service
        docker compose -f "$COMPOSE_FILE" logs -f "$2"
    else
        # Show logs for all services
        docker compose -f "$COMPOSE_FILE" logs -f
    fi
}

function status() {
    log_info "Service Status:"
    docker compose -f "$COMPOSE_FILE" ps

    echo ""
    log_info "Access URLs:"

    # Get host IP (or use localhost)
    HOST_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

    echo -e "  Livebook:   ${GREEN}http://${HOST_IP}:8080${NC}"
    echo -e "  Grafana:    ${GREEN}http://${HOST_IP}:3000${NC}"
    echo -e "  Jaeger:     ${GREEN}http://${HOST_IP}:16686${NC}"
    echo -e "  Prometheus: ${GREEN}http://${HOST_IP}:9090${NC}"
    echo -e "  MinIO:      ${GREEN}http://${HOST_IP}:9001${NC}"
}

function update() {
    log_info "Updating application..."

    # Pull latest code
    log_info "Pulling latest code from git..."
    git pull

    # Rebuild images
    build

    # Restart services
    log_info "Restarting services with new images..."
    docker compose -f "$COMPOSE_FILE" up -d

    log_info "Update complete ✓"
    status
}

function backup() {
    BACKUP_DIR="./backups"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)

    log_info "Creating backups..."

    # Backup MinIO data
    log_info "Backing up MinIO data..."
    docker run --rm \
        -v msvc_minio-data:/data \
        -v "$(pwd)/$BACKUP_DIR":/backup \
        alpine tar czf "/backup/minio-${TIMESTAMP}.tar.gz" /data

    # Backup Grafana data
    log_info "Backing up Grafana data..."
    docker run --rm \
        -v msvc_grafana-data:/data \
        -v "$(pwd)/$BACKUP_DIR":/backup \
        alpine tar czf "/backup/grafana-${TIMESTAMP}.tar.gz" /data

    # Backup NATS data
    log_info "Backing up NATS data..."
    docker run --rm \
        -v msvc_nats_data:/data \
        -v "$(pwd)/$BACKUP_DIR":/backup \
        alpine tar czf "/backup/nats-${TIMESTAMP}.tar.gz" /data

    log_info "Backups created in $BACKUP_DIR/ ✓"
    ls -lh "$BACKUP_DIR/"
}

function health() {
    log_info "Checking service health..."

    # Check if containers are running
    RUNNING=$(docker compose -f "$COMPOSE_FILE" ps | grep "Up" | wc -l)
    TOTAL=$(docker compose -f "$COMPOSE_FILE" ps | grep -v "NAME" | wc -l)

    echo -e "Containers running: ${GREEN}$RUNNING${NC} / $TOTAL"

    # Check individual service health
    echo ""
    log_info "Health checks:"

    services=("user_svc" "client_svc" "image_svc_1" "image_svc_2" "email_svc" "grafana" "jaeger" "prometheus" "minio")

    for service in "${services[@]}"; do
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "msvc-$service" 2>/dev/null || echo "no healthcheck")

        if [ "$health_status" = "healthy" ]; then
            echo -e "  $service: ${GREEN}✓ healthy${NC}"
        elif [ "$health_status" = "no healthcheck" ]; then
            # Check if container is running
            if docker ps | grep -q "msvc-$service"; then
                echo -e "  $service: ${YELLOW}⚠ running (no healthcheck)${NC}"
            else
                echo -e "  $service: ${RED}✗ not running${NC}"
            fi
        else
            echo -e "  $service: ${RED}✗ $health_status${NC}"
        fi
    done
}

function usage() {
    cat << EOF
Production Deployment Script for Microservices System

Usage: ./deploy.sh [command]

Commands:
    setup       Initial setup (create .env.staging from template)
    build       Build Docker images
    start       Start all services
    stop        Stop all services
    restart     Restart all services
    down        Stop and remove containers (preserves volumes)
    logs        Show logs (use 'logs <service>' for specific service)
    status      Show service status and access URLs
    update      Pull latest code, rebuild, and restart
    backup      Backup volumes (MinIO, Grafana, NATS)
    health      Check health of all services

Examples:
    ./deploy.sh setup         # First time setup
    ./deploy.sh start         # Start all services
    ./deploy.sh logs user_svc # Show logs for user_svc
    ./deploy.sh update        # Update to latest version
    ./deploy.sh backup        # Create backups

For more information, see DEPLOYMENT.md
EOF
}

# Main script logic
case "${1:-}" in
    setup)
        setup
        ;;
    build)
        build
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    down)
        down
        ;;
    logs)
        logs "$@"
        ;;
    status)
        status
        ;;
    update)
        update
        ;;
    backup)
        backup
        ;;
    health)
        health
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        echo ""
        usage
        exit 1
        ;;
esac
