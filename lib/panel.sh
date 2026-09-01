#!/bin/bash
set -euo pipefail

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
    
    local pw
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
    
    if [[ "$gate_choice" == "1" ]]; then
        read -r -s -p "Введите пароль: " GATE_PASS_1
        echo ""
        read -r -s -p "Подтвердите пароль: " GATE_PASS_2
        echo ""
        
        if [[ -z "${GATE_PASS_1:-}" ]]; then
            log_error "Пароль не может быть пустым!"
            return 1
        fi
        
        if [[ "$GATE_PASS_1" != "$GATE_PASS_2" ]]; then
            log_error "Пароли не совпадают! Попробуйте снова."
            return 1
        fi
        
        # Сохраняем ТОЛЬКО хеш, оригинальный пароль стирается из переменных
        echo -n "$GATE_PASS_1" | sha256sum | awk '{print $1}' > "$PANEL_DIR/.gate_hash"
        GATE_PASS_1=""
        GATE_PASS_2=""
        log_success "$(t 'gate_password_set')"
        
    elif [[ "$gate_choice" == "2" ]]; then
        local auto_pass
        auto_pass=$(openssl rand -hex 16)
        echo -n "$auto_pass" | sha256sum | awk '{print $1}' > "$PANEL_DIR/.gate_hash"
        log_success "$(t 'gate_password_set')"
        echo -e "${GREEN}Автоматический пароль (сохраните его!): $auto_pass${NC}"
        
    elif [[ "$gate_choice" == "3" ]]; then
        rm -f "$PANEL_DIR/.gate_hash"
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
    
    if [[ "$proxy_choice" == "1" ]]; then
        setup_caddy
    elif [[ "$proxy_choice" == "2" ]]; then
        setup_nginx
    else
        log_error "Неверный выбор"
        return 1
    fi
}

deploy_gate_auth_service() {
    log_step "Развертывание сервиса аутентификации Gate..."
    
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 не найден. Установите его (apt install python3) для работы защиты."
        return 1
    fi

    local gate_hash=""
    if [[ -f "$PANEL_DIR/.gate_hash" ]]; then
        gate_hash=$(cat "$PANEL_DIR/.gate_hash")
    else
        log_warn "Файл .gate_hash не найден. Генерируем временный..."
        gate_hash=$(openssl rand -hex 32)
        echo "$gate_hash" > "$PANEL_DIR/.gate_hash"
    fi

    cat > /usr/local/bin/remna-gate.py << 'PYTHON_EOF'
#!/usr/bin/env python3
import os, sys, json, hashlib, urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

EXPECTED_HASH = os.environ.get('REMNA_GATE_HASH', '')

class GateHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Тихий режим

    def do_GET(self):
        if self.path == '/validate':
            cookie = self.headers.get('Cookie', '')
            auth_val = None
            for part in cookie.split(';'):
                if part.strip().startswith('remna_auth='):
                    auth_val = part.strip().split('=', 1)[1]
                    break
            
            if auth_val and auth_val == EXPECTED_HASH:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'OK')
            else:
                self.send_response(401)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/login':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            
            password = None
            for item in post_data.split('&'):
                if item.startswith('password='):
                    password = urllib.parse.unquote(item.split('=', 1)[1].replace('+', ' '))
                    break
            
            if password:
                hashed = hashlib.sha256(password.encode('utf-8')).hexdigest()
                if hashed == EXPECTED_HASH:
                    self.send_response(200)
                    self.send_header('Set-Cookie', f'remna_auth={EXPECTED_HASH}; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800')
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode('utf-8'))
                else:
                    self.send_response(401)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "error"}).encode('utf-8'))
            else:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    if not EXPECTED_HASH:
        sys.exit(1)
    server = HTTPServer(('127.0.0.1', 8088), GateHandler)
    server.serve_forever()
PYTHON_EOF

    if ! chmod +x /usr/local/bin/remna-gate.py; then
        log_error "Не удалось сделать скрипт исполняемым"
        return 1
    fi

    cat > /etc/systemd/system/remna-gate.service << EOF
[Unit]
Description=Remnawave Gate Auth Service
After=network.target

[Service]
Type=simple
Environment=REMNA_GATE_HASH=$gate_hash
ExecStart=/usr/bin/python3 /usr/local/bin/remna-gate.py
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    if ! systemctl daemon-reload; then
        log_error "Не удалось перезагрузить systemd daemon"
        return 1
    fi

    if ! systemctl enable --now remna-gate.service; then
        log_error "Не удалось запустить сервис remna-gate"
        return 1
    fi

    log_success "Сервис проверки пароля запущен"
}

