#!/bin/bash

# Установка Ноды
install_node() {
    log_step "$(t 'installing_node')"

    # 1. Запрос данных
    echo ""
    read -p "$(t 'enter_panel_url'): " PANEL_URL
    PANEL_URL="${PANEL_URL%/}" # Убираем слэш в конце, если есть
    
    read -p "$(t 'enter_node_token'): " NODE_TOKEN
    if [ -z "$NODE_TOKEN" ]; then
        log_error "$(t 'error_empty_token')"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi

    read -p "$(t 'enter_node_name'): " NODE_NAME
    if [ -z "$NODE_NAME" ]; then
        NODE_NAME="remnanode-1"
    fi

    read -p "$(t 'enter_node_port') [2222]: " NODE_PORT
    if [ -z "$NODE_PORT" ]; then
        NODE_PORT="2222"
    fi

    # 2. Проверка доступности Панели
    log_info "$(t 'checking_panel_availability')"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k --connect-timeout 10 "$PANEL_URL" || echo "000")
    
    if [[ "$HTTP_STATUS" == "000" ]]; then
        log_error "$(t 'panel_unreachable')"
        log_warn "Проверьте URL и наличие подключения к интернету"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    else
        log_success "Панель отвечает (HTTP $HTTP_STATUS)"
    fi

    # 3. Создание директории
    NODE_DIR="/opt/remnanode"
    mkdir -p "$NODE_DIR"
    cd "$NODE_DIR"

    # 4. Генерация .env (безопасное хранение секретов)
    log_info "$(t 'generating_secrets')"
    cat > .env << EOF
NODE_PORT='$NODE_PORT'
SECRET_KEY='$NODE_TOKEN'
NODE_NAME='$NODE_NAME'
EOF
    chmod 600 .env

    # 5. Создание docker-compose.yml (официальный формат Remnawave Node)
    cat > docker-compose.yml << 'EOF'
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    env_file:
      - .env
EOF

    # 6. Запуск контейнера
    log_info "$(t 'starting_containers')"
    if ! docker compose up -d; then
        log_error "$(t 'error_docker_compose')"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi

    # 7. Проверка статуса
    sleep 3
    if docker compose ps | grep -q "Up"; then
        log_success "$(t 'node_installed')"
        echo ""
        echo -e "${CYAN}Panel URL:${NC} $PANEL_URL"
        echo -e "${CYAN}Node Port:${NC} $NODE_PORT"
    else
        log_error "$(t 'error_node_start')"
        docker compose logs --tail=20
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

# Обновление Ноды
update_node() {
    NODE_DIR="/opt/remnanode"
    if [ ! -d "$NODE_DIR" ] || [ ! -f "$NODE_DIR/docker-compose.yml" ]; then
        log_error "$(t 'node_not_installed')"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi

    log_step "$(t 'updating_node')"
    cd "$NODE_DIR"
    docker compose pull
    docker compose up -d
    log_success "Node updated successfully / Нода обновлена"
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

# Удаление Ноды
uninstall_node() {
    NODE_DIR="/opt/remnanode"
    if [ ! -d "$NODE_DIR" ]; then
        log_error "$(t 'node_not_installed')"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi

    log_warn "This will remove Remnawave Node and all its data!"
    log_warn "Это удалит Remnawave Node и все её данные!"
    echo ""
    read -p "Are you sure? / Вы уверены? (y/n) " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Cancelled / Отменено"
        return 0
    fi

    log_step "$(t 'uninstalling_node')"
    cd "$NODE_DIR"
    docker compose down
    cd /
    rm -rf "$NODE_DIR"
    
    log_success "Node uninstalled / Нода удалена"
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

# Просмотр логов Ноды
view_node_logs() {
    NODE_DIR="/opt/remnanode"
    if [ ! -d "$NODE_DIR" ] || [ ! -f "$NODE_DIR/docker-compose.yml" ]; then
        log_error "$(t 'node_not_installed')"
        read -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi

    log_step "Viewing node logs..."
    cd "$NODE_DIR"
    docker compose logs -f --tail=100
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

# Получение Secret Key (инструкция)
get_node_secret() {
    log_step "$(t 'get_node_secret')"
    echo ""
    echo -e "${CYAN}$(t 'secret_key_instruction')${NC}"
    echo ""
    read -p "Press Enter to continue / Нажмите Enter для продолжения..."
}

export -f install_node update_node uninstall_node view_node_logs get_node_secret
