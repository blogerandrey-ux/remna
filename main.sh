#!/bin/bash
set -euo pipefail # Усиливаем безопасность

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALLER_DIR

source "$INSTALLER_DIR/lib/colors.sh"
source "$INSTALLER_DIR/lib/logger.sh"
source "$INSTALLER_DIR/lib/language.sh"
source "$INSTALLER_DIR/lib/checks.sh"
source "$INSTALLER_DIR/lib/panel.sh"
source "$INSTALLER_DIR/lib/node.sh"
source "$INSTALLER_DIR/lib/menu.sh"

clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Remnawave Installer v2.1.0          ${NC}" # Синхронизировано
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

check_root
detect_language
check_os

log_info "$(t 'welcome')"

show_main_menu
