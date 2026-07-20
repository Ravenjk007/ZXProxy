#!/bin/bash
# install.sh - ZXProxy Installer
REPO_URL="https://github.com/Ravenjk007/BSProxy.git"
REPO_BRANCH="main"
CMD_NAME="zxproxy"
TOTAL_STEPS=9
CURRENT_STEP=0

show_progress() {
    PERCENT=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo "Progresso: [${PERCENT}%] - $1"
}

error_exit() {
    echo -e "\nErro: $1"
    exit 1
}

increment_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
}

if [ "$EUID" -ne 0 ]; then
    error_exit "EXECUTE COMO ROOT"
else
    clear
    show_progress "Atualizando repositorios..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y > /dev/null 2>&1 || error_exit "Falha ao atualizar os repositorios"
    increment_step

    show_progress "Verificando o sistema..."
    if ! command -v lsb_release &> /dev/null; then
        apt install lsb-release -y > /dev/null 2>&1 || error_exit "Falha ao instalar lsb-release"
    fi
    increment_step

    OS_NAME=$(lsb_release -is)
    VERSION=$(lsb_release -rs)
    case $OS_NAME in
        Ubuntu)
            case $VERSION in
                24.*|22.*|20.*|18.*) show_progress "Sistema Ubuntu suportado, continuando..." ;;
                *) error_exit "Versão do Ubuntu não suportada. Use 18, 20, 22 ou 24." ;;
            esac
            ;;
        Debian)
            case $VERSION in
                12*|11*|10*|9*) show_progress "Sistema Debian suportado, continuando..." ;;
                *) error_exit "Versão do Debian não suportada. Use 9, 10, 11 ou 12." ;;
            esac
            ;;
        *) error_exit "Sistema não suportado. Use Ubuntu ou Debian." ;;
    esac
    increment_step

    show_progress "Atualizando o sistema..."
    apt upgrade -y > /dev/null 2>&1 || error_exit "Falha ao atualizar o sistema"
    apt-get install curl build-essential git -y > /dev/null 2>&1 || error_exit "Falha ao instalar pacotes"
    increment_step

    show_progress "Criando diretorio /opt/zxproxy..."
    mkdir -p /opt/zxproxy > /dev/null 2>&1
    increment_step

    show_progress "Instalando Rust..."
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y > /dev/null 2>&1 || error_exit "Falha ao instalar Rust"
        source "$HOME/.cargo/env"
    fi
    increment_step

    show_progress "Compilando ZXProxy, isso pode levar algum tempo..."
    if [ -d "/root/ZXProxy" ]; then
        rm -rf /root/ZXProxy
    fi
    git clone --branch "$REPO_BRANCH" "$REPO_URL" /root/ZXProxy > /dev/null 2>&1 || error_exit "Falha ao clonar ZXProxy"

    if [ -f /root/ZXProxy/menu.sh ]; then
        cp /root/ZXProxy/menu.sh /opt/zxproxy/menu
        chmod +x /opt/zxproxy/menu
    fi

    cd /root/ZXProxy || error_exit "Diretório do ZXProxy não encontrado"
    cargo build --release --jobs "$(nproc)" > /dev/null 2>&1 || error_exit "Falha ao compilar ZXProxy"

    if [ -f ./target/release/zxproxy ]; then
        mv ./target/release/zxproxy /opt/zxproxy/proxy || error_exit "Binário compilado não encontrado"
        chmod +x /opt/zxproxy/proxy
    else
        error_exit "Binário 'zxproxy' não encontrado após compilação"
    fi
    increment_step

    show_progress "Configurando permissões..."
    chmod +x /opt/zxproxy/proxy
    [ -f /opt/zxproxy/menu ] && chmod +x /opt/zxproxy/menu

    # Criar o link usando cp (mais confiável)
    if [ -f /opt/zxproxy/menu ]; then
        cp /opt/zxproxy/menu /usr/local/bin/zxproxy
    else
        cp /opt/zxproxy/proxy /usr/local/bin/zxproxy
    fi
    chmod +x /usr/local/bin/zxproxy
    increment_step

    show_progress "Limpando diretórios temporários..."
    cd /root/
    rm -rf /root/ZXProxy/
    increment_step

    echo ""
    echo -e "\033[0;32m✅ Instalação concluída com sucesso!\033[0m"
    echo ""
    echo "🚀 Digite 'zxproxy' para acessar o menu."
    echo "   Ou 'zxproxy -p 80' para abrir porta 80 diretamente."
    echo ""
    echo "📡 Protocolos suportados:"
    echo "   - SOCKS5 (byte 0x05)"
    echo "   - TLS/SECURITY (byte 0x16)"
    echo "   - WebSocket (GET / ou HTTP/)"
    echo "   - HTTP (GET, POST, PUT, DELETE, etc)"
    echo "   - HTTPS (TLS/SSL)"
    echo "   - SSH Tunnel (SSH-)"
    echo "   - VPN (OpenVPN, WireGuard, IPSec, L2TP)"
    echo "   - SECURITY (AUTH ou SECURITY)"
    echo "   - TCP Fallback (qualquer outro)"
    echo ""
    echo "📊 Métricas: http://localhost:9090/metrics"
    echo ""
fi
