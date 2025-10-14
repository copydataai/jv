#!/bin/bash

set -eo pipefail

# JV Installer
# Installs jv to /usr/local/bin

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="jv"

echo -e "${BLUE}JV Installer${NC}"
echo ""

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo -e "${YELLOW}Warning:${NC} Java is not installed"
    echo "Please install Java (JDK) to use jv"
    echo ""
    echo "macOS: brew install openjdk"
    echo "Ubuntu/Debian: sudo apt install default-jdk"
    echo ""
fi

# Check if we need sudo
if [[ ! -w "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}→${NC} Installation requires sudo access"
    SUDO="sudo"
else
    SUDO=""
fi

# Copy script
echo -e "${BLUE}→${NC} Installing jv to $INSTALL_DIR..."

if [[ ! -f "jv.sh" ]]; then
    echo -e "${RED}Error:${NC} jv.sh not found in current directory"
    exit 1
fi

$SUDO cp jv.sh "$INSTALL_DIR/$SCRIPT_NAME"
$SUDO chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

echo -e "${GREEN}✓${NC} Installation complete!"
echo ""
echo "Try it out:"
echo "  jv help"
echo "  jv create my-first-project"
echo ""
echo -e "${BLUE}Learn more:${NC} https://github.com/copydataai/jv"