create_gate_page() {
    log_info "Создание страницы-заглушки Gate..."
    
    cat > "$PANEL_DIR/gate.html" << 'GATEEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Remnawave Access Gate</title>
    <style>
        :root { --bg: #0f172a; --card: #1e293b; --text: #f8fafc; --accent: #3b82f6; --error: #ef4444; }
        body { margin: 0; display: flex; align-items: center; justify-content: center; min-height: 100vh; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        .gate-card { background: var(--card); padding: 2.5rem; border-radius: 12px; box-shadow: 0 20px 25px -5px rgba(0,0,0,0.3); width: 100%; max-width: 400px; text-align: center; }
        .gate-card h1 { margin: 0 0 1.5rem 0; font-size: 1.5rem; font-weight: 600; }
        .input-group { margin-bottom: 1.5rem; text-align: left; }
        .input-group label { display: block; margin-bottom: 0.5rem; font-size: 0.875rem; color: #94a3b8; }
        .input-group input { width: 100%; padding: 0.75rem; border: 1px solid #334155; border-radius: 6px; background: #0f172a; color: white; font-size: 1rem; box-sizing: border-box; outline: none; transition: border-color 0.2s; }
        .input-group input:focus { border-color: var(--accent); }
        .btn { width: 100%; padding: 0.75rem; background: var(--accent); color: white; border: none; border-radius: 6px; font-size: 1rem; font-weight: 500; cursor: pointer; transition: background 0.2s; }
        .btn:hover { background: #2563eb; }
        .btn:disabled { background: #64748b; cursor: not-allowed; }
        .error-msg { color: var(--error); font-size: 0.875rem; margin-top: 1rem; display: none; }
    </style>
</head>
<body>
    <div class="gate-card">
        <h1>🔒 Remnawave Panel</h1>
        <form id="gateForm">
            <div class="input-group">
                <label for="password">Access Password</label>
                <input type="password" id="password" name="password" required autocomplete="current-password" autofocus>
            </div>
            <button type="submit" class="btn">Unlock</button>
            <div id="errorMsg" class="error-msg">Invalid password. Please try again.</div>
        </form>
    </div>
    <script>
        document.getElementById('gateForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const pwd = document.getElementById('password').value;
            const btn = e.target.querySelector('.btn');
            const err = document.getElementById('errorMsg');
            
            btn.disabled = true;
            btn.textContent = 'Checking...';
            err.style.display = 'none';

            try {
                const res = await fetch('/auth_login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: 'password=' + encodeURIComponent(pwd)
                });
                
                if (res.ok) {
                    window.location.reload();
                } else {
                    err.style.display = 'block';
                    document.getElementById('password').value = '';
                    document.getElementById('password').focus();
                }
            } catch (e) {
                err.textContent = 'Connection error';
                err.style.display = 'block';
            } finally {
                btn.disabled = false;
                btn.textContent = 'Unlock';
            }
        });
    </script>
</body>
</html>
GATEEOF
    
    log_success "Страница-заглушка обновлена"
}

setup_caddy() {
    log_step "Настройка Caddy с SSL и Gate-защитой..."
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    local domain="$DOMAIN"
    if [[ -z "${domain:-}" ]]; then
        if [[ -f "$PANEL_DIR/.domain" ]]; then
            domain=$(cat "$PANEL_DIR/.domain")
        else
            log_error "Домен не найден. Настройте домен сначала."
            return 1
        fi
    fi

    local server_ip
    server_ip=$(curl -s ifconfig.me)
    local domain_ip
    domain_ip=$(getent ahosts "$domain" | awk '{print $1}' | head -n 1)
    
    if [[ "$server_ip" != "$domain_ip" ]]; then
        log_warn "ВНИМАНИЕ: IP сервера ($server_ip) не совпадает с IP домена ($domain_ip)!"
        log_warn "Caddy не сможет получить SSL, пока DNS-запись не обновится."
        echo ""
        read -r -p "Продолжить установку всё равно? (y/n): " continue_caddy
        if [[ "$continue_caddy" != "y" && "$continue_caddy" != "Y" ]]; then
            log_info "Установка прервана. Настройте DNS и запустите скрипт снова."
            return 1
        fi
    fi

    create_gate_page
    deploy_gate_auth_service
    
    # Генерируем исправленный Caddyfile
    cat > Caddyfile << EOF
$domain {
    # 1. ACME Challenge (без авторизации)
    handle_path /.well-known/acme-challenge/* {
        root * /var/www/html
        file_server
    }

    # 2. API для проверки пароля (прокси на Python)
    handle /auth_login {
        reverse_proxy 127.0.0.1:8088
    }

    # 3. Страница заглушки (ЯВНО указываем root, чтобы file_server нашел файл)
    handle /gate.html {
        root * $PANEL_DIR
        file_server
    }

    # 4. ПРОВЕРКА: Если в Cookie НЕТ валидного хеша, переписываем запрос на /gate.html
    # ИСПРАВЛЕНО: добавлено имя 'has_auth_cookie' для корректной работы header_regexp в Caddy v2
    @needs_auth {
        not header_regexp has_auth_cookie Cookie .*remna_auth=[a-f0-9]{64}.*
    }
    
    handle @needs_auth {
        rewrite * /gate.html
    }

    # 5. Всё остальное проксируем в Remnawave (если cookie есть, запрос попадет сюда)
    handle {
        reverse_proxy remnawave:3000
    }
}
EOF
    
    docker rm -f caddy 2>/dev/null || true
    
    if ! docker run -d --name caddy \
        --restart unless-stopped \
        --network remnawave-network \
        -p 80:80 \
        -p 443:443 \
        -v "$PANEL_DIR/Caddyfile:/etc/caddy/Caddyfile" \
        -v caddy_data:/data \
        -v caddy_config:/config \
        caddy:2-alpine; then
        log_error "Не удалось запустить Caddy"
        return 1
    fi
    
    log_info "Ожидаем получения SSL-сертификата и применения конфига (до 30 секунд)..."
    sleep 15
    
    if ! docker ps | grep -q caddy; then
        log_error "Caddy не запустился! Причина:"
        docker logs caddy --tail 20
        return 1
    else
        # Проверяем, нет ли ошибок валидации в логах Caddy
        if docker logs caddy 2>&1 | grep -qi "error"; then
            log_warn "Caddy запущен, но в логах есть предупреждения. Проверьте 'docker logs caddy'."
        fi
        log_success "Caddy успешно запущен с кастомной Gate-защитой!"
    fi
    
    echo "caddy" > "$PANEL_DIR/.proxy_type"
}

setup_nginx() {
    log_step "Настройка Nginx с SSL и Gate-защитой..."
    cd "$PANEL_DIR" || { log_error "Не удалось перейти в $PANEL_DIR"; return 1; }
    
    unlock_apt
    if ! apt-get update -qq; then
        log_error "Ошибка обновления пакетов"
        return 1
    fi
    # apache2-utils больше не нужен, так как мы не используем htpasswd
    if ! apt-get install -y -qq nginx certbot python3-certbot-nginx; then
        log_error "Ошибка установки Nginx или Certbot"
        return 1
    fi
    
    create_gate_page
    deploy_gate_auth_service
    
    local domain="$DOMAIN"
    if [[ -z "${domain:-}" ]]; then
        if [[ -f "$PANEL_DIR/.domain" ]]; then
            domain=$(cat "$PANEL_DIR/.domain")
        else
            log_error "Домен не найден. Настройте домен сначала."
            return 1
        fi
    fi

    cat > /etc/nginx/sites-available/remnawave << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        auth_request off;
        root /var/www/html;
    }

    location / {
        auth_request /auth_validate;
        error_page 401 = /gate.html;
        
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

    location = /gate.html {
        root $PANEL_DIR;
        internal;
        add_header Content-Type text/html;
    }

    location = /auth_validate {
        internal;
        proxy_pass http://127.0.0.1:8088/validate;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header Cookie \$http_cookie;
    }

    location = /auth_login {
        proxy_pass http://127.0.0.1:8088/login;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/remnawave /etc/nginx/sites-enabled/remnawave
    
    if ! nginx -t; then
        log_error "Ошибка в конфигурации Nginx"
        return 1
    fi
    
    if ! systemctl restart nginx; then
        log_error "Не удалось перезапустить Nginx"
        return 1
    fi
    
    if ! certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email; then
        log_warn "Certbot завершился с ошибкой. Проверьте DNS и запустите certbot вручную."
    else
        log_success "Nginx установлен с SSL и кастомной Gate-защитой (без браузерных окон)"
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
    
    # Очистка сервиса Gate
    log_info "Cleaning up Gate service..."
    systemctl disable --now remna-gate.service 2>/dev/null || true
    rm -f /etc/systemd/system/remna-gate.service
    rm -f /usr/local/bin/remna-gate.py
    systemctl daemon-reload 2>/dev/null || true
    
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
    
    local DB_CONTAINER
    DB_CONTAINER=$(docker compose ps -q remnawave-db 2>/dev/null || true)
    
    if [ -z "$DB_CONTAINER" ]; then
        log_error "Database container not found / Контейнер базы данных не найден"
        read -r -p "Press Enter to continue / Нажмите Enter для продолжения..."
        return 1
    fi
    
    local BACKUP_FILE="$PANEL_DIR/backups/backup_$(date +%Y%m%d_%H%M%S).sql"
    
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
        local local_domain
        local_domain=$(cat /opt/remnawave/.domain)
        echo -e "${CYAN}URL панели / Panel URL:${NC} https://$local_domain"
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
    local local_domain
    local_domain=$(cat /opt/remnawave/.domain 2>/dev/null || echo 'your-domain.com')
    echo "1. Откройте панель: https://$local_domain"
    echo "2. Создайте нового супер-админа с новым паролем"
    echo ""
    read -r -p "Нажмите Enter для возврата в меню... / Press Enter to return to menu..."
}

export -f unlock_apt install_docker download_panel_files generate_secrets configure_domain configure_gate_password setup_reverse_proxy deploy_gate_auth_service create_gate_page setup_caddy setup_nginx start_panel install_panel update_panel uninstall_panel view_logs check_status backup_db show_login_info reset_admin_password
export PANEL_DIR
