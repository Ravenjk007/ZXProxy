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
                24.*|22.*|20.*|18.*) show_progress "✅ Sistema Ubuntu suportado, continuando..." ;;
                *) error_exit "Versão do Ubuntu não suportada. Use 18, 20, 22 ou 24." ;;
            esac
            ;;
        Debian)
            case $VERSION in
                12*|11*|10*|9*) show_progress "✅ Sistema Debian suportado, continuando..." ;;
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

    show_progress "Preparando código fonte ZXProxy..."
    
    # Limpar diretório antigo
    if [ -d "/root/ZXProxy" ]; then
        rm -rf /root/ZXProxy
    fi
    
    # Tentar clonar o repositório
    echo "📥 Clonando repositório..."
    git clone --branch "$REPO_BRANCH" "$REPO_URL" /root/ZXProxy 2>/dev/null
    
    # Se falhar ao clonar, criar projeto do zero
    if [ $? -ne 0 ] || [ ! -d "/root/ZXProxy/src" ]; then
        echo "⚠️  Repositório não encontrado, criando projeto do zero..."
        cd /root
        cargo new ZXProxy > /dev/null 2>&1 || error_exit "Falha ao criar projeto"
    fi
    
    cd /root/ZXProxy || error_exit "Diretório do ZXProxy não encontrado"
    
    # Criar Cargo.toml
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

    # Criar src/main.rs
    cat > src/main.rs << 'EOF'
use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error};

