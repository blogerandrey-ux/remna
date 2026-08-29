#!/bin/bash

# Путь для установки панели
PANEL_DIR="/opt/remnawave"

install_docker() {
    log_step "$(t 'installing_docker')"
    
    if [ "$DOCKER_INSTALLED" = true ]; then
        log_info "Docker already installed, skipping..."
        return 0
    fi
    
    # Установка Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    
    if [ $? -ne 0 ]; then
        log_error "$(t 'error_docker')"
        exit 1
    fi
    
    # Запуск Docker
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker installed successfully"
}

download_panel_files() {
    log_step "$(t 'downloading_files')"
    
    # Создаём директорию
    mkdir -p "$PANEL_DIR"
    cd "$PANEL_DIR"
    
    # Скачиваем docker-compose.yml и .env.sample с официального репозитория
    curl -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
    curl -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample
    
    if [ ! -f docker-compose.yml ] || [ ! -f .env ]; then
        log_error "Failed to download files / Не удалось загрузить файлы"
        exit 1
    fi
    
    log_success "Files downloaded successfully"
}

generate_secrets() {
    log_step "$(t 'generating_secrets')"
    
    cd "$PANEL_DIR"
    
    # Генерация APP_SECRET
    sed -i "s/^APP_SECRET=.*/APP_SECRET=$(openssl rand -hex 64)/" .env
    
    # Генерация METRICS_PASS
    sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
    
    # Генерация WEBHOOK_SECRET_HEADER
    sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env
    
    # Генерация пароля PostgreSQL
    pw=$(openssl rand -hex 24)
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
    sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$pw\2|" .env
    
    log_success "Secrets generated successfully"
}

configure_domain() {
    log_step "Configuring domain..."
    
    cd "$PANEL_DIR"
    
    echo ""
    read -p "$(t 'enter_domain'): " DOMAIN
    
    # Проверка домена
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-z]{2,}$ ]]; then
        log_error "$(t 'error_domain')"
        exit 1
    fi
    
    # Сохраняем домен в .env
    sed -i "s/^FRONT_END_DOMAIN=.*/FRONT_END_DOMAIN=$DOMAIN/" .env
    sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$DOMAIN/api/sub|" .env
    
    # Сохраняем домен для дальнейшего использования
    echo "$DOMAIN" > /opt/remnawave/.domain
    
    log_success "Domain configured: $DOMAIN"
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
        log_error "Invalid choice / Неверный выбор"
        exit 1
    fi
}

setup_caddy() {
    log_step "Setting up Caddy..."
    
    cd "$PANEL_DIR"
    
    # Создаём Caddyfile
    cat > Caddyfile << EOF
$DOMAIN {
    reverse_proxy localhost:3000
}
EOF
    
    # Запускаем Caddy в Docker
    docker run -d --name caddy \
        --restart unless-stopped \
        -p 80:80 \
        -p 443:443 \
        -p 443:443/udp \
        -v "$PANEL_DIR/Caddyfile:/etc/caddy/Caddyfile" \
        -v caddy_data:/data \
        -v caddy_config:/config \
        caddy:2-alpine
    
    log_success "Caddy installed and configured"
}

setup_nginx() {
    log_step "Setting up Nginx..."
    
    cd "$PANEL_DIR"
    
    # Установка Nginx
    apt-get update
    apt-get install -y nginx certbot python3-certbot-nginx
    
    # Создаём конфиг
    cat > /etc/nginx/sites-available/remnawave << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
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
    
    # Включаем сайт
    ln -sf /etc/nginx/sites-available/remnawave /etc/nginx/sites-enabled/remnawave
    nginx -t
    systemctl restart nginx
    
    # Получаем SSL сертификат
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
    
    log_success "Nginx installed and configured with SSL"
}

start_panel() {
    log_step "$(t 'starting_containers')"
    
    cd "$PANEL_DIR"
    
    # Запускаем контейнеры
    docker compose up -d
    
    # Ждём запуска
    sleep 10
    
    # Проверяем статус
    if docker compose ps | grep -q "Up"; then
        log_success "$(t 'panel_installed')"
        echo ""
        echo -e "${CYAN}════════════════════════════════════════${NC}"
        echo -e "$(t 'success_installation')"
        echo -e "$(t 'panel_url') https://$DOMAIN"
        echo -e "${CYAN}════════════════════════════════════════${NC}"
        echo ""
    else
        log_error "Failed to start containers / Не удалось запустить контейнеры"
        log_error "Check logs: cd $PANEL_DIR && docker compose logs"
        exit 1
    fi
}

install_panel() {
    install_docker
    download_panel_files
    generate_secrets
    configure_domain
    setup_reverse_proxy
    start_panel
}

export -f install_docker download_panel_files generate_secrets configure_domain setup_reverse_proxy setup_caddy setup_nginx start_panel install_panel
export PANEL_DIR
