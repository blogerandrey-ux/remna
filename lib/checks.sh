#!/bin/bash

check_root() {
    # Используем [[ ]] для более безопасного сравнения в bash
    if [[ $EUID -ne 0 ]]; then
        log_error "Please run as root / Пожалуйста, запустите от root"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "Cannot detect OS / Не удалось определить ОС"
        exit 1
    fi
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_warn "Recommended OS: Ubuntu 20.04+ or Debian 11+ / Рекомендуется Ubuntu 20.04+ или Debian 11+"
        # ИСПРАВЛЕНИЕ: добавлен флаг -r и проверка на заглавную Y
        read -r -p "Continue? / Продолжить? (y/n) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            exit 1
        fi
    fi
    
    log_info "OS: $OS $VER"
}

# НОВАЯ ФУНКЦИЯ: Проверка базового подключения к интернету перед скачиванием
check_dns() {
    log_info "Проверка подключения к интернету (github.com)..."
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_warn "Нет доступа к github.com. Проверьте DNS или подключение к интернету."
        read -r -p "Continue anyway? / Продолжить в любом случае? (y/n) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            exit 1
        fi
    else
        log_success "Подключение к интернету установлено"
    fi
}

check_docker() {
    # ИСПРАВЛЕНИЕ: замена &> на >/dev/null 2>&1 (предпочтительнее для shellcheck)
    # Также добавлена проверка docker info, чтобы убедиться, что демон действительно запущен
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        log_success "$(t 'docker_installed')"
        DOCKER_INSTALLED=true
    else
        DOCKER_INSTALLED=false
    fi
    
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_INSTALLED=true
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_INSTALLED=true
    else
        COMPOSE_INSTALLED=false
    fi
    
    export DOCKER_INSTALLED COMPOSE_INSTALLED
}

# Не забываем экспортировать новую функцию check_dns
export -f check_root check_os check_dns check_docker
