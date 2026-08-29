#!/bin/bash

# Язык по умолчанию
LANG_CODE="en"

detect_language() {
    echo ""
    echo -e "${CYAN}Select language / Выберите язык:${NC}"
    echo "  1) English"
    echo "  2) Русский"
    echo ""
    read -p "> " lang_choice
    
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
            "welcome") echo "Добро пожаловать в установщик Remnawave Panel!" ;;
            "install_panel") echo "Установить Remnawave Panel" ;;
            "update_panel") echo "Обновить Remnawave Panel" ;;
            "uninstall_panel") echo "Удалить Remnawave Panel" ;;
            "install_node") echo "Установить Remnawave Node" ;;
            "update_node") echo "Обновить Remnawave Node" ;;
            "uninstall_node") echo "Удалить Remnawave Node" ;;
            "view_logs") echo "Просмотреть логи" ;;
            "check_status") echo "Проверить статус" ;;
            "backup_db") echo "Создать резервную копию БД" ;;
            "show_login_info") echo "Показать данные для входа" ;;
            "reset_admin_password") echo "Сбросить пароль админа" ;;
            "exit") echo "Выход" ;;
            "select_option") echo "Выберите опцию" ;;
            "invalid_option") echo "Неверная опция, попробуйте снова" ;;
            "installing_docker") echo "Установка Docker..." ;;
            "docker_installed") echo "Docker уже установлен" ;;
            "enter_domain") echo "Введите домен для панели (например: panel.example.com)" ;;
            "installing_panel") echo "Установка Remnawave Panel..." ;;
            "panel_installed") echo "Remnawave Panel успешно установлена!" ;;
            "select_proxy") echo "Выберите Reverse Proxy:" ;;
            "caddy") echo "Caddy (проще, авто-SSL)" ;;
            "nginx") echo "Nginx (классика, больше контроля)" ;;
            "enter_email") echo "Введите email для SSL сертификата:" ;;
            "downloading_files") echo "Загрузка файлов конфигурации..." ;;
            "generating_secrets") echo "Генерация секретных ключей..." ;;
            "starting_containers") echo "Запуск контейнеров..." ;;
            "error_domain") echo "Ошибка: введён некорректный домен" ;;
            "error_docker") echo "Ошибка при установке Docker" ;;
            "success_installation") echo "✅ Установка завершена успешно!" ;;
            "panel_url") echo "Панель доступна по адресу:" ;;
            *) echo "$key" ;;
        esac
    else
        case "$key" in
            "welcome") echo "Welcome to Remnawave Panel Installer!" ;;
            "install_panel") echo "Install Remnawave Panel" ;;
            "update_panel") echo "Update Remnawave Panel" ;;
            "uninstall_panel") echo "Uninstall Remnawave Panel" ;;
            "install_node") echo "Install Remnawave Node" ;;
            "update_node") echo "Update Remnawave Node" ;;
            "uninstall_node") echo "Uninstall Remnawave Node" ;;
            "view_logs") echo "View logs" ;;
            "check_status") echo "Check status" ;;
            "backup_db") echo "Backup database" ;;
            "show_login_info") echo "Show login credentials" ;;
            "reset_admin_password") echo "Reset admin password" ;;
            "exit") echo "Exit" ;;
            "select_option") echo "Select option" ;;
            "invalid_option") echo "Invalid option, try again" ;;
            "installing_docker") echo "Installing Docker..." ;;
            "docker_installed") echo "Docker is already installed" ;;
            "enter_domain") echo "Enter domain for panel (e.g.: panel.example.com)" ;;
            "installing_panel") echo "Installing Remnawave Panel..." ;;
            "panel_installed") echo "Remnawave Panel installed successfully!" ;;
            "select_proxy") echo "Select Reverse Proxy:" ;;
            "caddy") echo "Caddy (easier, auto-SSL)" ;;
            "nginx") echo "Nginx (classic, more control)" ;;
            "enter_email") echo "Enter email for SSL certificate:" ;;
            "downloading_files") echo "Downloading configuration files..." ;;
            "generating_secrets") echo "Generating secret keys..." ;;
            "starting_containers") echo "Starting containers..." ;;
            "error_domain") echo "Error: invalid domain" ;;
            "error_docker") echo "Error installing Docker" ;;
            "success_installation") echo "✅ Installation completed successfully!" ;;
            "panel_url") echo "Panel available at:" ;;
            *) echo "$key" ;;
        esac
    fi
}

export -f t detect_language
export LANG_CODE
