#!/bin/bash

# Путь для установки панели
PANEL_DIR="/opt/remnawave"

# Функция для гарантированной разблокировки apt
unlock_apt() {
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
        log_warn "Обнаружена блокировка пакетов (unattended-upgrades). Освобождаю..."
        killall -9 unattended-upgrades 2>/dev/null || true
        fuser -k /var/lib/dpkg/lock-frontend 2>/dev/null || true
        fuser -k /var/lib/dpkg/lock 2>/dev/null || true
        fuser -k /var/lib/apt/lists/lock 2>/dev/null || true
        fuser -k /var/cache/apt/archives/lock 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock
        dpkg --configure -a
        sleep 2
        log_success "Система пакетов разблокирована"
    fi
}

install_docker() {
    log_step "$(t 'installing_docker')"
    
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        log_success "Docker уже установлен и работает. Пропускаем."
        return 0
    fi
    
    log_info "Установка Docker..."
    unlock_apt
    
    if ! curl -fsSL https://get.docker.com -o get-docker.sh; then
        log_error "$(t 'error_docker')"
        return 1
    fi
    
    if ! sh get-docker.sh; then
        log_error "$(t 'error_docker')"
        rm -f get-docker.sh
        return 1
    fi
    rm -f get-docker.sh
    
    systemctl enable docker
    systemctl start docker
    log_success "Docker успешно установлен"
}

download_panel_files() {
    log_step "$(t 'downloading_files')"
    mkdir -p "$PANEL_DIR"
    
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    if ! curl -sL -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml; then
        log_error "Не удалось загрузить docker-compose.yml"
        return 1
    fi
    
    if ! curl -sL -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample; then
        log_error "Не удалось загрузить .env.sample"
        return 1
    fi
    
    log_success "Файлы загружены"
}

generate_secrets() {
    log_step "$(t 'generating_secrets')"
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    sed -i "s/^APP_SECRET=.*/APP_SECRET=$(openssl rand -hex 64)/" .env
    sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
    sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env
    
    pw=$(openssl rand -hex 24)
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"postgresql://postgres:${pw}@remnawave-db:5432/remnawave\"|" .env
    
    log_success "Секреты сгенерированы"
}

configure_domain() {
    log_step "Настройка домена..."
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    echo ""
    
    read -r -p "$(t 'enter_domain'): " DOMAIN
    
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-z]{2,}$ ]]; then
        log_error "$(t 'error_domain')"
        return 1
    fi
    
    sed -i "s/^FRONT_END_DOMAIN=.*/FRONT_END_DOMAIN=$DOMAIN/" .env
    sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$DOMAIN/api/sub|" .env
    echo "$DOMAIN" > /opt/remnawave/.domain
    log_success "Домен настроен: $DOMAIN"
}

configure_gate_password() {
    log_step "$(t 'configure_gate_password')"
    echo ""
    echo -e "${YELLOW}1)${NC} $(t 'enter_gate_password')"
    echo -e "${YELLOW}2)${NC} $(t 'use_auto_password')"
    echo -e "${YELLOW}3)${NC} $(t 'skip_gate_password')"
    echo ""
    read -r -p "> " gate_choice
    
    if [ "$gate_choice" = "1" ]; then
        read -r -s -p "Введите пароль: " GATE_PASSWORD
        echo ""
        read -r -s -p "Подтвердите пароль: " GATE_PASSWORD_CONFIRM
        echo ""
        
        if [ "$GATE_PASSWORD" != "$GATE_PASSWORD_CONFIRM" ]; then
            log_error "Пароли не совпадают! Используйте опцию 2 для автогенерации."
            return 1
        fi
        
        if [ -z "$GATE_PASSWORD" ]; then
            log_error "Пароль не может быть пустым!"
            return 1
        fi
        
        echo "$GATE_PASSWORD" > /opt/remnawave/.gate_password
        log_success "$(t 'gate_password_set')"
        
    elif [ "$gate_choice" = "2" ]; then
        GATE_PASSWORD=$(openssl rand -hex 16)
        echo "$GATE_PASSWORD" > /opt/remnawave/.gate_password
        log_success "$(t 'gate_password_set')"
        echo -e "${GREEN}Автоматически сгенерированный пароль: $GATE_PASSWORD${NC}"
        
    elif [ "$gate_choice" = "3" ]; then
        rm -f /opt/remnawave/.gate_password
        log_info "$(t 'gate_password_skipped')"
        return 0
    else
        log_error "Неверный выбор"
        return 1
    fi
}

setup_reverse_proxy() {
    log_step "$(t 'select_proxy')"
    echo "  1) $(t 'caddy')"
    echo "  2) $(t 'nginx')"
    echo ""
    read -r -p "> " proxy_choice
    
    if [ "$proxy_choice" = "1" ]; then
        setup_caddy
    elif [ "$proxy_choice" = "2" ]; then
        setup_nginx
    else
        log_error "Неверный выбор"
        return 1
    fi
}

