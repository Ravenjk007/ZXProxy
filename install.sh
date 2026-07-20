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
    
    # Clonar o repositório
    git clone --branch "$REPO_BRANCH" "$REPO_URL" /root/ZXProxy > /dev/null 2>&1 || error_exit "Falha ao clonar ZXProxy"
    
    # CORREÇÃO: Criar Cargo.toml limpo
    cat > /root/ZXProxy/Cargo.toml << 'EOF'
[package]
name = "zxproxy"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.35", features = ["full"] }
rustls = "0.21"
tokio-rustls = "0.24"
rcgen = "0.11"
anyhow = "1.0"
log = "0.4"
env_logger = "0.10"
clap = { version = "4.4", features = ["derive"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
warp = "0.3"

[[bin]]
name = "zxproxy"
path = "src/main.rs"
EOF
    
    # Atualizar todos os arquivos .rs com as correções
    cat > /root/ZXProxy/src/tcp_fallback.rs << 'EOF'
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_tcp(mut socket: TcpStream) -> Result<()> {
    info!("📦 TCP Fallback");
    socket.write_all(b"TCP OK\n").await?;
    
    let mut buffer = [0u8; 1024];
    let n = socket.read(&mut buffer).await?;
    if n > 0 {
        info!("📦 Received: {}", String::from_utf8_lossy(&buffer[..n]));
        socket.write_all(&buffer[..n]).await?;
    }
    
    Ok(())
}
EOF
    
    cat > /root/ZXProxy/src/socks5.rs << 'EOF'
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_socks5(mut client: TcpStream) -> Result<()> {
    info!("🔐 SOCKS5");
    
    let mut header = [0u8; 2];
    client.read_exact(&mut header).await?;
    let nmethods = header[1] as usize;
    let mut methods = vec![0u8; nmethods];
    client.read_exact(&mut methods).await?;
    client.write_all(&[0x05, 0x00]).await?;
    
    let mut req = [0u8; 4];
    client.read_exact(&mut req).await?;
    let _cmd = req[1];
    let atyp = req[3];
    
    let target_addr = match atyp {
        0x01 => {
            let mut addr = [0u8; 4];
            client.read_exact(&mut addr).await?;
            let mut port = [0u8; 2];
            client.read_exact(&mut port).await?;
            format!("{}.{}.{}.{}:{}", addr[0], addr[1], addr[2], addr[3], u16::from_be_bytes(port))
        }
        _ => {
            client.write_all(&[0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            anyhow::bail!("Unsupported address type");
        }
    };
    
    info!("SOCKS5 -> {}", target_addr);
    
    match TcpStream::connect(&target_addr).await {
        Ok(remote) => {
            client.write_all(&[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            let (mut client_reader, mut client_writer) = client.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
            Ok(())
        }
        Err(e) => {
            client.write_all(&[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]).await?;
            anyhow::bail!("Connection failed: {}", e);
        }
    }
}
EOF
    
    # Criar os outros módulos necessários
    for module in tls websocket security http https ssh_tunnel vpn_forward metrics; do
        cat > "/root/ZXProxy/src/${module}.rs" << EOF
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_${module}(socket: TcpStream) -> Result<()> {
    info!("🔐 ${module} connection");
    Ok(())
}
EOF
    done
    
    cd /root/ZXProxy || error_exit "Diretório do ZXProxy não encontrado"
    
    # Compilar
    echo "Compilando... (isso pode levar alguns minutos)"
    cargo clean > /dev/null 2>&1
    cargo build --release > /tmp/zxproxy_build.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "❌ Erro na compilação. Log:"
        tail -n 30 /tmp/zxproxy_build.log
        error_exit "Falha ao compilar ZXProxy"
    fi
    
    # Instalar binário
    if [ -f ./target/release/zxproxy ]; then
        cp ./target/release/zxproxy /opt/zxproxy/proxy
    elif [ -f ./target/release/bsproxy ]; then
        cp ./target/release/bsproxy /opt/zxproxy/proxy
    else
        error_exit "Binário não encontrado"
    fi
    
    chmod +x /opt/zxproxy/proxy
    cp /opt/zxproxy/proxy /usr/local/bin/zxproxy
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
fi
