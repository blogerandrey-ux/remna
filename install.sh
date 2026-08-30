#!/bin/bash
# Remnawave Panel Installer - Bootstrap Script
# Скачивает установщик с GitHub и запускает его
set -euo pipefail

INSTALLER_DIR="/opt/remna-installer"
REPO_URL="https://raw.githubusercontent.com/blogerandrey-ux/remna/main"

# 1. Проверка root (замечание #2)
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] Этот скрипт требует прав root.\033[0m"
    echo "Запустите: sudo bash <(curl -Ls https://raw.githubusercontent.com/blogerandrey-ux/remna/main/install.sh)"
    exit 1
fi

echo -e "\033[0;36m==> Remnawave Panel Installer v2.0\033[0m"
echo -e "\033[0;36m==> Подготовка установщика...\033[0m"

# Создаём структуру папок
mkdir -p "$INSTALLER_DIR/lib" "$INSTALLER_DIR/templates"
cd "$INSTALLER_DIR"

# Список файлов для скачивания
declare -A FILES=(
    ["lib/colors.sh"]="lib/colors.sh"
    ["lib/logger.sh"]="lib/logger.sh"
    ["lib/language.sh"]="lib/language.sh"
    ["lib/checks.sh"]="lib/checks.sh"
    ["lib/panel.sh"]="lib/panel.sh"
    ["lib/menu.sh"]="lib/menu.sh"
    ["templates/docker-compose-panel.yml"]="templates/docker-compose-panel.yml"
    ["templates/caddy.conf"]="templates/caddy.conf"
    ["templates/nginx.conf"]="templates/nginx.conf"
    ["main.sh"]="main.sh"
)

# 2. Скачивание с флагом -f (замечание #1) и проверкой существующих файлов (замечание #4)
for src in "${!FILES[@]}"; do
    dest="${FILES[$src]}"
    
    # Скачиваем только если файла нет или он пустой (экономия времени при повторном запуске)
    if [ ! -s "$dest" ]; then
        echo -e "\033[0;33m  [download]\033[0m $src"
        if ! curl -fsSL "$REPO_URL/$src" -o "$dest"; then
            echo -e "\033[0;31m[ERROR] Не удалось скачать $src\033[0m"
            echo "Проверьте:"
            echo "  - Подключение к интернету"
            echo "  - Доступность репозитория: $REPO_URL/$src"
            exit 1
        fi
    else
        echo -e "\033[0;32m  [cached]\033[0m $dest (используем локальную версию)"
    fi
done

# 3. Проверка целостности — main.sh должен быть bash-скриптом
if ! head -1 main.sh | grep -q '^#!/bin/bash'; then
    echo -e "\033[0;31m[ERROR] main.sh повреждён или не является bash-скриптом.\033[0m"
    echo "Возможно, GitHub вернул HTML-страницу вместо файла."
    exit 1
fi

# Делаем всё исполняемым
chmod +x lib/*.sh main.sh

echo ""
echo -e "\033[0;36m==> Запуск интерактивного меню...\033[0m"
sleep 1

# Запускаем основной скрипт (exec заменяет текущий процесс — чисто и правильно)
exec bash main.sh
