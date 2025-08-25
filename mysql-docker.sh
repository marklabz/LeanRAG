#!/bin/bash

# MySQL Docker Management Script for LeanRAG
# This script provides easy management of the MySQL container used by LeanRAG

set -e

CONTAINER_NAME="leangraph-mysql"
IMAGE_NAME="mysql:8.0"
CUSTOM_IMAGE_NAME="leangraph-mysql"
MYSQL_PORT="4321"
MYSQL_PASSWORD="123"
DATABASE_NAME="leanrag_default"
VOLUME_NAME="mysql_data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
}

container_exists() {
    docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

container_running() {
    docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

start_mysql() {
    check_docker
    
    if container_running; then
        print_warning "MySQL container is already running"
        return 0
    fi
    
    if container_exists; then
        print_status "Starting existing MySQL container..."
        docker start ${CONTAINER_NAME}
    else
        print_status "Creating and starting new MySQL container..."
        docker run -d \
            --name ${CONTAINER_NAME} \
            -e MYSQL_ROOT_PASSWORD=${MYSQL_PASSWORD} \
            -e MYSQL_DATABASE=${DATABASE_NAME} \
            -e MYSQL_CHARSET=utf8mb4 \
            -e MYSQL_COLLATION=utf8mb4_unicode_ci \
            -p ${MYSQL_PORT}:3306 \
            -v ${VOLUME_NAME}:/var/lib/mysql \
            -v "$(pwd)/mysql-init:/docker-entrypoint-initdb.d" \
            --restart unless-stopped \
            ${IMAGE_NAME} \
            --character-set-server=utf8mb4 \
            --collation-server=utf8mb4_unicode_ci \
            --default-authentication-plugin=mysql_native_password \
            --sql-mode=STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO
    fi
    
    print_status "Waiting for MySQL to be ready..."
    for i in {1..30}; do
        if docker exec ${CONTAINER_NAME} mysqladmin ping -h localhost -u root -p${MYSQL_PASSWORD} &>/dev/null; then
            print_success "MySQL is ready and accepting connections"
            print_status "Connection details:"
            echo "  Host: localhost"
            echo "  Port: ${MYSQL_PORT}"
            echo "  User: root"
            echo "  Password: ${MYSQL_PASSWORD}"
            echo "  Database: ${DATABASE_NAME}"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    
    print_error "MySQL failed to start within 30 seconds"
    docker logs ${CONTAINER_NAME} --tail 20
    exit 1
}

stop_mysql() {
    check_docker
    
    if ! container_running; then
        print_warning "MySQL container is not running"
        return 0
    fi
    
    print_status "Stopping MySQL container..."
    docker stop ${CONTAINER_NAME}
    print_success "MySQL container stopped"
}

restart_mysql() {
    stop_mysql
    start_mysql
}

status_mysql() {
    check_docker
    
    if container_running; then
        print_success "MySQL container is running"
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        # Test connection
        if docker exec ${CONTAINER_NAME} mysqladmin ping -h localhost -u root -p${MYSQL_PASSWORD} &>/dev/null; then
            print_success "Database is accepting connections"
        else
            print_warning "Database is not ready yet"
        fi
    elif container_exists; then
        print_warning "MySQL container exists but is not running"
        docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        print_error "MySQL container does not exist"
    fi
}

connect_mysql() {
    check_docker
    
    if ! container_running; then
        print_error "MySQL container is not running. Start it first with: $0 start"
        exit 1
    fi
    
    print_status "Connecting to MySQL shell..."
    docker exec -it ${CONTAINER_NAME} mysql -u root -p${MYSQL_PASSWORD} ${DATABASE_NAME}
}

logs_mysql() {
    check_docker
    
    if ! container_exists; then
        print_error "MySQL container does not exist"
        exit 1
    fi
    
    print_status "Showing MySQL container logs..."
    docker logs ${CONTAINER_NAME} -f
}

reset_mysql() {
    check_docker
    
    print_warning "This will delete ALL data in the MySQL database!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Reset cancelled"
        exit 0
    fi
    
    print_status "Stopping and removing MySQL container..."
    if container_exists; then
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME}
    fi
    
    print_status "Removing MySQL data volume..."
    docker volume rm ${VOLUME_NAME} 2>/dev/null || true
    
    print_success "MySQL reset complete. Use '$0 start' to create a fresh database"
}

build_custom() {
    check_docker
    
    print_status "Building custom MySQL image..."
    docker build -f Dockerfile.mysql -t ${CUSTOM_IMAGE_NAME} .
    print_success "Custom image built: ${CUSTOM_IMAGE_NAME}"
}

show_help() {
    echo "MySQL Docker Management Script for LeanRAG"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start     Start MySQL container"
    echo "  stop      Stop MySQL container"
    echo "  restart   Restart MySQL container"
    echo "  status    Show container status"
    echo "  connect   Connect to MySQL shell"
    echo "  logs      Show container logs"
    echo "  reset     Delete all data and reset container"
    echo "  build     Build custom MySQL image"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start          # Start MySQL"
    echo "  $0 status         # Check if running"
    echo "  $0 connect        # Open MySQL shell"
    echo "  $0 logs           # Watch logs"
    echo "  $0 reset          # Delete all data"
}

# Main command dispatcher
case "${1:-help}" in
    start)
        start_mysql
        ;;
    stop)
        stop_mysql
        ;;
    restart)
        restart_mysql
        ;;
    status)
        status_mysql
        ;;
    connect)
        connect_mysql
        ;;
    logs)
        logs_mysql
        ;;
    reset)
        reset_mysql
        ;;
    build)
        build_custom
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac