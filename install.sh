#!/bin/bash
set -e

INSTALLER_DIR="/opt/remna-installer"
REPO_URL="https://raw.githubusercontent.com/blogerandrey-ux/remna/main"

echo "==> Подготовка установщика..."
mkdir -p "$INSTALLER_DIR/lib" "$INSTALLER_DIR/templates"
cd "$INSTALLER_DIR"

# Скачиваем все библиотеки и шаблоны
curl -sL "$REPO_URL/lib/colors.sh" -o lib/colors.sh
curl -sL "$REPO_URL/lib/logger.sh" -o lib/logger.sh
curl -sL "$REPO_URL/lib/language.sh" -o lib/language.sh
curl -sL "$REPO_URL/lib/checks.sh" -o lib/checks.sh
curl -sL "$REPO_URL/lib/panel.sh" -o lib/panel.sh
curl -sL "$REPO_URL/lib/menu.sh" -o lib/menu.sh
curl -sL "$REPO_URL/templates/docker-compose-panel.yml" -o templates/docker-compose-panel.yml
curl -sL "$REPO_URL/templates/caddy.conf" -o templates/caddy.conf
curl -sL "$REPO_URL/templates/nginx.conf" -o templates/nginx.conf

# Скачиваем основной скрипт с меню
curl -sL "$REPO_URL/main.sh" -o main.sh

# Делаем всё исполняемым
chmod +x lib/*.sh main.sh

echo "==> Запуск интерактивного меню..."
echo ""
sleep 1

# Запускаем основной скрипт
exec bash main.sh
