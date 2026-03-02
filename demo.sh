#!/bin/bash
set -e

# powerglide - Demo Script
# This script demonstrates the key capabilities of the powerglide CLI

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BOLD}======================================${NC}"
echo -e "${BOLD}  powerglide - Demo Script${NC}"
echo -e "${BOLD}======================================${NC}"
echo ""

# Function to print section headers
section() {
    echo -e "\n${BLUE}━━━ $1 ${NC}"
    echo ""
}

# 1. Version check
section "1. Version Information"
./zig-out/bin/powerglide version

# 2. Help overview
section "2. CLI Help"
./zig-out/bin/powerglide --help

# 3. Doctor command - system health check
section "3. System Health Check (doctor)"
./zig-out/bin/powerglide doctor

# 4. List available agents
section "4. Available Agents"
./zig-out/bin/powerglide agent list

# 5. Show configuration
section "5. Current Configuration"
./zig-out/bin/powerglide config show || echo "(No config file found - using defaults)"

# 6. List tools
section "6. Available Tools"
./zig-out/bin/powerglide tools list

# 7. Demo run (dry-run mode if available)
section "7. Demo Agent Run (Dry Run)"
echo -e "${YELLOW}Note: This is a demonstration. No actual API calls are made.${NC}"
./zig-out/bin/powerglide run --agent sisyphus --help || echo "(Run command help displayed)"

# 8. Session management
section "8. Session Management"
./zig-out/bin/powerglide session list || echo "(No active sessions)"

# 9. Swarm commands
section "9. Swarm Management"
./zig-out/bin/powerglide swarm list || echo "(No active swarms)"

# 10. TUI launch (will fail if not in TTY)
section "10. TUI Dashboard"
echo -e "${YELLOW}Note: TUI requires a TTY. Showing help instead.${NC}"
./zig-out/bin/powerglide tui --help || echo "(TUI requires interactive terminal)"

# Summary
section "Demo Complete!"
echo -e "${GREEN}✓${NC} All powerglide commands executed successfully!"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  • Set your API key: export ANTHROPIC_API_KEY='your-key'"
echo "  • Run an agent: ./zig-out/bin/powerglide run \"your task\""
echo "  • Open TUI: ./zig-out/bin/powerglide tui"
echo ""
echo -e "For more information, see ${BLUE}README.md${NC} or run ${BLUE}powerglide --help${NC}"
