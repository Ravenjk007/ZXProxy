#!/bin/bash
# ZXProxy - VPN/HTTP Inject Optimized

echo "🚀 Instalando ZXProxy VPN Optimized..."

# Parar processos antigos
sudo pkill -9 zxproxy 2>/dev/null
sudo fuser -k 80/tcp 2>/dev/null
sudo fuser -k 8080/tcp 2>/dev/null
sudo rm -f /tmp/*proxy*.pid 2>/dev/null

# Instalar Rust se não tiver
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

# main.rs - Versão Ultra Simples
cat > src/main.rs << 'EOF'
use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error};

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
    info!("📡 VPN Mode: Always respond 200 OK");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buffer = [0u8; 4096];
            match socket.read(&mut buffer).await {
                Ok(n) if n > 0 => {
                    let request = String::from_utf8_lossy(&buffer[..n]);
                    info!("📩 [{}] Request: {}", peer_addr, request.lines().next().unwrap_or(""));
                    
                    if request.to_lowercase().contains("upgrade: websocket") {
                        info!("🌐 [{}] WebSocket -> 101", peer_addr);
                        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                                        Upgrade: websocket\r\n\
                                        Connection: Upgrade\r\n\
                                        Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                                        \r\n";
                        let _ = socket.write_all(response.as_bytes()).await;
                        tokio::time::sleep(tokio::time::Duration::from_secs(300)).await;
                        return;
                    }
                    
                    info!("✅ [{}] Sending 200 OK", peer_addr);
                    let response = "HTTP/1.1 200 OK\r\n\
                                    Content-Type: text/plain\r\n\
                                    Content-Length: 12\r\n\
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
    Ok(())
}
EOF

# Compilar
echo "🔨 Compilando..."
cargo build --release

if [ $? -eq 0 ]; then
    sudo cp target/release/zxproxy /usr/local/bin/
    sudo chmod +x /usr/local/bin/zxproxy
    
    # Menu simplificado
    sudo cat > /usr/local/bin/zxproxy-menu << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "====================================="
    echo "          ZXProxy Menu              "
    echo "====================================="
    echo ""
    echo "Portas ativas:"
    ps aux | grep "zxproxy -p" | grep -v grep | while read line; do
        PORT=$(echo $line | grep -oP '(?<=-p )\d+')
        PID=$(echo $line | awk '{print $2}')
        echo "   ✅ Porta $PORT (PID: $PID)"
    done
    echo ""
    echo " 1 - Iniciar porta 80 (HTTP)"
    echo " 2 - Iniciar porta 8080"
    echo " 3 - Iniciar porta 443"
    echo " 4 - Iniciar porta customizada"
    echo " 5 - Parar todos"
    echo " 6 - Status"
    echo " 7 - Ver logs"
    echo " 8 - Sair"
    echo ""
    read -p "--> " OPT
    
    case $OPT in
        1) 
            sudo fuser -k 80/tcp 2>/dev/null
            sudo pkill -9 zxproxy 2>/dev/null
            sudo nohup zxproxy -p 80 > /tmp/zxproxy_80.log 2>&1 &
            echo "✅ Porta 80 iniciada!"
            sleep 2
            ;;
        2)
            sudo fuser -k 8080/tcp 2>/dev/null
            sudo pkill -9 zxproxy 2>/dev/null
            sudo nohup zxproxy -p 8080 > /tmp/zxproxy_8080.log 2>&1 &
            echo "✅ Porta 8080 iniciada!"
            sleep 2
            ;;
        3)
            sudo fuser -k 443/tcp 2>/dev/null
            sudo pkill -9 zxproxy 2>/dev/null
            sudo nohup zxproxy -p 443 > /tmp/zxproxy_443.log 2>&1 &
            echo "✅ Porta 443 iniciada!"
            sleep 2
            ;;
        4)
            read -p "Porta: " PORT
            sudo fuser -k $PORT/tcp 2>/dev/null
            sudo pkill -9 zxproxy 2>/dev/null
            sudo nohup zxproxy -p $PORT > /tmp/zxproxy_${PORT}.log 2>&1 &
            echo "✅ Porta $PORT iniciada!"
            sleep 2
            ;;
        5)
            sudo pkill -9 zxproxy
            sudo rm -f /tmp/*proxy*.pid
            echo "✅ Todos parados!"
            sleep 2
            ;;
        6)
            echo "📊 Status:"
            ps aux | grep zxproxy | grep -v grep || echo "❌ Nenhum ativo"
            echo ""
            read -p "Enter..."
            ;;
        7)
            echo "📝 Últimos logs:"
            tail -n 20 /tmp/zxproxy_*.log 2>/dev/null || echo "Nenhum log"
            echo ""
            read -p "Enter..."
            ;;
        8)
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
    echo "🚀 Comandos:"
    echo "   zxproxy -p 80     - Iniciar na porta 80"
    echo "   zxproxy-menu      - Menu interativo"
    echo ""
    echo "📡 Agora respondendo com HTTP 200 OK para qualquer request!"
    echo "   Ideal para VPN/HTTP Inject"
    echo ""
    echo "🔍 Teste:"
    echo "   curl -v -x http://localhost:80 https://google.com"
else
    echo "❌ Falha na compilação"
fi
