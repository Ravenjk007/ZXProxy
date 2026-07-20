#!/bin/bash
# ZXProxy Installer
REPO_URL="https://github.com/Ravenjk007/ZXProxy.git"
REPO_BRANCH="main"
CMD_NAME="zxproxy"
TOTAL_STEPS=9
CURRENT_STEP=0

show_progress() {
    PERCENT=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo "Progresso: [${PERCENT}%] - $1"
}

error_exit() {
    echo -e "\n❌ Erro: $1"
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
                24.*|22.*|20.*|18.*) show_progress "✅ Sistema Ubuntu suportado..." ;;
                *) error_exit "Versão do Ubuntu não suportada." ;;
            esac
            ;;
        Debian)
            case $VERSION in
                12*|11*|10*|9*) show_progress "✅ Sistema Debian suportado..." ;;
                *) error_exit "Versão do Debian não suportada." ;;
            esac
            ;;
        *) error_exit "Sistema não suportado." ;;
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

    show_progress "Compilando ZXProxy..."
    if [ -d "/root/ZXProxy" ]; then
        rm -rf /root/ZXProxy
    fi
    
    git clone --branch "$REPO_BRANCH" "$REPO_URL" /root/ZXProxy > /dev/null 2>&1 || error_exit "Falha ao clonar"

    cd /root/ZXProxy || error_exit "Diretório não encontrado"
    cargo build --release --jobs "$(nproc)" > /dev/null 2>&1 || error_exit "Falha ao compilar"

    if [ -f ./target/release/zxproxy ]; then
        mv ./target/release/zxproxy /opt/zxproxy/proxy
        chmod +x /opt/zxproxy/proxy
    else
        error_exit "Binário não encontrado"
    fi
    increment_step

    show_progress "Copiando menu.sh do repositório..."
    if [ -f /root/ZXProxy/menu.sh ]; then
        cp /root/ZXProxy/menu.sh /opt/zxproxy/menu.sh
        chmod +x /opt/zxproxy/menu.sh
    else
        error_exit "menu.sh não encontrado no repositório"
    fi
    increment_step

    show_progress "Criando link..."
    cp /opt/zxproxy/menu.sh /usr/local/bin/"$CMD_NAME"
    chmod +x /usr/local/bin/"$CMD_NAME"
    increment_step

    show_progress "Limpando..."
    cd /root/
    rm -rf /root/ZXProxy/
    increment_step

    echo ""
    echo -e "\033[0;32m✅ Instalação concluída!\033[0m"
    echo ""
    echo "🚀 Digite '$CMD_NAME' para acessar o menu."
    echo "   Ou '$CMD_NAME -p 80' para abrir porta 80."
    echo ""
    echo "📡 Protocolos: SOCKS5 | TLS | WebSocket | SECURITY | TCP"
    echo ""
fi
