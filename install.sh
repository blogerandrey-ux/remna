#!/bin/bash
# Remnawave Panel Installer - Bootstrap Script
# Скачивает актуальный код установщика с GitHub и запускает его
set -euo pipefail

INSTALLER_DIR="/opt/remna-installer"
REPO_URL="https://raw.githubusercontent.com/blogerandrey-ux/remna/main"

# 1. Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] Этот скрипт требует прав root.\033[0m"
    echo "Запустите: sudo bash <(curl -Ls https://raw.githubusercontent.com/blogerandrey-ux/remna/main/install.sh)"
    exit 1
fi

echo -e "\033[0;36m==> Remnawave Panel Installer v2.0\033[0m"
echo -e "\033[0;36m==> Подготовка установщика...\033[0m"

# Создаём структуру папок (только для кода установщика)
mkdir -p "$INSTALLER_DIR/lib"
cd "$INSTALLER_DIR"

# 2. Список файлов кода (качаем ВСЕГДА свежими, без кэша)
FILES=(
    "lib/colors.sh"
    "lib/logger.sh"
    "lib/language.sh"
    "lib/checks.sh"
    "lib/panel.sh"
    "lib/menu.sh"
    "main.sh"
)

# 3. Цикл скачивания с человеческой обработкой ошибок
for f in "${FILES[@]}"; do
    echo -e "\033[0;33m  [download]\033[0m $f"
    if ! curl -fsSL "$REPO_URL/$f" -o "$f"; then
        echo -e "\033[0;31m[ERROR] Не удалось скачать $f\033[0m"
        echo "Возможные причины:"
        echo "  - Отсутствует подключение к интернету"
        echo "  - GitHub недоступен или превышен лимит запросов"
        echo "  - Ошибка в пути к файлу в репозитории"
        exit 1
    fi
done

# 4. Проверка целостности: main.sh должен быть bash-скриптом
if ! head -1 main.sh | grep -q '^#!/bin/bash'; then
    echo -e "\033[0;31m[ERROR] main.sh повреждён или не является bash-скриптом.\033[0m"
    echo "GitHub мог вернуть HTML-страницу (например, 404) вместо кода."
    exit 1
fi

# Делаем все скачанные скрипты исполняемыми
chmod +x lib/*.sh main.sh

echo ""
echo -e "\033[0;36m==> Запуск интерактивного меню...\033[0m"
sleep 1

# Запускаем основной скрипт (exec заменяет текущий процесс,不留 хвостов)
exec bash main.sh
