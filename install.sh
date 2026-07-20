#!/bin/bash
# ZXProxy - Versão Estável

echo "🚀 Instalando ZXProxy..."

# Parar tudo
sudo pkill -9 zxproxy 2>/dev/null
sudo fuser -k 80/tcp 2>/dev/null
sudo fuser -k 8080/tcp 2>/dev/null
sudo rm -f /tmp/*proxy*.pid 2>/dev/null

# Instalar Rust
if ! command -v rustc &> /dev/null; then
    echo "📦 Instalando Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Criar projeto
cd /root
rm -rf ZXProxy
cargo new ZXProxy
cd ZXProxy

# Cargo.toml
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

# main.rs
cat > src/main.rs << 'EOF'
use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error};

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "ZXProxy - VPN/HTTP Inject")]
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
    
    match TcpListener::bind(&addr).await {
        Ok(listener) => {
            info!("✅ ZXProxy listening on {}", addr);
            info!("📡 VPN Mode: Always 200 OK");
            
            while let Ok((mut socket, peer_addr)) = listener.accept().await {
                tokio::spawn(async move {
                    let mut buffer = [0u8; 4096];
                    match socket.read(&mut buffer).await {
                        Ok(n) if n > 0 => {
                            let request = String::from_utf8_lossy(&buffer[..n]);
                            let first_line = request.lines().next().unwrap_or("");
                            info!("📩 [{}] {}", peer_addr, first_line);
                            
                            // WebSocket
                            if request.to_lowercase().contains("upgrade: websocket") {
                                let response = "HTTP/1.1 101 Switching Protocols\r\n\
                                                Upgrade: websocket\r\n\
                                                Connection: Upgrade\r\n\
                                                Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                                                \r\n";
                                let _ = socket.write_all(response.as_bytes()).await;
                                info!("✅ [{}] 101 Switching Protocols", peer_addr);
                                tokio::time::sleep(tokio::time::Duration::from_secs(300)).await;
                                return;
                            }
                            
                            // 200 OK para tudo
                            let response = "HTTP/1.1 200 OK\r\n\
                                            Content-Type: text/plain\r\n\
                                            Content-Length: 2\r\n\
                                            Connection: keep-alive\r\n\
                                            Server: ZXProxy\r\n\
                                            \r\n\
                                            OK";
                            let _ = socket.write_all(response.as_bytes()).await;
                            info!("✅ [{}] 200 OK sent", peer_addr);
                        }
                        Ok(_) => info!("📦 [{}] Empty", peer_addr),
                        Err(e) => error!("❌ [{}] Error: {}", peer_addr, e),
                    }
                });
            }
        }
        Err(e) => {
            error!("❌ Failed to bind {}: {}", addr, e);
            return Err(e.into());
        }
    }
    Ok(())
}
EOF

# Compilar
echo "🔨 Compilando..."
cargo build --release 2>&1 | tail -20

if [ -f target/release/zxproxy ]; then
    sudo cp target/release/zxproxy /usr/local/bin/
    sudo chmod +x /usr/local/bin/zxproxy
    
    echo ""
    echo -e "\033[0;32m✅ Instalação concluída!\033[0m"
    echo ""
    echo "🚀 Iniciar na porta 80:"
    echo "   sudo zxproxy -p 80"
    echo ""
    echo "📝 Ver logs:"
    echo "   tail -f /tmp/zxproxy_80.log"
    echo ""
    echo "🔍 Testar:"
    echo "   curl -v -x http://localhost:80 https://google.com"
else
    echo "❌ Falha na compilação"
    ls -la target/release/
fi
