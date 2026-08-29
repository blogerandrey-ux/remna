#!/bin/bash

show_main_menu() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║       Remnawave Panel Installer v1.0        ${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${YELLOW}1)${NC} $(t 'install_panel')"
        echo -e "  ${YELLOW}2)${NC} $(t 'update_panel')"
        echo -e "  ${YELLOW}3)${NC} $(t 'uninstall_panel')"
        echo -e "  ${YELLOW}4)${NC} $(t 'view_logs')"
        echo -e "  ${YELLOW}5)${NC} $(t 'check_status')"
        echo -e "  ${YELLOW}6)${NC} $(t 'backup_db')"
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
    curl -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
    
    # Перезапускаем контейнеры
    docker compose pull
    docker compose up -d
    
    log_success "Panel updated successfully / Панель обновлена"
}

uninstall_panel() {
    log_warn "This will remove Remnawave Panel and all data!"
    log_warn "Это удалит Remnawave Panel и все данные!"
    echo ""
    read -p "Are you sure? / Вы уверены? (y/n) " confirm
    
    if [ "$confirm" != "y" ]; then
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
    docker rm -f caddy 2>/dev/null
    
    log_success "Panel uninstalled / Панель удалена"
}

view_logs() {
    log_step "Viewing logs..."
    
    cd "$PANEL_DIR"
    
    if [ -d "$PANEL_DIR" ]; then
        docker compose logs -f --tail=100
    else
        log_error "Panel not installed / Панель не установлена"
    fi
}

check_status() {
    log_step "Checking status..."
    
    if [ -d "$PANEL_DIR" ]; then
        cd "$PANEL_DIR"
        docker compose ps
    else
        log_error "Panel not installed / Панель не установлена"
    fi
}

backup_db() {
    log_step "Creating database backup..."
    
    cd "$PANEL_DIR"
    
    if [ ! -d "$PANEL_DIR" ]; then
        log_error "Panel not installed / Панель не установлена"
        return 1
    fi
    
    # Создаём папку для бэкапов
    mkdir -p "$PANEL_DIR/backups"
    
    # Получаем имя контейнера с базой данных
    DB_CONTAINER=$(docker compose ps -q remnawave-db)
    
    if [ -z "$DB_CONTAINER" ]; then
        log_error "Database container not found / Контейнер базы данных не найден"
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
}

export -f show_main_menu update_panel uninstall_panel view_logs check_status backup_db
