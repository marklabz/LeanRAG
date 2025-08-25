#!/bin/bash

# MySQL Docker Management Script for LeanRAG
# This script provides easy management of the MySQL container for LeanRAG

CONTAINER_NAME="leangraph-mysql"
IMAGE_NAME="leangraph-mysql"
VOLUME_NAME="mysql_data"
MYSQL_PORT="4321"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}[MYSQL-DOCKER]${NC} $1"
}

# Function to check if Docker is running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
}

# Function to start MySQL container
start_mysql() {
    print_header "Starting MySQL container for LeanRAG..."
    
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        # Container exists, check if it's running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            print_warning "MySQL container is already running"
            return 0
        else
            print_status "Starting existing MySQL container..."
            docker start ${CONTAINER_NAME}
        fi
    else
        # Container doesn't exist, create and start it
        print_status "Creating and starting new MySQL container..."
        docker run -d \
            --name ${CONTAINER_NAME} \
            -e MYSQL_ROOT_PASSWORD=123 \
            -e MYSQL_DATABASE=leanrag_default \
            -p ${MYSQL_PORT}:3306 \
            -v ${VOLUME_NAME}:/var/lib/mysql \
            -v $(pwd)/mysql-init:/docker-entrypoint-initdb.d \
            mysql:8.0 \
            --character-set-server=utf8mb4 \
            --collation-server=utf8mb4_unicode_ci \
            --default-authentication-plugin=mysql_native_password \
            --sql-mode=STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO
    fi
    
    # Wait for MySQL to be ready
    print_status "Waiting for MySQL to be ready..."
    for i in {1..30}; do
        if docker exec ${CONTAINER_NAME} mysqladmin ping -h localhost -u root -p123 --silent; then
            print_status "MySQL is ready!"
            break
        fi
        echo -n "."
        sleep 2
    done
    echo
}

# Function to stop MySQL container
stop_mysql() {
    print_header "Stopping MySQL container..."
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop ${CONTAINER_NAME}
        print_status "MySQL container stopped"
    else
        print_warning "MySQL container is not running"
    fi
}

# Function to restart MySQL container
restart_mysql() {
    print_header "Restarting MySQL container..."
    stop_mysql
    start_mysql
}

# Function to show MySQL container status
show_status() {
    print_header "MySQL Container Status"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container Status:"
        docker ps -a --filter name=${CONTAINER_NAME} --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo
        
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "MySQL Connection Details:"
            echo "  Host: localhost"
            echo "  Port: ${MYSQL_PORT}"
            echo "  User: root"
            echo "  Password: 123"
            echo "  Database: leanrag_default"
        fi
    else
        print_warning "MySQL container does not exist"
    fi
}

# Function to connect to MySQL shell
connect_mysql() {
    print_header "Connecting to MySQL shell..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_error "MySQL container is not running. Start it first with: $0 start"
        exit 1
    fi
    
    print_status "Opening MySQL shell (use Ctrl+D or 'exit' to quit)..."
    docker exec -it ${CONTAINER_NAME} mysql -u root -p123 leanrag_default
}

# Function to show MySQL logs
show_logs() {
    print_header "MySQL Container Logs"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker logs ${CONTAINER_NAME} --tail 50 -f
    else
        print_warning "MySQL container does not exist"
    fi
}

# Function to reset (delete everything and start fresh)
reset_mysql() {
    print_header "Resetting MySQL (this will delete all data!)"
    read -p "Are you sure you want to delete all MySQL data? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        print_status "Stopping and removing container..."
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
        
        print_status "Removing volume..."
        docker volume rm ${VOLUME_NAME} 2>/dev/null || true
        
        print_status "Starting fresh MySQL container..."
        start_mysql
    else
        print_warning "Reset cancelled"
    fi
}

# Function to build custom MySQL image
build_image() {
    print_header "Building custom MySQL image..."
    
    if [ ! -f "Dockerfile.mysql" ]; then
        print_error "Dockerfile.mysql not found in current directory"
        exit 1
    fi
    
    docker build -f Dockerfile.mysql -t ${IMAGE_NAME} .
    print_status "Custom MySQL image built successfully"
}

# Function to show help
show_help() {
    echo "MySQL Docker Management Script for LeanRAG"
    echo ""
    echo "Usage: $0 {start|stop|restart|status|connect|logs|reset|build|help}"
    echo ""
    echo "Commands:"
    echo "  start    - Start MySQL container"
    echo "  stop     - Stop MySQL container"
    echo "  restart  - Restart MySQL container"
    echo "  status   - Show container status and connection details"
    echo "  connect  - Connect to MySQL shell"
    echo "  logs     - Show MySQL container logs"
    echo "  reset    - Stop container and delete all data (fresh start)"
    echo "  build    - Build custom MySQL image from Dockerfile.mysql"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start     # Start MySQL"
    echo "  $0 connect   # Connect to MySQL shell"
    echo "  $0 status    # Check if MySQL is running"
}

# Main script logic
check_docker

case "$1" in
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
        show_status
        ;;
    connect)
        connect_mysql
        ;;
    logs)
        show_logs
        ;;
    reset)
        reset_mysql
        ;;
    build)
        build_image
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