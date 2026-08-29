#!/bin/bash

# ============================================================
# Remnawave Panel Installer - One Command Version
# Автоматически скачивает и запускает установщик
# ============================================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Remnawave Panel Installer v2.0           ${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Рабочая директория
INSTALLER_DIR="/opt/remna-installer"
REPO_URL="https://raw.githubusercontent.com/blogerandrey-ux/remna/main"

# Функция логирования
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}==>${NC} $1"; }

# Проверка root
if [ "$EUID" -ne 0 ]; then
    log_error "Пожалуйста, запустите от root (используйте 'sudo su')"
    exit 1
fi

# Проверка наличия curl
if ! command -v curl &> /dev/null; then
    log_step "Установка curl..."
    apt-get update -qq && apt-get install -y -qq curl > /dev/null 2>&1
fi

# Создание рабочей директории
log_step "Подготовка установщика..."
mkdir -p "$INSTALLER_DIR"
cd "$INSTALLER_DIR"

# Скачивание файлов (с проверкой существования)
log_info "Загрузка файлов установщика..."

FILES=(
    "lib/colors.sh"
    "lib/logger.sh"
    "lib/language.sh"
    "lib/checks.sh"
    "lib/panel.sh"
    "lib/menu.sh"
    "templates/docker-compose-panel.yml"
    "templates/caddy.conf"
    "templates/nginx.conf"
)

for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        mkdir -p "$(dirname "$file")"
        curl -sL "$REPO_URL/$file" -o "$file"
    fi
done

# Всегда скачиваем главный скрипт (обновлённую версию)
curl -sL "$REPO_URL/install.sh" -o "install_main.sh"

# Проверка целостности
if [ ! -f "lib/colors.sh" ] || [ ! -f "lib/menu.sh" ]; then
    log_error "Не удалось загрузить файлы установщика"
    log_error "Проверьте подключение к интернету и доступность GitHub"
    exit 1
fi

# Делаем скрипты исполняемыми
chmod +x lib/*.sh install_main.sh

log_success "Установщик готов!"
echo ""

# Запуск основного установщика
log_info "Запуск интерактивного меню..."
echo ""
sleep 1

# Запускаем обновлённый install_main.sh, который теперь имеет все файлы
exec bash install_main.sh
