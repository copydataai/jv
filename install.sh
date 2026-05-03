#!/bin/bash

set -eo pipefail

# JV Installer

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="${JV_INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_NAME="jv"
INSTALL_VERSION="${JV_INSTALL_VERSION:-latest}"
DOWNLOAD_URL="https://raw.githubusercontent.com/copydataai/jv/${INSTALL_VERSION}/jv.sh"

echo -e "${BLUE}JV Installer${NC}"
echo ""

if ! command -v java >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning:${NC} Java is not installed"
    echo "Please install Java (JDK) to use jv"
    echo ""
    echo "macOS: brew install openjdk"
    echo "Ubuntu/Debian: sudo apt install default-jdk"
    echo ""
fi

mkdir -p "$INSTALL_DIR"

echo -e "${BLUE}→${NC} Installing jv to $INSTALL_DIR..."

if [[ -f "jv.sh" ]]; then
    cp jv.sh "$INSTALL_DIR/$SCRIPT_NAME"
else
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}Error:${NC} jv.sh not found and curl is not installed"
        exit 1
    fi
    curl -fsSL "$DOWNLOAD_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
fi

chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

echo -e "${GREEN}✓${NC} Installation complete!"
echo ""
"$INSTALL_DIR/$SCRIPT_NAME" version || true

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        echo ""
        echo -e "${YELLOW}Warning:${NC} $INSTALL_DIR is not on PATH"
        echo "Add this to your shell profile:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        ;;
esac

echo ""
echo "Try it out:"
echo "  jv help"
echo "  jv create my-first-project"
echo ""
echo -e "${BLUE}Learn more:${NC} https://github.com/copydataai/jv"
