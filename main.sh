#!/bin/bash
set -e

# Определяем путь к скрипту
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALLER_DIR

# Подключаем библиотеки
source "$INSTALLER_DIR/lib/colors.sh"
source "$INSTALLER_DIR/lib/logger.sh"
source "$INSTALLER_DIR/lib/language.sh"
source "$INSTALLER_DIR/lib/checks.sh"
source "$INSTALLER_DIR/lib/panel.sh"
source "$INSTALLER_DIR/lib/menu.sh"

# Приветствие
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Remnawave Panel Installer v1.0        ${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Проверки
check_root
detect_language
check_os

log_info "$(t 'welcome')"

# Запуск меню
show_main_menu
