#!/bin/bash

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root / Пожалуйста, запустите от root"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "Cannot detect OS / Не удалось определить ОС"
        exit 1
    fi
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_warn "Recommended OS: Ubuntu 20.04+ or Debian 11+ / Рекомендуется Ubuntu 20.04+ или Debian 11+"
        read -p "Continue? / Продолжить? (y/n) " confirm
        if [ "$confirm" != "y" ]; then
            exit 1
        fi
    fi
    
    log_info "OS: $OS $VER"
}

check_docker() {
    if command -v docker &> /dev/null; then
        log_success "$(t 'docker_installed')"
        DOCKER_INSTALLED=true
    else
        DOCKER_INSTALLED=false
    fi
    
    if command -v docker-compose &> /dev/null; then
        COMPOSE_INSTALLED=true
    elif docker compose version &> /dev/null; then
        COMPOSE_INSTALLED=true
    else
        COMPOSE_INSTALLED=false
    fi
    
    export DOCKER_INSTALLED COMPOSE_INSTALLED
}

export -f check_root check_os check_docker
