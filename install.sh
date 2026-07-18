#!/bin/bash

echo "🔧 Instalando BSProxy Multiprotocol..."
echo "📡 Protocols: SOCKS5 + TLS/SECURITY + TCP Fallback"
echo ""

# Instalar Rust se não tiver
if ! command -v cargo &> /dev/null; then
    echo "📦 Instalando Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
fi

# Criar diretório do projeto
mkdir -p ~/BSProxy
cd ~/BSProxy

# Criar Cargo.toml
cat > Cargo.toml << 'EOF'
[package]
name = "bsproxy"
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

[[bin]]
name = "bsproxy"
path = "src/main.rs"
EOF

# Criar diretório src
mkdir -p src

# Criar main.rs (COM MENU INTEGRADO)
cat > src/main.rs << 'EOF'
mod socks5;
mod tls;
mod tcp_fallback;

use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error};
use std::process::Command;

#[derive(Parser)]
#[command(name = "bsproxy")]
#[command(about = "Multiprotocol proxy server (SOCKS5 + TLS + TCP)", long_about = None)]
struct Cli {
    #[arg(short = 'p', long = "port", default_value = "")]
    port: String,
    #[arg(short = 'd', long = "debug")]
    debug: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Se não foi passada porta, abre o menu
    if cli.port.is_empty() {
        show_menu();
        return Ok(());
    }
    
    // Se foi passada porta, inicia o proxy
    if cli.debug {
        env_logger::init();
    } else {
        env_logger::builder()
            .filter_level(log::LevelFilter::Info)
            .init();
    }
    
    let addr = format!("0.0.0.0:{}", cli.port);
    let listener = TcpListener::bind(&addr).await?;
    info!("🚀 BSProxy Multiprotocol listening on {}", addr);
    info!("📡 Protocols: SOCKS5, TLS/SECURITY, TCP Fallback");

    while let Ok((mut socket, _)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buf = [0u8; 1];
            match socket.peek(&mut buf).await {
                Ok(_) => {
                    match buf[0] {
                        0x05 => {
                            info!("🔐 SOCKS5 connection");
                            let _ = socks5::handle(socket).await;
                        }
                        0x16 => {
                            info!("🔒 TLS/SECURITY connection");
                            let _ = tls::handle(socket).await;
                        }
                        _ => {
                            info!("📦 TCP Fallback connection");
                            let _ = tcp_fallback::handle(socket).await;
                        }
                    }
                }
                Err(e) => error!("Failed to peek: {}", e),
            }
        });
    }
    Ok(())
}

fn show_menu() {
    // Verifica se o menu.sh existe no diretório atual
    let menu_path = "./menu.sh";
    if std::path::Path::new(menu_path).exists() {
        let _ = Command::new("bash")
            .arg(menu_path)
            .status();
    } else {
        // Se não encontrar, procura no diretório do projeto
        let home = std::env::var("HOME").unwrap_or_else(|_| "~".to_string());
        let menu_path2 = format!("{}/BSProxy/menu.sh", home);
        if std::path::Path::new(&menu_path2).exists() {
            let _ = Command::new("bash")
                .arg(&menu_path2)
                .status();
        } else {
            println!("❌ Menu não encontrado!");
            println!("Execute: ~/BSProxy/menu.sh");
        }
    }
}
EOF

# Criar socks5.rs (mesmo de antes)
cat > src/socks5.rs << 'EOF'
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::Result;
use log::info;

pub async fn handle(mut socket: TcpStream) -> Result<()> {
    let mut buf = [0u8; 2];
    socket.read_exact(&mut buf).await?;
    if buf[0] != 0x05 { anyhow::bail!("Invalid SOCKS version"); }
    socket.write_all(&[0x05, 0x00]).await?;
    let mut req = [0u8; 4];
    socket.read_exact(&mut req).await?;
    if req[0] != 0x05 { anyhow::bail!("Invalid SOCKS request"); }
    match req[1] {
        0x01 => handle_connect(socket).await,
        _ => anyhow::bail!("Unsupported SOCKS command"),
    }
}

