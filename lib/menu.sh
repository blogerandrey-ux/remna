#!/bin/bash

show_main_menu() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║         Remnawave Installer v2.1.0          ${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}─── Panel ───${NC}"
        echo -e "  ${YELLOW}1)${NC} $(t 'install_panel')"
        echo -e "  ${YELLOW}2)${NC} $(t 'update_panel')"
        echo -e "  ${YELLOW}3)${NC} $(t 'uninstall_panel')"
        echo -e "  ${YELLOW}4)${NC} $(t 'view_logs')"
        echo -e "  ${YELLOW}5)${NC} $(t 'check_status')"
        echo -e "  ${YELLOW}6)${NC} $(t 'backup_db')"
        echo -e "  ${YELLOW}7)${NC} $(t 'show_login_info')"
        echo -e "  ${YELLOW}8)${NC} $(t 'reset_admin_password')"
        echo ""
        echo -e "  ${CYAN}─── Node ───${NC}"
        echo -e "  ${YELLOW}9)${NC} $(t 'install_node')"
        echo -e "  ${YELLOW}10)${NC} $(t 'update_node')"
        echo -e "  ${YELLOW}11)${NC} $(t 'uninstall_node')"
        echo -e "  ${YELLOW}12)${NC} $(t 'view_node_logs')"
        echo -e "  ${YELLOW}13)${NC} $(t 'get_node_secret')"
        echo ""
        echo -e "  ${RED}0)${NC} $(t 'exit')"
        echo ""
        echo -e "${WHITE}$(t 'select_option'):${NC}"
        read -r -p "> " choice
        
        case $choice in
            1)
                install_panel
                echo ""
                read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            2)
                update_panel
                echo ""
                read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            3)
                uninstall_panel
                echo ""
                read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            4)
                view_logs
                echo ""
                read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            5)
                check_status
                echo ""
                read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            6)
                backup_db
                echo ""
                read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
                ;;
            7)
                show_login_info
                ;;
            8)
                reset_admin_password
                ;;
            9)
                install_node
                ;;
            10)
                update_node
                ;;
            11)
                uninstall_node
                ;;
            12)
                view_node_logs
                ;;
            13)
                get_node_secret
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
    
    # ИСПРАВЛЕНИЕ: Проверка перед cd
    if [ ! -d "$PANEL_DIR" ]; then
        log_error "Panel not installed / Панель не установлена"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    # ИСПРАВЛЕНИЕ: Безопасный cd (SC2164)
    cd "$PANEL_DIR" || { log_error "Cannot access $PANEL_DIR"; return 1; }
    
    # ИСПРАВЛЕНИЕ: Безопасная проверка curl (совместимо с set -e)
    if ! curl -sL -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml; then
        log_error "Failed to download docker-compose.yml"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    # Перезапускаем контейнеры с проверкой ошибок
    if ! docker compose pull; then
        log_error "Failed to pull images"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    if ! docker compose up -d; then
        log_error "Failed to start containers"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    log_success "Panel updated successfully / Панель обновлена"
    read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

uninstall_panel() {
    log_warn "This will remove Remnawave Panel and all data!"
    log_warn "Это удалит Remnawave Panel и все данные!"
    echo ""
    read -r -p "Are you sure? / Вы уверены? (y/n) " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled / Отменено"
        return 0
    fi
    
    if [ -d "$PANEL_DIR" ]; then
        cd "$PANEL_DIR" || { log_error "Cannot access $PANEL_DIR"; return 1; }
        docker compose down || true
    fi
    
    # ИСПРАВЛЕНИЕ: Симметричное удаление прокси (читаем .proxy_type, созданный в panel.sh)
    if [ -f "$PANEL_DIR/.proxy_type" ]; then
        PROXY_TYPE=$(cat "$PANEL_DIR/.proxy_type")
        if [ "$PROXY_TYPE" = "nginx" ]; then
            log_info "Cleaning up Nginx..."
            rm -f /etc/nginx/sites-enabled/remnawave
            rm -f /etc/nginx/sites-available/remnawave
            nginx -t && systemctl reload nginx || true
        else
            log_info "Cleaning up Caddy..."
            docker rm -f caddy 2>/dev/null || true
            rm -rf /etc/caddy 2>/dev/null || true
        fi
    else
        # Fallback на случай очень старых установок без .proxy_type
        docker rm -f caddy 2>/dev/null || true
    fi
    
    # ИСПРАВЛЕНИЕ: Безопасный cd /
    cd / || exit 1
    rm -rf "$PANEL_DIR"
    
    log_success "Panel uninstalled / Панель удалена"
    read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

view_logs() {
    log_step "Viewing logs..."
    
    if [ -d "$PANEL_DIR" ]; then
        cd "$PANEL_DIR" || { log_error "Cannot access $PANEL_DIR"; return 1; }
        docker compose logs -f --tail=100
    else
        log_error "Panel not installed / Панель не установлена"
    fi
    read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

check_status() {
    log_step "Checking status..."
    
    if [ -d "$PANEL_DIR" ]; then
        cd "$PANEL_DIR" || { log_error "Cannot access $PANEL_DIR"; return 1; }
        docker compose ps
    else
        log_error "Panel not installed / Панель не установлена"
    fi
    read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

backup_db() {
    log_step "Creating database backup..."
    
    if [ ! -d "$PANEL_DIR" ]; then
        log_error "Panel not installed / Панель не установлена"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    cd "$PANEL_DIR" || { log_error "Cannot access $PANEL_DIR"; return 1; }
    
    mkdir -p "$PANEL_DIR/backups"
    
    DB_CONTAINER=$(docker compose ps -q remnawave-db 2>/dev/null || true)
    
    if [ -z "$DB_CONTAINER" ]; then
        log_error "Database container not found / Контейнер базы данных не найден"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    BACKUP_FILE="$PANEL_DIR/backups/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    # ИСПРАВЛЕНИЕ: Убрана опасная конструкция с $?, которая ломалась из-за set -e.
    # Теперь используется корректная проверка через if !
    if ! docker exec "$DB_CONTAINER" pg_dump -U postgres remnawave > "$BACKUP_FILE" 2>/dev/null; then
        log_error "Backup failed / Ошибка создания бэкапа"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    log_success "Backup created: $BACKUP_FILE"
    read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
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
    read -r -p "Нажмите Enter для возврата в меню... / Press Enter to return to menu..."
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
    read -r -p "Нажмите Enter для возврата в меню... / Press Enter to return to menu..."
}

export -f show_main_menu update_panel uninstall_panel view_logs check_status backup_db show_login_info reset_admin_password
