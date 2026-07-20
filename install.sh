#!/bin/bash
# ZXProxy Installer - VPN HTTP Injector Optimized

echo "🚀 Instalando ZXProxy para HTTP Injector..."

# Parar processos antigos
sudo pkill -9 zxproxy 2>/dev/null
sudo fuser -k 80/tcp 2>/dev/null
sudo fuser -k 8080/tcp 2>/dev/null
sudo rm -f /tmp/*proxy*.pid 2>/dev/null

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
use std::time::Duration;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "ZXProxy - HTTP Injector Optimized")]
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
    info!("📡 HTTP Injector Mode: Read all, 200 OK, Keep-Alive");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buffer = vec![0u8; 8192];
            
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
                        info!("✅ [{}] 101 WebSocket", peer_addr);
                    } else {
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
                    
                    // KEEP-ALIVE INFINITO
                    let mut interval = tokio::time::interval(Duration::from_secs(20));
                    loop {
                        interval.tick().await;
                        match socket.write_all(b"\r\n").await {
                            Ok(_) => info!("💓 [{}] Keep-alive", peer_addr),
                            Err(_) => break,
                        }
                    }
                    info!("🔚 [{}] Connection closed", peer_addr);
                }
                Ok(_) => info!("📦 [{}] Empty", peer_addr),
                Err(e) => error!("❌ [{}] Error: {}", peer_addr, e),
            }
        });
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
    
    # Menu
    cat > /usr/local/bin/zxproxy-menu << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "====================================="
    echo "          ZXProxy Menu              "
    echo "====================================="
    echo ""
    ps aux | grep "zxproxy -p" | grep -v grep | while read line; do
        PORT=$(echo $line | grep -oP '(?<=-p )\d+')
        PID=$(echo $line | awk '{print $2}')
        echo "   ✅ Porta $PORT (PID: $PID)"
    done
    echo ""
    echo " 1 - Iniciar porta 80 (HTTP Injector)"
    echo " 2 - Iniciar porta 8080"
    echo " 3 - Iniciar porta customizada"
    echo " 4 - Parar todos"
    echo " 5 - Status"
    echo " 6 - Ver logs"
    echo " 7 - Sair"
    echo ""
    read -p "--> " OPT
    
    case $OPT in
        1)
            sudo fuser -k 80/tcp 2>/dev/null
            sudo pkill -9 zxproxy 2>/dev/null
            sudo nohup zxproxy -p 80 > /tmp/zxproxy_80.log 2>&1 &
            sleep 2
            echo "✅ Porta 80 iniciada!"
            read -p "Enter..."
            ;;
        2)
            sudo fuser -k 8080/tcp 2>/dev/null
            sudo pkill -9 zxproxy 2>/dev/null
            sudo nohup zxproxy -p 8080 > /tmp/zxproxy_8080.log 2>&1 &
            sleep 2
            echo "✅ Porta 8080 iniciada!"
            read -p "Enter..."
            ;;
        3)
            read -p "Porta: " PORT
            sudo fuser -k $PORT/tcp 2>/dev/null
            sudo pkill -9 zxproxy 2>/dev/null
            sudo nohup zxproxy -p $PORT > /tmp/zxproxy_${PORT}.log 2>&1 &
            sleep 2
            echo "✅ Porta $PORT iniciada!"
            read -p "Enter..."
            ;;
        4)
            sudo pkill -9 zxproxy
            sudo rm -f /tmp/*proxy*.pid
            echo "✅ Todos parados!"
            sleep 2
            ;;
        5)
            echo "📊 Status:"
            ps aux | grep zxproxy | grep -v grep || echo "❌ Nenhum ativo"
            echo ""
            read -p "Enter..."
            ;;
        6)
            echo "📝 Logs:"
            tail -n 20 /tmp/zxproxy_*.log 2>/dev/null || echo "Nenhum log"
            echo ""
            read -p "Enter..."
            ;;
        7)
            echo "👋 Saindo..."
            exit 0
            ;;
    esac
done
EOF
    
    sudo chmod +x /usr/local/bin/zxproxy-menu
    
    echo ""
    echo -e "\033[0;32m✅ Instalação concluída!\033[0m"
    echo ""
    echo "🚀 COMANDOS:"
    echo "   zxproxy-menu    - Menu interativo"
    echo "   sudo zxproxy -p 80 - Iniciar direto"
    echo ""
    echo "📱 CONFIGURE NO APP:"
    echo "   Proxy: $(curl -s ifconfig.me):80"
    echo "   Payload: Qualquer um, o proxy vai responder 200 OK"
    echo ""
    echo "🔍 TESTE:"
    echo "   curl -v -x http://localhost:80 https://google.com"
else
    echo "❌ Falha na compilação"
fi
