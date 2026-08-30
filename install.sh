#!/bin/bash
set -euo pipefail

INSTALLER_DIR="/opt/remna-installer"
REPO_URL="https://raw.githubusercontent.com/blogerandrey-ux/remna/main"

if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] Этот скрипт требует прав root.\033[0m"
    echo "Запустите: sudo bash <(curl -Ls https://raw.githubusercontent.com/blogerandrey-ux/remna/main/install.sh)"
    exit 1
fi

echo -e "\033[0;36m==> Remnawave Installer v2.1.0\033[0m"
echo -e "\033[0;36m==> Подготовка установщика...\033[0m"

mkdir -p "$INSTALLER_DIR/lib"
cd "$INSTALLER_DIR" || exit 1

FILES=(
    "lib/colors.sh"
    "lib/logger.sh"
    "lib/language.sh"
    "lib/checks.sh"
    "lib/panel.sh"
    "lib/node.sh"
    "lib/menu.sh"
    "main.sh"
)

for f in "${FILES[@]}"; do
    echo -e "\033[0;33m  [download]\033[0m $f"
    if ! curl -fsSL "$REPO_URL/$f" -o "$f"; then
        echo -e "\033[0;31m[ERROR] Не удалось скачать $f\033[0m"
        echo "Проверьте подключение к интернету или доступность GitHub."
        exit 1
    fi
done

if ! head -1 main.sh | grep -q '^#!/bin/bash'; then
    echo -e "\033[0;31m[ERROR] main.sh повреждён или не является bash-скриптом.\033[0m"
    exit 1
fi

chmod +x lib/*.sh main.sh

echo ""
echo -e "\033[0;36m==> Запуск интерактивного меню...\033[0m"
sleep 1

exec bash main.sh
