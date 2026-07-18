#!/bin/bash
# BSProxy Installer
REPO_URL="https://github.com/Ravenjk007/BSProxy.git"
REPO_BRANCH="main"

echo "🔧 Instalando BSProxy..."

# Instalar dependências
apt update -y
apt install curl build-essential git -y

# Instalar Rust
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Clonar e compilar
rm -rf /root/BSProxy
git clone --branch "$REPO_BRANCH" "$REPO_URL" /root/BSProxy
cd /root/BSProxy
cargo build --release

# Instalar
mkdir -p /opt/bsproxy
cp ./target/release/bsproxy /opt/bsproxy/proxy
chmod +x /opt/bsproxy/proxy

# Copiar menu se existir
if [ -f /root/BSProxy/menu.sh ]; then
    cp /root/BSProxy/menu.sh /opt/bsproxy/menu
    chmod +x /opt/bsproxy/menu
fi

# Se não tiver menu, criar um padrão
if [ ! -f /opt/bsproxy/menu ]; then
    cat > /opt/bsproxy/menu << 'MENUEOF'
#!/bin/bash
BSPROXY="/opt/bsproxy/proxy"
PID_FILE="/tmp/bsproxy_"

show_menu() {
    clear
    echo "====================================="
    echo "          BSProxy Menu              "
    echo "====================================="
    echo ""
    ACTIVE_PORTS=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/bsproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                ACTIVE_PORTS="$ACTIVE_PORTS $PORT"
            else
                rm -f "$pidfile"
            fi
        fi
    done
    if [ -n "$ACTIVE_PORTS" ]; then
        echo "Porta(s) aberta(s):$ACTIVE_PORTS"
    else
        echo "Porta(s): nenhuma"
    fi
    echo ""
    echo " 1 - Abrir Porta"
    echo " 2 - Fechar Porta"
    echo " 3 - Sair"
    echo ""
    echo -n "--> Selecione uma opção: "
}

open_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        echo "❌ Porta ${PORT} já está aberta!"
        sleep 2
        return
    fi
    echo "🔓 Abrindo porta ${PORT}..."
    if [ ! -f "$BSPROXY" ]; then
        echo "❌ BSProxy não encontrado!"
        sleep 3
        return
    fi
    nohup ${BSPROXY} -p ${PORT} > "/tmp/bsproxy_${PORT}.log" 2>&1 &
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 2
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo "✅ Porta ${PORT} aberta!"
    else
        echo "❌ Falha!"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    sleep 2
}

close_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo "✅ Porta ${PORT} fechada!"
    else
        echo "❌ Porta ${PORT} não está aberta!"
    fi
    sleep 2
}

while true; do
    show_menu
    read OPTION
    case $OPTION in
        1) open_port ;;
        2) close_port ;;
        3) echo "👋 Saindo..."; exit 0 ;;
        *) echo "❌ Opção inválida!"; sleep 2 ;;
    esac
done
MENUEOF
    chmod +x /opt/bsproxy/menu
fi

# Criar comando
if [ -f /opt/bsproxy/menu ]; then
    cp /opt/bsproxy/menu /usr/local/bin/bsproxy
else
    cp /opt/bsproxy/proxy /usr/local/bin/bsproxy
fi
chmod +x /usr/local/bin/bsproxy

# Limpar
rm -rf /root/BSProxy

echo ""
echo "✅ Instalação concluída!"
echo "🚀 Digite 'bsproxy' para acessar o menu."
echo "   Ou 'bsproxy -p 80' para abrir porta 80."