create_gate_page() {
    log_info "Создание страницы-заглушки..."
    
    cat > "$PANEL_DIR/gate.html" << 'GATEEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="3; url=/panel">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Remnawave Panel</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .box {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            width: 100%;
            max-width: 400px;
        }
        h1 { color: #333; margin-bottom: 15px; font-size: 28px; }
        p { color: #666; margin-bottom: 25px; font-size: 16px; }
        .btn {
            display: inline-block;
            padding: 14px 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-decoration: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            transition: transform 0.2s;
        }
        .btn:hover { transform: translateY(-2px); }
    </style>
</head>
<body>
    <div class="box">
        <h1>🔐 Remnawave Panel</h1>
        <p>Перенаправление на страницу входа...</p>
        <a href="/panel" class="btn">Перейти к входу</a>
    </div>
</body>
</html>
GATEEOF
    
    log_success "Страница-заглушка создана"
}

setup_caddy() {
    log_step "Настройка Caddy с SSL..."
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_IP=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)
    
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        log_warn "ВНИМАНИЕ: IP сервера ($SERVER_IP) не совпадает с IP домена ($DOMAIN_IP)!"
        log_warn "Caddy не сможет получить SSL, пока DNS-запись не обновится."
        echo ""
        read -r -p "Продолжить установку всё равно? (y/n): " continue_caddy
        if [[ "$continue_caddy" != "y" && "$continue_caddy" != "Y" ]]; then
            log_info "Установка прервана. Настройте DNS и запустите скрипт снова."
            return 1
        fi
    fi

    create_gate_page
    
    cat > Caddyfile << EOF
$DOMAIN {
    root * /opt/remnawave
    
    handle / {
        try_files /gate.html
    }
    
    handle {
        reverse_proxy remnawave:3000
    }
}
EOF
    
    docker rm -f caddy 2>/dev/null || true
    
    docker run -d --name caddy \
        --restart unless-stopped \
        --network remnawave-network \
        -p 80:80 \
        -p 443:443 \
        -v "$PANEL_DIR/Caddyfile:/etc/caddy/Caddyfile" \
        -v caddy_data:/data \
        -v caddy_config:/config \
        caddy:2-alpine
    
    log_info "Ожидаем получения SSL-сертификата (до 30 секунд)..."
    sleep 15
    
    if ! docker ps | grep -q caddy; then
        log_error "Caddy не запустился! Причина:"
        docker logs caddy --tail 15
        return 1
    else
        log_success "Caddy успешно запущен!"
    fi
    
    echo "caddy" > "$PANEL_DIR/.proxy_type"
}

setup_nginx() {
    log_step "Настройка Nginx с SSL..."
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    unlock_apt
    apt-get update -qq
    apt-get install -y -qq nginx certbot python3-certbot-nginx
    
    create_gate_page
    
    cat > /etc/nginx/sites-available/remnawave << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    root /opt/remnawave;
    index gate.html;

    location = /gate.html {
        try_files \$uri =404;
        add_header Content-Type text/html;
    }
    
    location = / {
        try_files /gate.html =404;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/remnawave /etc/nginx/sites-enabled/remnawave
    
    if ! nginx -t; then
        log_error "Ошибка в конфигурации Nginx"
        return 1
    fi
    
    systemctl restart nginx
    
    if ! certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email; then
        log_warn "Certbot завершился с ошибкой. Проверьте DNS и запустите certbot вручную."
    else
        log_success "Nginx установлен и настроен с SSL"
    fi
    
    echo "nginx" > "$PANEL_DIR/.proxy_type"
}

start_panel() {
    log_step "$(t 'starting_containers')"
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    if ! docker compose up -d; then
        log_error "Не удалось запустить контейнеры"
        return 1
    fi
    
    log_info "Ожидание запуска базы данных и приложения (15 секунд)..."
    sleep 15
    
    if docker compose ps | grep -q "Up"; then
        log_success "$(t 'panel_installed')"
    else
        log_error "Не удалось запустить контейнеры"
        log_error "Проверьте логи: cd $PANEL_DIR && docker compose logs"
        return 1
    fi
}

install_panel() {
    install_docker || return 1
    download_panel_files || return 1
    generate_secrets || return 1
    configure_domain || return 1
    configure_gate_password || return 1
    
    start_panel || return 1
    setup_reverse_proxy || return 1
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "$(t 'success_installation')"
    echo -e "$(t 'panel_url') https://$DOMAIN"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
}

# ========================================
# ФУНКЦИИ УПРАВЛЕНИЯ (ОБНОВЛЕНИЕ, УДАЛЕНИЕ И Т.Д.)
# ========================================

update_panel() {
    log_step "Обновление Remnawave Panel..."
    
    if [ ! -d "$PANEL_DIR" ]; then
        log_error "Panel not installed / Панель не установлена"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi

    cd "$PANEL_DIR" || { log_error "Cannot access $PANEL_DIR"; return 1; }
    
    if ! curl -sL -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml; then
        log_error "Failed to download docker-compose.yml"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
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
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Cancelled / Отменено"
        return 0
    fi
    
    if [ -d "$PANEL_DIR" ]; then
        cd "$PANEL_DIR" || { log_error "Cannot access $PANEL_DIR"; return 1; }
        docker compose down || true
    fi
    
    # Симметричное удаление прокси
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
        fi
    else
        docker rm -f caddy 2>/dev/null || true
    fi
    
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

export -f unlock_apt install_docker download_panel_files generate_secrets configure_domain configure_gate_password create_gate_page setup_reverse_proxy setup_caddy setup_nginx start_panel install_panel update_panel uninstall_panel view_logs check_status backup_db show_login_info reset_admin_password
export PANEL_DIR
