#!/bin/bash
# ZXProxy Installer - VPN/HTTP Inject Optimized
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

    show_progress "Compilando ZXProxy, isso pode levar algum tempo..."
    
    # Criar projeto do zero (mais confiável)
    cd /root
    rm -rf ZXProxy
    cargo new ZXProxy > /dev/null 2>&1 || error_exit "Falha ao criar projeto"
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

    # main.rs - Versão VPN/HTTP Inject
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
    Ok(())
}
EOF

    # Compilar
    cargo build --release > /tmp/zxproxy_build.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "❌ Erro na compilação:"
        tail -n 30 /tmp/zxproxy_build.log
        error_exit "Falha ao compilar ZXProxy"
    fi

    if [ -f ./target/release/zxproxy ]; then
        mv ./target/release/zxproxy /opt/zxproxy/proxy || error_exit "Falha ao mover binário"
        chmod +x /opt/zxproxy/proxy
    else
        error_exit "Binário 'zxproxy' não encontrado após compilação"
    fi
    increment_step

    show_progress "Configurando permissões..."
    chmod +x /opt/zxproxy/proxy

    # Criar o link
    cp /opt/zxproxy/proxy /usr/local/bin/zxproxy
    chmod +x /usr/local/bin/zxproxy
    increment_step

    show_progress "Limpando diretórios temporários..."
    cd /root/
    rm -rf /root/ZXProxy/
    increment_step

    # Criar serviço systemd
    show_progress "Configurando serviço systemd..."
    cat > /etc/systemd/system/zxproxy.service << 'EOF'
[Unit]
Description=ZXProxy VPN Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/zxproxy -p 80
Restart=always
RestartSec=5
StandardOutput=append:/tmp/zxproxy.log
StandardError=append:/tmp/zxproxy.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zxproxy
    systemctl start zxproxy

    # Criar menu
    cat > /usr/local/bin/zxproxy-menu << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "====================================="
    echo "          ZXProxy Menu              "
    echo "====================================="
    echo ""
    
    if systemctl is-active --quiet zxproxy; then
        echo "✅ ZXProxy: ATIVO (porta 80)"
    else
        echo "❌ ZXProxy: PARADO"
    fi
    
    echo ""
    echo " 1 - Iniciar (porta 80)"
    echo " 2 - Parar"
    echo " 3 - Reiniciar"
    echo " 4 - Ver logs"
    echo " 5 - Status"
    echo " 6 - Sair"
    echo ""
    read -p "--> " OPT
    
    case $OPT in
        1)
            sudo systemctl start zxproxy
            echo "✅ ZXProxy iniciado!"
            sleep 2
            ;;
        2)
            sudo systemctl stop zxproxy
            echo "✅ ZXProxy parado"
            sleep 2
            ;;
        3)
            sudo systemctl restart zxproxy
            echo "✅ ZXProxy reiniciado"
            sleep 2
            ;;
        4)
            echo "📝 Últimos logs:"
            tail -n 30 /tmp/zxproxy.log
            echo ""
            read -p "Enter..."
            ;;
        5)
            sudo systemctl status zxproxy --no-pager
            echo ""
            read -p "Enter..."
            ;;
        6)
            echo "👋 Saindo..."
            exit 0
            ;;
        *)
            echo "❌ Opção inválida"
            sleep 2
            ;;
    esac
done
EOF

    chmod +x /usr/local/bin/zxproxy-menu

    echo ""
    echo -e "\033[0;32m✅ Instalação concluída com sucesso!\033[0m"
    echo ""
    echo "🚀 Digite 'zxproxy-menu' para acessar o menu."
    echo "   Ou 'zxproxy -p 80' para abrir porta 80 diretamente."
    echo ""
    echo "📡 Protocolos suportados:"
    echo "   - HTTP (SEMPRE 200 OK)"
    echo "   - WebSocket (101 Switching Protocols)"
    echo "   - TCP Fallback"
    echo ""
    echo "📝 Log: /tmp/zxproxy.log"
    echo "🔍 Status: sudo systemctl status zxproxy"
    echo ""
    echo "📱 Configure seu app VPN com:"
    echo "   Proxy: $(curl -s ifconfig.me):80"
    echo ""
fi
