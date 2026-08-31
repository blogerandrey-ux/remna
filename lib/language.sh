#!/bin/bash

# Язык по умолчанию
LANG_CODE="en"

detect_language() {
    echo ""
    echo -e "${CYAN}Select language / Выберите язык:${NC}"
    echo "  1) English"
    echo "  2) Русский"
    echo ""
    read -r -p "> " lang_choice
    
    if [ "$lang_choice" = "2" ]; then
        LANG_CODE="ru"
    else
        LANG_CODE="en"
    fi
    export LANG_CODE
}

# Функция перевода
t() {
    local key="$1"
    
    if [ "$LANG_CODE" = "ru" ]; then
        case "$key" in
            "welcome") echo "Добро пожаловать в установщик Remnawave!" ;;
            "install_panel") echo "Установить Remnawave Panel" ;;
            "update_panel") echo "Обновить Remnawave Panel" ;;
            "uninstall_panel") echo "Удалить Remnawave Panel" ;;
            "install_node") echo "Установить Remnawave Node" ;;
            "update_node") echo "Обновить Remnawave Node" ;;
            "uninstall_node") echo "Удалить Remnawave Node" ;;
            "view_logs") echo "Просмотреть логи Панели" ;;
            "view_node_logs") echo "Просмотреть логи Ноды" ;;
            "check_status") echo "Проверить статус Панели" ;;
            "backup_db") echo "Создать резервную копию БД" ;;
            "show_login_info") echo "Показать данные для входа" ;;
            "reset_admin_password") echo "Сбросить пароль админа" ;;
            "get_node_secret") echo "Как получить Secret Key для Ноды" ;;
            "configure_gate_password") echo "Настроить пароль-заглушку" ;;
            "enter_gate_password") echo "Ввести свой пароль для доступа" ;;
            "use_auto_password") echo "Использовать автоматически сгенерированный пароль" ;;
            "skip_gate_password") echo "Пропустить защиту (панель будет доступна без пароля)" ;;
            "gate_password_set") echo "Пароль-заглушка успешно установлен" ;;
            "gate_password_skipped") echo "Защита паролем пропущена" ;;
            "gate_service_started") echo "Сервис проверки пароля запущен" ;;
            "error_python3_missing") echo "Python 3 не найден. Установите его (apt install python3) для работы защиты." ;;
            "exit") echo "Выход" ;;
            "select_option") echo "Выберите опцию" ;;
            "invalid_option") echo "Неверная опция, попробуйте снова" ;;
            "installing_docker") echo "Установка Docker..." ;;
            "docker_installed") echo "Docker уже установлен" ;;
            "enter_domain") echo "Введите домен для панели (например: panel.example.com)" ;;
            "installing_panel") echo "Установка Remnawave Panel..." ;;
            "panel_installed") echo "Remnawave Panel успешно установлена!" ;;
            "installing_node") echo "Установка Remnawave Node..." ;;
            "node_installed") echo "Remnawave Node успешно установлена!" ;;
            "node_not_installed") echo "Нода не установлена" ;;
            "updating_node") echo "Обновление Remnawave Node..." ;;
            "uninstalling_node") echo "Удаление Remnawave Node..." ;;
            "enter_panel_url") echo "Введите URL Панели (например: https://panel.example.com)" ;;
            "enter_node_token") echo "Введите Node Token (Secret Key) из Панели" ;;
            "error_empty_token") echo "Ошибка: Token не может быть пустым" ;;
            "enter_node_name") echo "Введите имя Ноды (например: node-1)" ;;
            "enter_node_port") echo "Введите порт Ноды" ;;
            "checking_panel_availability") echo "Проверка доступности Панели..." ;;
            "panel_unreachable") echo "Ошибка: Панель недоступна по указанному URL" ;;
            "select_proxy") echo "Выберите Reverse Proxy:" ;;
            "caddy") echo "Caddy (проще, авто-SSL)" ;;
            "nginx") echo "Nginx (классика, больше контроля)" ;;
            "enter_email") echo "Введите email для SSL сертификата:" ;;
            "downloading_files") echo "Загрузка файлов конфигурации..." ;;
            "generating_secrets") echo "Генерация секретных ключей..." ;;
            "starting_containers") echo "Запуск контейнеров..." ;;
            "error_domain") echo "Ошибка: введён некорректный домен" ;;
            "error_docker") echo "Ошибка при установке Docker" ;;
            "error_docker_compose") echo "Ошибка при выполнении docker compose" ;;
            "error_node_start") echo "Ошибка: контейнер Ноды не запустился. Проверьте логи выше." ;;
            "success_installation") echo "✅ Установка завершена успешно!" ;;
            "panel_url") echo "Панель доступна по адресу:" ;;
            "secret_key_instruction") echo -e "1. Откройте Панель\n2. Перейдите в 'Ноды' -> 'Управление'\n3. Нажмите '+' чтобы добавить новую ноду\n4. Скопируйте 'Secret Key' из сгенерированной конфигурации" ;;
            *) echo "$key" ;;
        esac
    else
        case "$key" in
            "welcome") echo "Welcome to Remnawave Installer!" ;;
            "install_panel") echo "Install Remnawave Panel" ;;
            "update_panel") echo "Update Remnawave Panel" ;;
            "uninstall_panel") echo "Uninstall Remnawave Panel" ;;
            "install_node") echo "Install Remnawave Node" ;;
            "update_node") echo "Update Remnawave Node" ;;
            "uninstall_node") echo "Uninstall Remnawave Node" ;;
            "view_logs") echo "View Panel logs" ;;
            "view_node_logs") echo "View Node logs" ;;
            "check_status") echo "Check Panel status" ;;
            "backup_db") echo "Backup database" ;;
            "show_login_info") echo "Show login credentials" ;;
            "reset_admin_password") echo "Reset admin password" ;;
            "get_node_secret") echo "How to get Secret Key for Node" ;;
            "configure_gate_password") echo "Configure gate password" ;;
            "enter_gate_password") echo "Enter custom password for access" ;;
            "use_auto_password") echo "Use automatically generated password" ;;
            "skip_gate_password") echo "Skip protection (panel will be accessible without password)" ;;
            "gate_password_set") echo "Gate password successfully set" ;;
            "gate_password_skipped") echo "Password protection skipped" ;;
            "gate_service_started") echo "Password verification service started" ;;
            "error_python3_missing") echo "Python 3 not found. Please install it for Gate protection." ;;
            "exit") echo "Exit" ;;
            "select_option") echo "Select option" ;;
            "invalid_option") echo "Invalid option, try again" ;;
            "installing_docker") echo "Installing Docker..." ;;
            "docker_installed") echo "Docker is already installed" ;;
            "enter_domain") echo "Enter domain for panel (e.g.: panel.example.com)" ;;
            "installing_panel") echo "Installing Remnawave Panel..." ;;
            "panel_installed") echo "Remnawave Panel installed successfully!" ;;
            "installing_node") echo "Installing Remnawave Node..." ;;
            "node_installed") echo "Remnawave Node installed successfully!" ;;
            "node_not_installed") echo "Node is not installed" ;;
            "updating_node") echo "Updating Remnawave Node..." ;;
            "uninstalling_node") echo "Uninstalling Remnawave Node..." ;;
            "enter_panel_url") echo "Enter Panel URL (e.g., https://panel.example.com)" ;;
            "enter_node_token") echo "Enter Node Token (Secret Key) from Panel" ;;
            "error_empty_token") echo "Error: Token cannot be empty" ;;
            "enter_node_name") echo "Enter Node name (e.g., node-1)" ;;
            "enter_node_port") echo "Enter Node port" ;;
            "checking_panel_availability") echo "Checking Panel availability..." ;;
            "panel_unreachable") echo "Error: Panel is unreachable at the specified URL" ;;
            "select_proxy") echo "Select Reverse Proxy:" ;;
            "caddy") echo "Caddy (easier, auto-SSL)" ;;
            "nginx") echo "Nginx (classic, more control)" ;;
            "enter_email") echo "Enter email for SSL certificate:" ;;
            "downloading_files") echo "Downloading configuration files..." ;;
            "generating_secrets") echo "Generating secret keys..." ;;
            "starting_containers") echo "Starting containers..." ;;
            "error_domain") echo "Error: invalid domain" ;;
            "error_docker") echo "Error installing Docker" ;;
            "error_docker_compose") echo "Error running docker compose" ;;
            "error_node_start") echo "Error: Node container failed to start. Check logs above." ;;
            "success_installation") echo "✅ Installation completed successfully!" ;;
            "panel_url") echo "Panel available at:" ;;
            "secret_key_instruction") echo -e "1. Open Panel\n2. Go to 'Nodes' -> 'Management'\n3. Click '+' to add a new node\n4. Copy 'Secret Key' from the generated configuration" ;;
            *) echo "$key" ;;
        esac
    fi
}

export -f t detect_language
export LANG_CODE
