#!/bin/bash
# Remnawave Panel Installer - Bootstrap Script
set -euo pipefail

INSTALLER_DIR="/opt/remna-installer"
REPO_URL="https://raw.githubusercontent.com/blogerandrey-ux/remna/main"

# Проверка root
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] Этот скрипт требует прав root.\033[0m"
    echo "Запустите: sudo bash <(curl -Ls https://raw.githubusercontent.com/blogerandrey-ux/remna/main/install.sh)"
    exit 1
fi

echo -e "\033[0;36m==> Remnawave Panel Installer v2.0\033[0m"
echo -e "\033[0;36m==> Подготовка установщика...\033[0m"

mkdir -p "$INSTALLER_DIR/lib" "$INSTALLER_DIR/templates"
cd "$INSTALLER_DIR"

# 1. КОД — качаем ВСЕГДА свежим (без кэша)
echo -e "\033[0;33m  [download]\033[0m lib/colors.sh"
curl -fsSL "$REPO_URL/lib/colors.sh" -o lib/colors.sh

echo -e "\033[0;33m  [download]\033[0m lib/logger.sh"
curl -fsSL "$REPO_URL/lib/logger.sh" -o lib/logger.sh

echo -e "\033[0;33m  [download]\033[0m lib/language.sh"
curl -fsSL "$REPO_URL/lib/language.sh" -o lib/language.sh

echo -e "\033[0;33m  [download]\033[0m lib/checks.sh"
curl -fsSL "$REPO_URL/lib/checks.sh" -o lib/checks.sh

echo -e "\033[0;33m  [download]\033[0m lib/panel.sh"
curl -fsSL "$REPO_URL/lib/panel.sh" -o lib/panel.sh

echo -e "\033[0;33m  [download]\033[0m lib/menu.sh"
curl -fsSL "$REPO_URL/lib/menu.sh" -o lib/menu.sh

echo -e "\033[0;33m  [download]\033[0m main.sh"
curl -fsSL "$REPO_URL/main.sh" -o main.sh

# 2. ШАБЛОНЫ — качаем только если нет (кэшируем)
for template in docker-compose-panel.yml caddy.conf nginx.conf; do
    if [ ! -f "templates/$template" ]; then
        echo -e "\033[0;33m  [download]\033[0m templates/$template"
        curl -fsSL "$REPO_URL/templates/$template" -o "templates/$template"
    else
        echo -e "\033[0;32m  [cached]\033[0m templates/$template (сохранён конфиг)"
    fi
done

# Проверка целостности main.sh
if ! head -1 main.sh | grep -q '^#!/bin/bash'; then
    echo -e "\033[0;31m[ERROR] main.sh повреждён или не является bash-скриптом.\033[0m"
    echo "GitHub вернул unexpected content. Попробуйте позже."
    exit 1
fi

chmod +x lib/*.sh main.sh

echo ""
echo -e "\033[0;36m==> Запуск интерактивного меню...\033[0m"
sleep 1

exec bash main.sh
