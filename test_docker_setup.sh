#!/bin/bash

# Test script to verify LeanRAG Docker MySQL setup
# This script demonstrates the complete Docker integration

echo "🧪 Testing LeanRAG Docker MySQL Setup"
echo "======================================="

# Test 1: Check required files exist
echo "📋 Test 1: Checking required files..."
required_files=(
    "docker-compose.yml"
    "Dockerfile.mysql"
    "mysql-docker.sh"
    "mysql-init/01-init.sql"
    "MYSQL_DOCKER_README.md"
    "database_utils.py"
    "pyproject.toml"
)

all_files_exist=true
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (missing)"
        all_files_exist=false
    fi
done

if $all_files_exist; then
    echo "  ✅ All required files present"
else
    echo "  ❌ Some files are missing"
    exit 1
fi

# Test 2: Validate Docker configurations
echo ""
echo "🐳 Test 2: Validating Docker configurations..."

# Check docker-compose.yml
if docker compose config --quiet 2>/dev/null; then
    echo "  ✓ docker-compose.yml is valid"
else
    echo "  ✗ docker-compose.yml has issues"
    exit 1
fi

# Check mysql-docker.sh is executable
if [[ -x "mysql-docker.sh" ]]; then
    echo "  ✓ mysql-docker.sh is executable"
else
    echo "  ✗ mysql-docker.sh is not executable"
    exit 1
fi

# Test 3: Validate Python syntax
echo ""
echo "🐍 Test 3: Validating Python code..."

if python -m py_compile database_utils.py 2>/dev/null; then
    echo "  ✓ database_utils.py syntax is valid"
else
    echo "  ✗ database_utils.py has syntax errors"
    exit 1
fi

if python -c "import tomllib; tomllib.load(open('pyproject.toml', 'rb'))" 2>/dev/null; then
    echo "  ✓ pyproject.toml is valid"
else
    echo "  ✗ pyproject.toml has issues"
    exit 1
fi

# Test 4: Check MySQL initialization script
echo ""
echo "🗄️  Test 4: Validating MySQL initialization..."

if [[ -s "mysql-init/01-init.sql" ]]; then
    echo "  ✓ MySQL initialization script exists and is not empty"
    # Basic SQL syntax check (look for key SQL keywords)
    if grep -q "CREATE DATABASE" mysql-init/01-init.sql && grep -q "GRANT" mysql-init/01-init.sql; then
        echo "  ✓ MySQL initialization script contains expected SQL commands"
    else
        echo "  ⚠️  MySQL initialization script may be incomplete"
    fi
else
    echo "  ✗ MySQL initialization script is missing or empty"
    exit 1
fi

# Test 5: Check CommonKG configuration and logging
echo ""
echo "📊 Test 5: Validating CommonKG setup..."

# Check config files
config_files=(
    "CommonKG/config/create_kg_conf_example.yaml"
    "CommonKG/config/create_kg_conf_test.yaml"
    "CommonKG/config/create_kg_conf_test_small.yaml"
    "CommonKG/config/test_entities_small.txt"
)

for config in "${config_files[@]}"; do
    if [[ -f "$config" ]]; then
        echo "  ✓ $config"
    else
        echo "  ✗ $config (missing)"
    fi
done

# Check logging directory structure
if [[ -d "CommonKG/logs" ]]; then
    echo "  ✓ CommonKG/logs directory exists"
    if [[ -d "CommonKG/logs/create_kg" ]]; then
        echo "  ✓ CommonKG/logs/create_kg directory exists"
    else
        echo "  ⚠️  CommonKG/logs/create_kg directory missing"
    fi
else
    echo "  ✗ CommonKG/logs directory missing"
fi

# Test 6: Demonstrate Docker commands (without actually starting containers)
echo ""
echo "🚀 Test 6: Docker command demonstrations..."

echo "  Available mysql-docker.sh commands:"
./mysql-docker.sh help | grep -E "^  [a-z]" | sed 's/^/    /'

echo ""
echo "  Example usage:"
echo "    ./mysql-docker.sh start     # Start MySQL container"
echo "    ./mysql-docker.sh status    # Check container status"
echo "    ./mysql-docker.sh connect   # Connect to MySQL shell"
echo "    ./mysql-docker.sh stop      # Stop MySQL container"

# Test 7: Check that PyMySQL is properly configured
echo ""
echo "📦 Test 7: Validating dependencies..."

if grep -q "pymysql" pyproject.toml; then
    echo "  ✓ PyMySQL dependency is included in pyproject.toml"
else
    echo "  ✗ PyMySQL dependency missing from pyproject.toml"
fi

if grep -q "PyMySQL" requirements.txt; then
    echo "  ✓ PyMySQL dependency is included in requirements.txt"
else
    echo "  ⚠️  PyMySQL dependency missing from requirements.txt"
fi

echo ""
echo "🎉 All tests completed successfully!"
echo ""
echo "📋 Quick Start Guide:"
echo "1. Start MySQL:     ./mysql-docker.sh start"
echo "2. Check status:    ./mysql-docker.sh status"
echo "3. Run CommonKG:    python CommonKG/create_kg.py"
echo "4. Build graph:     python build_graph.py"
echo "5. Query graph:     python query_graph.py"
echo ""
echo "For more information, see MYSQL_DOCKER_README.md"