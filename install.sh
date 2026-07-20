#!/bin/bash
# ZXProxy - VPN Optimized Installer

echo "🚀 Instalando ZXProxy otimizado para VPN..."

# Parar processos antigos
sudo pkill -9 zxproxy 2>/dev/null
sudo pkill -9 proxy 2>/dev/null
sudo fuser -k 80/tcp 2>/dev/null
sudo fuser -k 8080/tcp 2>/dev/null
sudo rm -f /tmp/*proxy*.pid 2>/dev/null

# Instalar dependências
sudo apt update -y
sudo apt install -y curl build-essential git

# Instalar Rust
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Criar projeto
cd /root
rm -rf ZXProxy
cargo new ZXProxy
cd ZXProxy

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
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error};

mod socks5;
mod tcp_fallback;
mod websocket;
mod security;
mod tls;
mod http_handler;

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
        .format_timestamp_millis()
        .init();
    
    let addr = format!("0.0.0.0:{}", cli.port);
    info!("🚀 ZXProxy listening on {}", addr);
    info!("📡 Protocols: SOCKS5, TLS, WebSocket, HTTP, Security, TCP");
    info!("💡 VPN Mode: Accepting any HTTP request with 200 OK");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((socket, peer_addr)) = listener.accept().await {
        let peer = peer_addr;
        tokio::spawn(async move {
            if let Err(e) = handle_connection(socket, peer).await {
                error!("❌ [{}] Error: {}", peer, e);
            }
        });
    }
    Ok(())
}

async fn handle_connection(mut socket: tokio::net::TcpStream, peer_addr: std::net::SocketAddr) -> Result<()> {
    let mut buf = [0u8; 1024];
    let n = socket.peek(&mut buf).await?;
    
    if n == 0 {
        info!("📦 [{}] Connection closed", peer_addr);
        return Ok(());
    }
    
    let protocol = detect_protocol(&buf[..n]);
    info!("📡 [{}] Protocol: {}", peer_addr, protocol);
    
    match protocol {
        "HTTP" => http_handler::handle_http(socket, peer_addr).await?,
        "WEBSOCKET" => websocket::handle_websocket(socket).await?,
        "SOCKS5" => socks5::handle_socks5(socket).await?,
        "TLS" => tls::handle_tls(socket).await?,
        "SECURITY" => security::handle_security(socket).await?,
        _ => tcp_fallback::handle_tcp(socket).await?,
    }
    
    Ok(())
}

fn detect_protocol(data: &[u8]) -> &'static str {
    if data.is_empty() { return "UNKNOWN"; }
    
    if let Ok(text) = std::str::from_utf8(data) {
        let text_lower = text.to_lowercase();
        
        if text_lower.contains("upgrade: websocket") || text_lower.contains("sec-websocket-key") {
            return "WEBSOCKET";
        }
        
        if text.starts_with("GET ") || text.starts_with("POST ") || 
           text.starts_with("PUT ") || text.starts_with("DELETE ") || 
           text.starts_with("CONNECT ") || text.starts_with("HEAD ") ||
           text.starts_with("OPTIONS ") || text.starts_with("PATCH ") ||
           text.contains("HTTP/") {
            return "HTTP";
        }
        
        if text.starts_with("SECURITY") || text.starts_with("AUTH") {
            return "SECURITY";
        }
    }
    
    if data.len() >= 1 && data[0] == 0x05 { return "SOCKS5"; }
    if data.len() >= 3 && data[0] == 0x16 { return "TLS"; }
    
    "TCP"
}
EOF

# Criar src/http_handler.rs
cat > src/http_handler.rs << 'EOF'
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::{info, debug};

pub async fn handle_http(mut socket: TcpStream, peer_addr: std::net::SocketAddr) -> Result<()> {
    info!("🌐 [{}] HTTP Request", peer_addr);
    
    let mut buffer = vec![0u8; 8192];
    let n = socket.read(&mut buffer).await?;
    
    if n == 0 { return Ok(()); }
    
    let request_str = String::from_utf8_lossy(&buffer[..n]);
    debug!("📩 [{}] Request: {}", peer_addr, request_str.lines().next().unwrap_or(""));
    
    // Verificar WebSocket
    if request_str.to_lowercase().contains("upgrade: websocket") {
        info!("🌐 [{}] WebSocket Upgrade", peer_addr);
        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                        Upgrade: websocket\r\n\
                        Connection: Upgrade\r\n\
                        Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                        \r\n";
        socket.write_all(response.as_bytes()).await?;
        info!("✅ [{}] 101 Switching Protocols", peer_addr);
        tokio::time::sleep(tokio::time::Duration::from_secs(300)).await;
        return Ok(());
    }
    
    // CONNECT
    if request_str.starts_with("CONNECT ") {
        info!("🔗 [{}] CONNECT", peer_addr);
        socket.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n").await?;
        return Ok(());
    }
    
    // Qualquer outro request HTTP -> 200 OK
    info!("✅ [{}] Responding 200 OK", peer_addr);
    let response = "HTTP/1.1 200 OK\r\n\
                    Content-Type: text/plain\r\n\
                    Content-Length: 12\r\n\
                    Connection: keep-alive\r\n\
                    Server: ZXProxy\r\n\
                    \r\n\
                    OK";
    socket.write_all(response.as_bytes()).await?;
    info!("✅ [{}] HTTP 200 OK sent", peer_addr);
    
    Ok(())
}
EOF

# Criar os outros módulos
cat > src/socks5.rs << 'EOF'
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_socks5(mut client: TcpStream) -> Result<()> {
    info!("🔐 SOCKS5");
    let mut header = [0u8; 2];
    if client.read_exact(&mut header).await.is_err() { return Ok(()); }
    let nmethods = header[1] as usize;
    let mut methods = vec![0u8; nmethods];
    if client.read_exact(&mut methods).await.is_err() { return Ok(()); }
    client.write_all(&[0x05, 0x00]).await?;
    
    let mut req = [0u8; 4];
    if client.read_exact(&mut req).await.is_err() { return Ok(()); }
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
            tokio::try_join!(tokio::io::copy(&mut cr, &mut rw), tokio::io::copy(&mut rr, &mut cw))?;
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

cat > src/tcp_fallback.rs << 'EOF'
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_tcp(mut socket: TcpStream) -> Result<()> {
    info!("📦 TCP Fallback");
    socket.write_all(b"ZXProxy TCP OK\n").await?;
    Ok(())
}
EOF

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
        if buf.len() >= 4 && &buf[buf.len() - 4..] == b"\r\n\r\n" { break; }
        if buf.len() > 8192 { break; }
    }
    Ok(())
}

pub async fn handle_websocket(mut socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket");
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

cat > src/security.rs << 'EOF'
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_security(mut socket: TcpStream) -> Result<()> {
    info!("🔐 SECURITY");
    socket.write_all(b"SECURITY OK\n").await?;
    Ok(())
}
EOF

cat > src/tls.rs << 'EOF'
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_tls(mut socket: TcpStream) -> Result<()> {
    info!("🔒 TLS");
    socket.write_all(b"TLS OK\n").await?;
    Ok(())
}
EOF

# Compilar
echo "🔨 Compilando ZXProxy..."
cargo build --release

if [ $? -eq 0 ]; then
    # Instalar
    sudo cp target/release/zxproxy /usr/local/bin/
    sudo chmod +x /usr/local/bin/zxproxy
    
    # Criar menu
    sudo mkdir -p /opt/zxproxy
    sudo cp target/release/zxproxy /opt/zxproxy/proxy
    
    # Menu
    sudo cat > /usr/local/bin/zxproxy-menu << 'EOF'
#!/bin/bash
echo "====================================="
echo "          ZXProxy Menu              "
echo "====================================="
echo ""
echo " 1 - Iniciar na porta 80"
echo " 2 - Iniciar na porta 8080"
echo " 3 - Iniciar na porta 443"
echo " 4 - Iniciar porta customizada"
echo " 5 - Parar todos"
echo " 6 - Status"
echo " 7 - Ver logs"
echo " 8 - Sair"
echo ""
read -p "--> Selecione uma opção: " OPTION

case $OPTION in
    1) sudo fuser -k 80/tcp 2>/dev/null; sudo zxproxy -p 80 ;;
    2) sudo fuser -k 8080/tcp 2>/dev/null; sudo zxproxy -p 8080 ;;
    3) sudo fuser -k 443/tcp 2>/dev/null; sudo zxproxy -p 443 ;;
    4) read -p "Digite a porta: " PORT; sudo fuser -k $PORT/tcp 2>/dev/null; sudo zxproxy -p $PORT ;;
    5) sudo pkill -9 zxproxy; sudo rm -f /tmp/*proxy*.pid ;;
    6) ps aux | grep zxproxy | grep -v grep ;;
    7) tail -f /tmp/zxproxy_*.log 2>/dev/null || echo "Nenhum log encontrado" ;;
    8) exit 0 ;;
    *) echo "Opção inválida" ;;
esac
EOF
    
    sudo chmod +x /usr/local/bin/zxproxy-menu
    
    echo ""
    echo -e "\033[0;32m✅ Instalação concluída!\033[0m"
    echo ""
    echo "🚀 Comandos:"
    echo "   zxproxy -p 80     - Iniciar na porta 80"
    echo "   zxproxy-menu      - Menu interativo"
    echo ""
    echo "📡 Agora respondendo com HTTP 200 OK para qualquer request!"
    echo "   Ideal para VPN/HTTP Inject"
else
    echo "❌ Falha na compilação"
    tail -n 30 /tmp/zxproxy_build.log
fi
