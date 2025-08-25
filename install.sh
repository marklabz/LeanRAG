#!/bin/bash
# LeanRAG Installation Script
# This script automates the complete installation of LeanRAG with all dependencies
#
# Usage:
#   ./install.sh          # Uses Python 3.11 (default)
#   ./install.sh 3.12     # Uses Python 3.12
#   ./install.sh 3.10     # Uses Python 3.10
#
# Requirements:
#   - uv package manager (https://github.com/astral-sh/uv)
#   - Python 3.10+ available on system

set -e  # Exit on any error

echo "🚀 Starting LeanRAG Installation..."
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if we're in the LeanRAG directory
if [[ ! -f "pyproject.toml" ]] || [[ ! -f "requirements.txt" ]]; then
    print_error "Please run this script from the LeanRAG project root directory"
    exit 1
fi

print_status "Detected LeanRAG project directory ✓"

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    print_error "uv package manager is required but not installed."
    print_status "Please install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

print_success "uv package manager detected ✓"

# Allow user to specify Python version or use default
PYTHON_VERSION=${1:-"3.11"}
print_status "Using Python version: $PYTHON_VERSION"

# Step 1: Create virtual environment if it doesn't exist
if [[ ! -d "leanrag" ]]; then
    print_status "Creating Python virtual environment with Python $PYTHON_VERSION..."
    uv venv leanrag --python=$PYTHON_VERSION
    
    if [[ $? -eq 0 ]]; then
        print_success "Virtual environment 'leanrag' created with Python $PYTHON_VERSION ✓"
    else
        print_error "Failed to create virtual environment with Python $PYTHON_VERSION"
        print_status "Available Python versions on your system:"
        uv python list 2>/dev/null || echo "Run 'uv python list' to see available versions"
        print_status "You can specify a different version by running: ./install.sh 3.12"
        exit 1
    fi
else
    print_warning "Virtual environment 'leanrag' already exists, using existing one"
    # Check if existing environment has compatible Python version
    if [[ -f "leanrag/pyvenv.cfg" ]]; then
        existing_version=$(grep "version =" leanrag/pyvenv.cfg | cut -d'=' -f2 | tr -d ' ' | cut -d'.' -f1,2)
        print_status "Existing environment uses Python $existing_version"
    fi
fi

# Step 2: Activate virtual environment and upgrade pip
print_status "Activating virtual environment..."
source leanrag/bin/activate

# Step 3: Install core LeanRAG package
print_status "Installing core LeanRAG package..."
uv pip install -e .

if [[ $? -eq 0 ]]; then
    print_success "Core LeanRAG package installed successfully ✓"
else
    print_error "Failed to install core LeanRAG package"
    exit 1
fi

# Step 4: Install nano-graphrag (optional but recommended)
print_status "Installing nano-graphrag (GitHub dependency)..."
uv pip install -e ".[nano-graphrag]"

if [[ $? -eq 0 ]]; then
    print_success "nano-graphrag installed successfully ✓"
else
    print_warning "nano-graphrag installation failed (this is optional)"
    print_warning "You can try installing it separately later with: uv pip install -e '.[nano-graphrag]'"
fi

# Step 5: Install full optional dependencies
print_status "Installing additional ML/AI packages..."
uv pip install -e ".[full]"

if [[ $? -eq 0 ]]; then
    print_success "Full package suite installed successfully ✓"
else
    print_warning "Some optional packages failed to install (continuing...)"
fi

# Step 6: Install Google Cloud dependencies (optional)
print_status "Installing Google Cloud dependencies for Gemini models..."
uv pip install -e ".[google-cloud]"

if [[ $? -eq 0 ]]; then
    print_success "Google Cloud dependencies installed successfully ✓"
else
    print_warning "Google Cloud dependencies installation failed (this is optional)"
fi

# Step 7: Install development dependencies (optional)
read -p "Do you want to install development dependencies (pytest, black, etc.)? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Installing development dependencies..."
    uv pip install -e ".[dev]"
    
    if [[ $? -eq 0 ]]; then
        print_success "Development dependencies installed successfully ✓"
    else
        print_warning "Development dependencies installation failed"
    fi
fi

# Step 8: Verify installation
print_status "Verifying installation..."

# Test imports
python3 -c "
try:
    import leanrag
    print('✅ leanrag package imported successfully')
except ImportError as e:
    print(f'❌ Failed to import leanrag: {e}')
    exit(1)

try:
    import lightrag_hku
    print('✅ lightrag-hku imported successfully')
except ImportError as e:
    print(f'⚠️  lightrag-hku import failed: {e}')

try:
    import nano_graphrag
    print('✅ nano-graphrag imported successfully')
except ImportError as e:
    print(f'⚠️  nano-graphrag import failed: {e}')

print('✅ Core installation verification complete')
"

if [[ $? -eq 0 ]]; then
    print_success "Installation verification passed ✓"
else
    print_error "Installation verification failed"
    exit 1
fi

# Final status
echo ""
echo "🎉 LeanRAG Installation Complete!"
echo "================================="
print_success "Installation completed successfully!"
echo ""
echo "📝 Next Steps:"
echo "   1. Activate the environment: source leanrag/bin/activate"
echo "   2. Check installed packages: uv pip list"
echo "   3. Run your LeanRAG applications!"
echo ""
echo "💡 Usage Tips:"
echo "   • To use a different Python version, run: ./install.sh 3.12"
echo "   • To see available Python versions: uv python list"
echo "   • To reinstall, delete 'leanrag' folder and run script again"
echo ""
echo "⚠️  Note: You may see a harmless warning about google-cloud-aiplatform[all]"
echo "   This doesn't affect functionality and can be safely ignored."
echo ""
echo "📚 For usage examples, check the src/lightrag-hku/examples/ directory"
echo ""
print_status "Happy coding with LeanRAG! 🚀"
