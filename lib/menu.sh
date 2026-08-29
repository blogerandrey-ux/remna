#!/bin/bash

show_main_menu() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║       Remnawave Panel Installer v2.0        ${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${YELLOW}1)${NC} $(t 'install_panel')"
        echo -e "  ${YELLOW}2)${NC} $(t 'update_panel')"
        echo -e "  ${YELLOW}3)${NC} $(t 'uninstall_panel')"
        echo -e "  ${YELLOW}4)${NC} $(t 'view_logs')"
        echo -e "  ${YELLOW}5)${NC} $(t 'check_status')"
        echo -e "  ${YELLOW}6)${NC} $(t 'backup_db')"
        echo -e "  ${YELLOW}7)${NC} $(t 'show_login_info')"
        echo -e "  ${YELLOW}8)${NC} $(t 'reset_admin_password')"
        echo -e "  ${RED}0)${NC} $(t 'exit')"
        echo ""
        echo -e "${WHITE}$(t 'select_option'):${NC}"
        read -p "> " choice
        
        case $choice in
            1)
                install_panel
                echo ""
                read -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            2)
                update_panel
                echo ""
                read -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            3)
                uninstall_panel
                echo ""
                read -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            4)
                view_logs
                echo ""
                read -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            5)
                check_status
                echo ""
                read -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            6)
                backup_db
                echo ""
                read -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            7)
                show_login_info
                ;;
            8)
                reset_admin_password
                ;;
            0)
                echo "Goodbye! / До свидания!"
                exit 0
                ;;
            *)
                log_error "$(t 'invalid_option')"
                sleep 2
                ;;
        esac
    done
}

update_panel() {
    log_step "Updating Remnawave Panel..."
    
    cd "$PANEL_DIR"
    
    # Скачиваем новые версии файлов
    curl -sL -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
    
    # Перезапускаем контейнеры
    docker compose pull
    docker compose up -d
    
    log_success "Panel updated successfully / Панель обновлена"
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

uninstall_panel() {
    log_warn "This will remove Remnawave Panel and all data!"
    log_warn "Это удалит Remnawave Panel и все данные!"
    echo ""
    read -p "Are you sure? / Вы уверены? (y/n) " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled / Отменено"
        return 0
    fi
    
    cd "$PANEL_DIR"
    
    # Останавливаем контейнеры
    docker compose down
    
    # Удаляем папку
    cd /
    rm -rf "$PANEL_DIR"
    
    # Удаляем Caddy контейнер если есть
    docker rm -f caddy 2>/dev/null || true
    
    log_success "Panel uninstalled / Панель удалена"
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

view_logs() {
    log_step "Viewing logs..."
    
    if [ -d "$PANEL_DIR" ]; then
        cd "$PANEL_DIR"
        docker compose logs -f --tail=100
    else
        log_error "Panel not installed / Панель не установлена"
    fi
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

check_status() {
    log_step "Checking status..."
    
    if [ -d "$PANEL_DIR" ]; then
        cd "$PANEL_DIR"
        docker compose ps
    else
        log_error "Panel not installed / Панель не установлена"
    fi
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

backup_db() {
    log_step "Creating database backup..."
    
    if [ ! -d "$PANEL_DIR" ]; then
        log_error "Panel not installed / Панель не установлена"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    cd "$PANEL_DIR"
    
    # Создаём папку для бэкапов
    mkdir -p "$PANEL_DIR/backups"
    
    # Получаем имя контейнера с базой данных
    DB_CONTAINER=$(docker compose ps -q remnawave-db)
    
    if [ -z "$DB_CONTAINER" ]; then
        log_error "Database container not found / Контейнер базы данных не найден"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    # Создаём бэкап
    BACKUP_FILE="$PANEL_DIR/backups/backup_$(date +%Y%m%d_%H%M%S).sql"
    docker exec "$DB_CONTAINER" pg_dump -U postgres remnawave > "$BACKUP_FILE"
    
    if [ $? -eq 0 ]; then
        log_success "Backup created: $BACKUP_FILE"
    else
        log_error "Backup failed / Ошибка создания бэкапа"
    fi
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

show_login_info() {
    log_step "Информация о панели / Panel Information"
    
    if [ -f "/opt/remnawave/.domain" ]; then
        DOMAIN=$(cat /opt/remnawave/.domain)
        echo -e "${CYAN}URL панели / Panel URL:${NC} https://$DOMAIN"
    else
        echo -e "${YELLOW}Домен не найден. Возможно, панель не установлена.${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Логин и пароль / Login and password:${NC}"
    echo "В целях безопасности пароль хранится в зашифрованном виде (хэш) и не может быть отображён."
    echo "For security reasons, the password is stored as a hash and cannot be displayed."
    echo "Если вы забыли пароль, используйте опцию 8 для сброса и создания нового админа."
    echo "If you forgot the password, use option 8 to reset and create a new admin."
    echo ""
    read -p "Нажмите Enter для возврата в меню... / Press Enter to return to menu..."
}
reset_admin_password() {
    log_step "Сброс пароля администратора / Reset admin password"
    echo ""
    echo -e "${CYAN}Для сброса пароля выполните следующую команду:${NC}"
    echo ""
    echo -e "${YELLOW}docker exec -it remnawave cli${NC}"
    echo ""
    echo "Затем выберите опцию 'Reset superadmin' из меню."
    echo ""
    echo -e "${CYAN}После сброса:${NC}"
    LOCAL_DOMAIN=$(cat /opt/remnawave/.domain 2>/dev/null || echo 'your-domain.com')
    echo "1. Откройте панель: https://$LOCAL_DOMAIN"
    echo "2. Создайте нового супер-админа с новым паролем"
    echo ""
    read -p "Нажмите Enter для возврата в меню... / Press Enter to return to menu..."
}


export -f show_main_menu update_panel uninstall_panel view_logs check_status backup_db show_login_info reset_admin_password
