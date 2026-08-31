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
    
    # ИСПРАВЛЕНИЕ 1: Безопасная проверка без $?, совместимая с set -e
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
    
    # ИСПРАВЛЕНИЕ 2: Безопасный cd (SC2164)
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    # ИСПРАВЛЕНИЕ 1: Проверка curl через if !
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
    
    # ИСПРАВЛЕНИЕ 4: Убрана хрупкая привязка к хардкодному "postgres" в regex.
    # Теперь мы явно перезаписываем строку DATABASE_URL, что надежнее и читаемее.
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"postgresql://postgres:${pw}@remnawave-db:5432/remnawave\"|" .env
    
    log_success "Секреты сгенерированы"
}

configure_domain() {
    log_step "Настройка домена..."
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    echo ""
    
    # ИСПРАВЛЕНИЕ 3: Добавлен флаг -r к read (SC2162)
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
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Remnawave Panel - Вход</title>
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
        .login-box {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 400px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
            text-align: center;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            text-align: center;
            font-size: 14px;
        }
        .form-group { margin-bottom: 20px; }
        label {
            display: block;
            margin-bottom: 8px;
            color: #333;
            font-weight: 500;
        }
        input[type="password"] {
            width: 100%;
            padding: 12px 16px;
            border: 2px solid #e1e1e1;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        input:focus {
            outline: none;
            border-color: #667eea;
        }
        button {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s;
        }
        button:hover { transform: translateY(-2px); }
        .error {
            background: #fee;
            color: #c33;
            padding: 12px;
            border-radius: 6px;
            margin-bottom: 20px;
            display: none;
        }
        .checkbox-group {
            display: flex;
            align-items: center;
            margin-bottom: 20px;
            gap: 8px;
        }
        .checkbox-group input {
            width: 18px;
            height: 18px;
            cursor: pointer;
        }
        .checkbox-group label {
            cursor: pointer;
            color: #666;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>🔐 Remnawave Panel</h1>
        <p class="subtitle">Введите пароль для доступа</p>
        
        <div class="error" id="errorMsg"></div>
        
        <form id="loginForm">
            <div class="form-group">
                <label for="password">Пароль доступа</label>
                <input type="password" id="password" name="password" required autocomplete="current-password">
            </div>
            
            <div class="checkbox-group">
                <input type="checkbox" id="rememberMe" checked>
                <label for="rememberMe">Запомнить меня</label>
            </div>
            
            <button type="submit">Войти</button>
        </form>
    </div>

    <script>
        // Проверяем, есть ли сохранённый пароль в localStorage
        const savedPassword = localStorage.getItem('remna_gate_password');
        const rememberMe = localStorage.getItem('remna_remember') === 'true';
        
        if (savedPassword && rememberMe) {
            // Автоматически пытаемся войти
            attemptLogin(savedPassword);
        }
        
        document.getElementById('loginForm').addEventListener('submit', function(e) {
            e.preventDefault();
            const password = document.getElementById('password').value;
            const remember = document.getElementById('rememberMe').checked;
            
            if (remember) {
                localStorage.setItem('remna_gate_password', password);
                localStorage.setItem('remna_remember', 'true');
            }
            
            attemptLogin(password);
        });
        
        function attemptLogin(password) {
            // Проверяем пароль через запрос к защищённому ресурсу
            fetch('/panel', {
                method: 'HEAD',
                headers: {
                    'Authorization': 'Basic ' + btoa('admin:' + password)
                }
            })
            .then(response => {
                if (response.status === 401 || response.status === 403) {
                    showError('Неверный пароль');
                } else {
                    // Успешно! Перенаправляем на панель
                    window.location.href = '/panel';
                }
            })
            .catch(() => {
                showError('Ошибка подключения');
            });
        }
        
        function showError(msg) {
            const errorEl = document.getElementById('errorMsg');
            errorEl.textContent = msg;
            errorEl.style.display = 'block';
            setTimeout(() => {
                errorEl.style.display = 'none';
            }, 5000);
        }
    </script>
</body>
</html>
GATEEOF
    
    log_success "Страница-заглушка создана"
}

setup_caddy() {
    log_step "Настройка Caddy с защитой и SSL..."
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

    # Создаём красивую страницу-заглушку
    create_gate_page
    
    # Генерируем Caddyfile БЕЗ фигурных скобок вокруг домена
    cat > Caddyfile << EOF
$DOMAIN {
    root * /opt/remnawave
    
    # Главная страница — без авторизации (наша заглушка)
    handle / {
        try_files {path} /gate.html
    }
    
    # Всё остальное — с авторизацией
    handle /panel* {
        basicauth {
            admin $(cat /opt/remnawave/.gate_password)
        }
        reverse_proxy remnawave:3000
    }
    
    handle /api* {
        basicauth {
            admin $(cat /opt/remnawave/.gate_password)
        }
        reverse_proxy remnawave:3000
    }
    
    handle /* {
        basicauth {
            admin $(cat /opt/remnawave/.gate_password)
        }
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
        -v "$PANEL_DIR/gate.html:/srv/gate.html" \
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
    log_step "Настройка Nginx с защитой и SSL..."
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    unlock_apt
    apt-get update -qq
    apt-get install -y -qq nginx certbot python3-certbot-nginx apache2-utils
    
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
    
    # ИСПРАВЛЕНИЕ 5: Сохраняем тип прокси для симметричного удаления
    echo "nginx" > "$PANEL_DIR/.proxy_type"
}

start_panel() {
    log_step "$(t 'starting_containers')"
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    # ИСПРАВЛЕНИЕ 1: Безопасная проверка запуска
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
    # Если любая из этих функций вернет 1, set -e в main.sh корректно обработает это,
    # но мы используем return 1 вместо exit 1, чтобы не убивать весь процесс bash мгновенно.
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

export -f unlock_apt install_docker download_panel_files generate_secrets configure_domain configure_gate_password setup_reverse_proxy setup_caddy setup_nginx start_panel install_panel
export PANEL_DIR
