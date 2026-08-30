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
    
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    
    if [ $? -ne 0 ]; then
        log_error "$(t 'error_docker')"
        exit 1
    fi
    
    systemctl enable docker
    systemctl start docker
    log_success "Docker успешно установлен"
}

download_panel_files() {
    log_step "$(t 'downloading_files')"
    mkdir -p "$PANEL_DIR"
    cd "$PANEL_DIR"
    
    curl -sL -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
    curl -sL -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample
    
    if [ ! -f docker-compose.yml ] || [ ! -f .env ]; then
        log_error "Не удалось загрузить файлы"
        exit 1
    fi
    log_success "Файлы загружены"
}

generate_secrets() {
    log_step "$(t 'generating_secrets')"
    cd "$PANEL_DIR"
    
    sed -i "s/^APP_SECRET=.*/APP_SECRET=$(openssl rand -hex 64)/" .env
    sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
    sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env
    
    pw=$(openssl rand -hex 24)
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
    sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$pw\2|" .env
    
    log_success "Секреты сгенерированы"
}

configure_domain() {
    log_step "Настройка домена..."
    cd "$PANEL_DIR"
    echo ""
    read -p "$(t 'enter_domain'): " DOMAIN
    
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-z]{2,}$ ]]; then
        log_error "$(t 'error_domain')"
        exit 1
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
    read -p "> " gate_choice
    
    if [ "$gate_choice" = "1" ]; then
        # Пользователь вводит свой пароль
        read -s -p "Введите пароль: " GATE_PASSWORD
        echo ""
        read -s -p "Подтвердите пароль: " GATE_PASSWORD_CONFIRM
        echo ""
        
        if [ "$GATE_PASSWORD" != "$GATE_PASSWORD_CONFIRM" ]; then
            log_error "Пароли не совпадают! Используйте опцию 2 для автогенерации."
            exit 1
        fi
        
        if [ -z "$GATE_PASSWORD" ]; then
            log_error "Пароль не может быть пустым!"
            exit 1
        fi
        
        echo "$GATE_PASSWORD" > /opt/remnawave/.gate_password
        log_success "$(t 'gate_password_set')"
        
    elif [ "$gate_choice" = "2" ]; then
        # Автогенерация
        GATE_PASSWORD=$(openssl rand -hex 16)
        echo "$GATE_PASSWORD" > /opt/remnawave/.gate_password
        log_success "$(t 'gate_password_set')"
        echo -e "${GREEN}Автоматически сгенерированный пароль: $GATE_PASSWORD${NC}"
        
    elif [ "$gate_choice" = "3" ]; then
        # Пропускаем защиту
        rm -f /opt/remnawave/.gate_password
        log_info "$(t 'gate_password_skipped')"
        return 0
        
    else
        log_error "Неверный выбор"
        exit 1
    fi
}

setup_reverse_proxy() {
    log_step "$(t 'select_proxy')"
    echo "  1) $(t 'caddy')"
    echo "  2) $(t 'nginx')"
    echo ""
    read -p "> " proxy_choice
    
    if [ "$proxy_choice" = "1" ]; then
        setup_caddy
    elif [ "$proxy_choice" = "2" ]; then
        setup_nginx
    else
        log_error "Неверный выбор"
        exit 1
    fi
}

setup_caddy() {
    log_step "Настройка Caddy с защитой и SSL..."
    cd "$PANEL_DIR"
    
    # Проверка DNS
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_IP=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)
    
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        log_warn "ВНИМАНИЕ: IP сервера ($SERVER_IP) не совпадает с IP домена ($DOMAIN_IP)!"
        log_warn "Caddy не сможет получить SSL, пока DNS-запись не обновится."
        echo ""
        read -p "Продолжить установку всё равно? (y/n): " continue_caddy
        if [ "$continue_caddy" != "y" ]; then
            log_info "Установка прервана. Настройте DNS и запустите скрипт снова."
            exit 0
        fi
    fi

    # Создаем Caddyfile с или без защиты
    if [ -f /opt/remnawave/.gate_password ]; then
        GATE_PASSWORD=$(cat /opt/remnawave/.gate_password)
        cat > Caddyfile << EOF
{$DOMAIN} {
    basicauth /* {
        admin {$GATE_PASSWORD}
    }
    reverse_proxy remnawave:3000
}
EOF
    else
        cat > Caddyfile << EOF
{$DOMAIN} {
    reverse_proxy remnawave:3000
}
EOF
    fi
    
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
    else
        log_success "Caddy успешно запущен!"
    fi
}

setup_nginx() {
    log_step "Настройка Nginx с защитой и SSL..."
    cd "$PANEL_DIR"
    
    unlock_apt
    apt-get update -qq
    apt-get install -y -qq nginx certbot python3-certbot-nginx apache2-utils
    
    # Создаем конфиг с или без защиты
    if [ -f /opt/remnawave/.gate_password ]; then
        GATE_PASSWORD=$(cat /opt/remnawave/.gate_password)
        htpasswd -bc /opt/remnawave/.htpasswd admin "$GATE_PASSWORD"
        
        cat > /etc/nginx/sites-available/remnawave << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    auth_basic "Restricted Access";
    auth_basic_user_file /opt/remnawave/.htpasswd;

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
    else
        cat > /etc/nginx/sites-available/remnawave << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

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
    fi
    
    ln -sf /etc/nginx/sites-available/remnawave /etc/nginx/sites-enabled/remnawave
    nginx -t
    systemctl restart nginx
    
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
    log_success "Nginx установлен и настроен с SSL"
}

start_panel() {
    log_step "$(t 'starting_containers')"
    cd "$PANEL_DIR"
    
    docker compose up -d
    
    log_info "Ожидание запуска базы данных и приложения (15 секунд)..."
    sleep 15
    
    if docker compose ps | grep -q "Up"; then
        log_success "$(t 'panel_installed')"
    else
        log_error "Не удалось запустить контейнеры"
        log_error "Проверьте логи: cd $PANEL_DIR && docker compose logs"
        exit 1
    fi
}

install_panel() {
    install_docker
    download_panel_files
    generate_secrets
    configure_domain
    configure_gate_password  # Новая функция
    
    start_panel
    setup_reverse_proxy
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "$(t 'success_installation')"
    echo -e "$(t 'panel_url') https://$DOMAIN"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
}

export -f unlock_apt install_docker download_panel_files generate_secrets configure_domain configure_gate_password setup_reverse_proxy setup_caddy setup_nginx start_panel install_panel
export PANEL_DIR
