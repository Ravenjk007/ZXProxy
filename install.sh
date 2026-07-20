#!/bin/bash
# ZXProxy Installer - VPN Optimized with Keep-Alive
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

    show_progress "Compilando ZXProxy (com Keep-Alive)..."
    
    cd /root
    rm -rf ZXProxy
    cargo new ZXProxy > /dev/null 2>&1 || error_exit "Falha ao criar projeto"
    cd ZXProxy

    cat > Cargo.toml << 'EOF'
[package]
name = "zxproxy"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.35", features = ["full"] }
anyhow = "1.0"
log = "0.4"
env_logger = "0.10"
clap = { version = "4.4", features = ["derive"] }

[[bin]]
name = "zxproxy"
path = "src/main.rs"
EOF

    cat > src/main.rs << 'EOF'
use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error};
use std::time::Duration;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "ZXProxy - VPN/HTTP Inject Optimized")]
struct Cli {
    #[arg(short = 'p', long = "port", default_value = "8080")]
    port: u16,
    #[arg(short = 'd', long = "debug")]
    debug: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    env_logger::builder()
        .filter_level(if cli.debug { 
            log::LevelFilter::Debug 
        } else { 
            log::LevelFilter::Info 
        })
        .format_timestamp_millis()
        .init();
    
    let addr = format!("0.0.0.0:{}", cli.port);
    info!("🚀 ZXProxy listening on {}", addr);
    info!("📡 VPN Mode: 200 OK + Keep-Alive Forever");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buffer = [0u8; 4096];
            
            match socket.read(&mut buffer).await {
                Ok(n) if n > 0 => {
                    let request = String::from_utf8_lossy(&buffer[..n]);
                    let first_line = request.lines().next().unwrap_or("");
                    info!("📩 [{}] {}", peer_addr, first_line);
                    
                    let is_websocket = request.to_lowercase().contains("upgrade: websocket") ||
                                       request.to_lowercase().contains("sec-websocket-key");
                    
                    if is_websocket {
                        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                                        Upgrade: websocket\r\n\
                                        Connection: Upgrade\r\n\
                                        Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                                        \r\n";
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 101 WebSocket - Keep-Alive", peer_addr);
                    } else {
                        let response = "HTTP/1.1 200 OK\r\n\
                                        Content-Type: text/plain\r\n\
                                        Content-Length: 2\r\n\
                                        Connection: keep-alive\r\n\
                                        Server: ZXProxy\r\n\
                                        \r\n\
                                        OK";
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 200 OK - Keep-Alive", peer_addr);
                    }
                    
                    // MANTER CONEXÃO VIVA PARA SEMPRE!
                    let mut interval = tokio::time::interval(Duration::from_secs(25));
                    loop {
                        interval.tick().await;
                        let _ = socket.write_all(b"\r\n").await;
                        info!("💓 [{}] Keep-alive", peer_addr);
                    }
                }
                Ok(_) => info!("📦 [{}] Empty", peer_addr),
                Err(e) => error!("❌ [{}] Error: {}", peer_addr, e),
            }
        });
    }
    Ok(())
}
EOF

    cargo build --release > /tmp/zxproxy_build.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "❌ Erro na compilação:"
        tail -n 30 /tmp/zxproxy_build.log
        error_exit "Falha ao compilar"
    fi

    if [ -f ./target/release/zxproxy ]; then
        mv ./target/release/zxproxy /opt/zxproxy/proxy
    else
        error_exit "Binário não encontrado"
    fi
    
    chmod +x /opt/zxproxy/proxy
    increment_step

    show_progress "Configurando permissões..."
    chmod +x /opt/zxproxy/proxy

    # Menu
    cat > /opt/zxproxy/menu << 'EOF'
#!/bin/bash
ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"

show_menu() {
    clear
    echo "====================================="
    echo "          ZXProxy Menu              "
    echo "====================================="
    echo ""
    ACTIVE_PORTS=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
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
    echo " 1 - Abrir Porta (Keep-Alive)"
    echo " 2 - Fechar Porta"
    echo " 3 - Status"
    echo " 4 - Ver Logs"
    echo " 5 - Sair"
    echo ""
    echo -n "--> "
}

open_port() {
    read -p "Digite a porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        echo "❌ Porta já aberta!"
        sleep 2
        return
    fi
    echo "🔓 Abrindo porta ${PORT}..."
    
    sudo fuser -k $PORT/tcp 2>/dev/null
    
    if [ "$PORT" -lt 1024 ]; then
        nohup sudo ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    else
        nohup ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    fi
    
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 2
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo "✅ Porta ${PORT} aberta com Keep-Alive!"
        echo "📝 Log: /tmp/zxproxy_${PORT}.log"
    else
        echo "❌ Falha!"
        rm -f "${PID_FILE}${PORT}.pid"
        tail -n 5 "/tmp/zxproxy_${PORT}.log"
    fi
    sleep 2
}

close_port() {
    read -p "Digite a porta: " PORT
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        sudo kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo "✅ Porta ${PORT} fechada!"
    else
        echo "❌ Porta não está aberta!"
    fi
    sleep 2
}

show_status() {
    echo "📊 Status:"
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            PID=$(cat "$pidfile")
            if ps -p $PID > /dev/null 2>&1; then
                echo "✅ Porta $PORT: ativa (PID: $PID)"
            fi
        fi
    done
    echo ""
    read -p "Enter..."
}

show_logs() {
    echo "📝 Logs:"
    tail -n 20 /tmp/zxproxy_*.log 2>/dev/null || echo "Nenhum log"
    echo ""
    read -p "Enter..."
}

while true; do
    show_menu
    read OPTION
    case $OPTION in
        1) open_port ;;
        2) close_port ;;
        3) show_status ;;
        4) show_logs ;;
        5) echo "👋 Saindo..."; exit 0 ;;
        *) echo "❌ Inválido!"; sleep 2 ;;
    esac
done
EOF

    chmod +x /opt/zxproxy/menu
    ln -sf /opt/zxproxy/menu /usr/local/bin/"$CMD_NAME"
    chmod +x /usr/local/bin/"$CMD_NAME"
    increment_step

    show_progress "Limpando..."
    cd /root/
    rm -rf /root/ZXProxy/
    increment_step

    echo ""
    echo -e "\033[0;32m✅ Instalação concluída!\033[0m"
    echo ""
    echo "🚀 Digite 'zxproxy' para o menu"
    echo ""
    echo "📡 AGORA COM KEEP-ALIVE!"
    echo "   A conexão NÃO será fechada após responder"
    echo "   O app VPN vai conseguir manter o túnel SSH"
    echo ""
fi