async fn handle_connect(mut socket: TcpStream) -> Result<()> {
    let mut addr_type = [0u8; 1];
    socket.read_exact(&mut addr_type).await?;
    let target = match addr_type[0] {
        0x01 => {
            let mut ip = [0u8; 4];
            socket.read_exact(&mut ip).await?;
            let mut port = [0u8; 2];
            socket.read_exact(&mut port).await?;
            format!("{}:{}", 
                ip.iter().map(|b| b.to_string()).collect::<Vec<_>>().join("."),
                u16::from_be_bytes(port)
            )
        }
        0x03 => {
            let mut len = [0u8; 1];
            socket.read_exact(&mut len).await?;
            let mut domain = vec![0u8; len[0] as usize];
            socket.read_exact(&mut domain).await?;
            let mut port = [0u8; 2];
            socket.read_exact(&mut port).await?;
            format!("{}:{}", String::from_utf8_lossy(&domain), u16::from_be_bytes(port))
        }
        _ => anyhow::bail!("Unsupported address type"),
    };
    info!("SOCKS5 connecting to: {}", target);
    match TcpStream::connect(&target).await {
        Ok(mut target_stream) => {
            socket.write_all(&[0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
            let (mut reader, mut writer) = socket.into_split();
            let (mut target_reader, mut target_writer) = target_stream.into_split();
            tokio::try_join!(
                tokio::io::copy(&mut reader, &mut target_writer),
                tokio::io::copy(&mut target_reader, &mut writer)
            )?;
            Ok(())
        }
        Err(_) => {
            socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
            anyhow::bail!("Connection failed")
        }
    }
}
EOF

# Criar tls.rs
cat > src/tls.rs << 'EOF'
use tokio::net::TcpStream;
use tokio_rustls::TlsAcceptor;
use rustls::{ServerConfig, Certificate, PrivateKey};
use std::sync::Arc;
use anyhow::Result;
use log::info;

pub async fn handle(socket: TcpStream) -> Result<()> {
    info!("🔒 Establishing TLS...");
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".to_string()])?;
    let cert_der = cert.serialize_der()?;
    let key_der = cert.serialize_private_key_der();
    let config = ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(vec![Certificate(cert_der)], PrivateKey(key_der))?;
    let acceptor = TlsAcceptor::from(Arc::new(config));
    let mut tls_stream = acceptor.accept(socket).await?;
    info!("🔒 TLS handshake complete!");
    let mut buf = [0u8; 1024];
    loop {
        match tls_stream.read(&mut buf).await {
            Ok(0) => break,
            Ok(n) => {
                let msg = String::from_utf8_lossy(&buf[..n]);
                let response = format!("SECURE: {}", msg);
                tls_stream.write_all(response.as_bytes()).await?;
            }
            Err(e) => anyhow::bail!("TLS error: {}", e),
        }
    }
    Ok(())
}
EOF

# Criar tcp_fallback.rs
cat > src/tcp_fallback.rs << 'EOF'
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::Result;
use log::info;

pub async fn handle(mut socket: TcpStream) -> Result<()> {
    info!("📦 TCP Fallback: echo");
    let mut buf = [0u8; 1024];
    loop {
        match socket.read(&mut buf).await {
            Ok(0) => break,
            Ok(n) => {
                let msg = String::from_utf8_lossy(&buf[..n]);
                let response = format!("TCP: {}", msg);
                socket.write_all(response.as_bytes()).await?;
            }
            Err(e) => anyhow::bail!("TCP error: {}", e),
        }
    }
    Ok(())
}
EOF

# Criar menu.sh (QBSManager)
cat > menu.sh << 'EOF'
#!/bin/bash
BSPROXY="./target/release/bsproxy"
PID_FILE="/tmp/bsproxy_"

show_menu() {
    clear
    echo "====================================="
    echo "          QBSManager                 "
    echo "====================================="
    echo "          BSPROXY                    "
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
    echo "🔓 Abrindo porta ${PORT} com multiprotocolo..."
    if [ ! -f "$BSPROXY" ]; then
        echo "📦 Compilando..."
        cargo build --release
    fi
    nohup ${BSPROXY} -p ${PORT} > "/tmp/bsproxy_${PORT}.log" 2>&1 &
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 2
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo "✅ Porta ${PORT} aberta!"
        echo "📋 Log: /tmp/bsproxy_${PORT}.log"
        echo ""
        echo "🧪 Teste SOCKS5: curl --socks5 localhost:${PORT} http://example.com"
        echo "🧪 Teste TLS: openssl s_client -connect localhost:${PORT}"
    else
        echo "❌ Falha ao abrir porta ${PORT}!"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    sleep 3
}

close_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        kill -9 $(cat "${PID_FILE}${PORT}.pid") 2>/dev/null
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
EOF

chmod +x menu.sh

# Compilar
echo "📦 Compilando BSProxy..."
cargo build --release

# Instalar globalmente
if [ -f "./target/release/bsproxy" ]; then
    cp ./target/release/bsproxy /usr/local/bin/
    chmod +x /usr/local/bin/bsproxy
    echo "✅ bsproxy instalado globalmente!"
fi

echo ""
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo ""
echo "🚀 Comandos:"
echo "   bsproxy              # Abre o menu interativo"
echo "   bsproxy -p 80        # Abre porta 80 diretamente"
echo "   ./menu.sh            # Menu interativo (alternativo)"
echo ""
echo "🧪 Testes:"
echo "   curl --socks5 localhost:80 http://example.com"
echo "   openssl s_client -connect localhost:80"
echo "   telnet localhost 80"