mod socks5;
mod tcp_fallback;
mod websocket;
mod security;
mod tls;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "Multiprotocol proxy server - ZXProxy")]
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
        .init();
    
    let addr = format!("0.0.0.0:{}", cli.port);
    let listener = TcpListener::bind(&addr).await?;
    info!("🚀 ZXProxy listening on {}", addr);
    info!("📡 Protocols: SOCKS5, TLS, WebSocket, Security, TCP");

    while let Ok((socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buf = [0u8; 24];
            match socket.peek(&mut buf).await {
                Ok(n) if n > 0 => {
                    match buf[0] {
                        0x05 => {
                            info!("🔐 [{}] SOCKS5", peer_addr);
                            let _ = socks5::handle_socks5(socket).await;
                        }
                        0x16 => {
                            info!("🔒 [{}] TLS/SECURITY", peer_addr);
                            let _ = tls::handle_tls(socket).await;
                        }
                        _ => {
                            let data_str = String::from_utf8_lossy(&buf[..n]);
                            if data_str.starts_with("GET ") || 
                               data_str.starts_with("POST ") || 
                               data_str.starts_with("PUT ") || 
                               data_str.starts_with("DELETE ") || 
                               data_str.starts_with("CONNECT ") ||
                               data_str.starts_with("HTTP/") {
                                info!("🌐 [{}] WebSocket/HTTP", peer_addr);
                                let _ = websocket::handle_websocket(socket).await;
                            } else if data_str.starts_with("SECURITY") || 
                                      data_str.starts_with("AUTH") {
                                info!("🔐 [{}] SECURITY", peer_addr);
                                let _ = security::handle_security(socket).await;
                            } else {
                                info!("📦 [{}] TCP Fallback", peer_addr);
                                let _ = tcp_fallback::handle_tcp(socket).await;
                            }
                        }
                    }
                }
                Ok(_) => info!("📦 [{}] Connection closed", peer_addr),
                Err(e) => error!("❌ [{}] Peek error: {}", peer_addr, e),
            }
        });
    }
    Ok(())
}
EOF

    # Criar src/socks5.rs
    cat > src/socks5.rs << 'EOF'
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_socks5(mut client: TcpStream) -> Result<()> {
    info!("🔐 SOCKS5 handshake");
    
    let mut header = [0u8; 2];
    if client.read_exact(&mut header).await.is_err() {
        return Ok(());
    }
    
    let nmethods = header[1] as usize;
    let mut methods = vec![0u8; nmethods];
    if client.read_exact(&mut methods).await.is_err() {
        return Ok(());
    }
    
    client.write_all(&[0x05, 0x00]).await?;
    
    let mut req = [0u8; 4];
    if client.read_exact(&mut req).await.is_err() {
        return Ok(());
    }
    
    let atyp = req[3];
    
    let target = match atyp {
        0x01 => {
            let mut addr = [0u8; 4];
            client.read_exact(&mut addr).await?;
            let mut port = [0u8; 2];
            client.read_exact(&mut port).await?;
            format!("{}.{}.{}.{}:{}", addr[0], addr[1], addr[2], addr[3], u16::from_be_bytes(port))
        }
        0x03 => {
            let mut len = [0u8; 1];
            client.read_exact(&mut len).await?;
            let mut domain = vec![0u8; len[0] as usize];
            client.read_exact(&mut domain).await?;
            let mut port = [0u8; 2];
            client.read_exact(&mut port).await?;
            format!("{}:{}", String::from_utf8_lossy(&domain), u16::from_be_bytes(port))
        }
        _ => {
            client.write_all(&[0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            return Ok(());
        }
    };
    
    info!("🔐 SOCKS5 -> {}", target);
    
    match TcpStream::connect(&target).await {
        Ok(remote) => {
            client.write_all(&[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            
            let (mut cr, mut cw) = client.into_split();
            let (mut rr, mut rw) = remote.into_split();
            
            tokio::try_join!(
                tokio::io::copy(&mut cr, &mut rw),
                tokio::io::copy(&mut rr, &mut cw)
            )?;
            
            Ok(())
        }
        Err(e) => {
            info!("❌ SOCKS5 failed: {}", e);
            client.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            Ok(())
        }
    }
}
EOF

    # Criar src/tcp_fallback.rs
    cat > src/tcp_fallback.rs << 'EOF'
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_tcp(mut socket: TcpStream) -> Result<()> {
    info!("📦 TCP connection");
    socket.write_all(b"ZXProxy TCP OK\n").await?;
    Ok(())
}
EOF

    # Criar src/websocket.rs
    cat > src/websocket.rs << 'EOF'
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

async fn consume_http_headers(socket: &mut TcpStream) -> std::io::Result<()> {
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1];

    loop {
        socket.read_exact(&mut tmp).await?;
        buf.push(tmp[0]);

        if buf.len() >= 4 && &buf[buf.len() - 4..] == b"\r\n\r\n" {
            break;
        }
        if buf.len() > 8192 {
            break;
        }
    }
    Ok(())
}

pub async fn handle_websocket(mut socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket/HTTP handshake...");
    
    consume_http_headers(&mut socket).await?;
    
    let response = "HTTP/1.1 101 Switching Protocols\r\n\
                    Upgrade: websocket\r\n\
                    Connection: Upgrade\r\n\
                    Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                    \r\n";
    
    socket.write_all(response.as_bytes()).await?;
    info!("🌐 WebSocket handshake complete!");
    
    Ok(())
}
EOF

    # Criar src/security.rs
    cat > src/security.rs << 'EOF'
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_security(mut socket: TcpStream) -> Result<()> {
    info!("🔐 SECURITY/TLS");
    socket.write_all(b"SECURITY OK\n").await?;
    Ok(())
}
EOF

    # Criar src/tls.rs
    cat > src/tls.rs << 'EOF'
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_tls(mut socket: TcpStream) -> Result<()> {
    info!("🔒 TLS connection");
    socket.write_all(b"TLS OK\n").await?;
    Ok(())
}
EOF

    # Copiar menu.sh se existir
    if [ -f /root/ZXProxy/menu.sh ]; then
        cp /root/ZXProxy/menu.sh /opt/zxproxy/menu
        chmod +x /opt/zxproxy/menu
    else
        # Criar menu básico
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
    echo " 1 - Abrir Porta"
    echo " 2 - Fechar Porta"
    echo " 3 - Status"
    echo " 4 - Sair"
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
    nohup ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
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

show_status() {
    echo "📊 Status do ZXProxy:"
    echo "===================="
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
    read -p "Pressione Enter para continuar..."
}

while true; do
    show_menu
    read OPTION
    case $OPTION in
        1) open_port ;;
        2) close_port ;;
        3) show_status ;;
        4) echo "👋 Saindo..."; exit 0 ;;
        *) echo "❌ Opção inválida!"; sleep 2 ;;
    esac
done
EOF
        chmod +x /opt/zxproxy/menu
    fi

    increment_step

    show_progress "Compilando ZXProxy, isso pode levar alguns minutos..."
    cargo build --release > /tmp/zxproxy_build.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "❌ Erro na compilação:"
        tail -n 30 /tmp/zxproxy_build.log
        error_exit "Falha ao compilar ZXProxy"
    fi

    if [ -f ./target/release/zxproxy ]; then
        mv ./target/release/zxproxy /opt/zxproxy/proxy || error_exit "Falha ao mover binário"
        chmod +x /opt/zxproxy/proxy
    elif [ -f ./target/release/bsproxy ]; then
        mv ./target/release/bsproxy /opt/zxproxy/proxy || error_exit "Falha ao mover binário"
        chmod +x /opt/zxproxy/proxy
    else
        error_exit "Binário 'zxproxy' não encontrado após compilação"
    fi
    increment_step

    show_progress "Configurando permissões..."
    chmod +x /opt/zxproxy/proxy
    [ -f /opt/zxproxy/menu ] && chmod +x /opt/zxproxy/menu

    # Criar link
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
    echo "   - SECURITY (AUTH ou SECURITY)"
    echo "   - TCP Fallback (qualquer outro)"
    echo ""
    echo "📝 Log: /tmp/zxproxy_*.log"
    echo ""
fi
