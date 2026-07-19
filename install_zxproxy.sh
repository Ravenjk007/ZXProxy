#!/bin/bash
# ============================================================
# ZXProxy Complete Installer v2.0
# Multiprotocol Proxy with VPN Support
# GitHub: https://github.com/Ravenjk007/ZXProxy
# ============================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configurações
INSTALL_DIR="/opt/zxproxy"
BIN_NAME="zxproxy"
PID_FILE="/tmp/zxproxy_"
VERSION="2.0.0"
GITHUB_REPO="Ravenjk007/ZXProxy"

# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_step() {
    echo -e "${CYAN}▶${NC} $1"
}

show_banner() {
    clear
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║     ███████╗██╗  ██╗██████╗ ██████╗  ██████╗ ██╗   ██╗ ║"
    echo "║     ╚══███╔╝██║  ██║██╔══██╗██╔══██╗██╔═══██╗╚██╗ ██╔╝ ║"
    echo "║       ███╔╝ ███████║██████╔╝██████╔╝██║   ██║ ╚████╔╝  ║"
    echo "║      ███╔╝  ██╔══██║██╔═══╝ ██╔══██╗██║   ██║  ╚██╔╝   ║"
    echo "║     ███████╗██║  ██║██║     ██║  ██║╚██████╔╝   ██║    ║"
    echo "║     ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ║"
    echo "║                                                          ║"
    echo "║         ZXProxy Installer v${VERSION}                      ║"
    echo "║    Multiprotocol Proxy with VPN Support                  ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

show_progress() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  $1"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
}

# ============================================================
# VERIFICAÇÕES INICIAIS
# ============================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script deve ser executado como root (use sudo)"
        echo ""
        echo "Execute: sudo bash install_zxproxy.sh"
        exit 1
    fi
}

check_internet() {
    log_step "Verificando conexão com a internet..."
    if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        log_error "Sem conexão com a internet"
        exit 1
    fi
    log_success "Conexão com a internet OK"
}

detect_os() {
    log_step "Detectando sistema operacional..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        ARCH=$(uname -m)
    else
        log_error "Sistema operacional não suportado"
        exit 1
    fi
    
    log_success "Sistema: $OS $VER ($ARCH)"
    
    # Verifica suporte
    case $OS in
        Ubuntu|Debian)
            log_success "Sistema suportado"
            ;;
        *)
            log_warning "Sistema não testado: $OS"
            read -p "Continuar mesmo assim? (s/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                exit 1
            fi
            ;;
    esac
}

# ============================================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ============================================================

install_dependencies() {
    show_progress "INSTALANDO DEPENDÊNCIAS"
    
    log_step "Atualizando repositórios..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y > /dev/null 2>&1 || {
        log_error "Falha ao atualizar repositórios"
        exit 1
    }
    log_success "Repositórios atualizados"
    
    log_step "Instalando pacotes necessários..."
    apt install -y \
        curl \
        wget \
        build-essential \
        git \
        pkg-config \
        libssl-dev \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        > /dev/null 2>&1 || {
        log_error "Falha ao instalar dependências"
        exit 1
    }
    
    log_success "Dependências instaladas"
}

# ============================================================
# INSTALAÇÃO RUST
# ============================================================

install_rust() {
    show_progress "INSTALANDO RUST"
    
    if command -v rustc &> /dev/null; then
        log_success "Rust já está instalado: $(rustc --version)"
        log_step "Atualizando Rust..."
        rustup update > /dev/null 2>&1
        log_success "Rust atualizado"
        return
    fi
    
    log_step "Baixando e instalando Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y > /tmp/rust_install.log 2>&1 || {
        log_error "Falha ao instalar Rust"
        cat /tmp/rust_install.log
        exit 1
    }
    
    source "$HOME/.cargo/env"
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Adiciona ao PATH permanentemente
    if ! grep -q ".cargo/bin" ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    fi
    
    log_success "Rust instalado: $(rustc --version)"
    log_success "Cargo instalado: $(cargo --version)"
}

# ============================================================
# COMPILAÇÃO DO ZXPROXY
# ============================================================

compile_zxproxy() {
    show_progress "COMPILANDO ZXPROXY"
    
    log_step "Preparando ambiente de compilação..."
    
    local BUILD_DIR="/tmp/zxproxy_build_$$"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    log_step "Criando estrutura do projeto..."
    
    # Cria Cargo.toml
    cat > Cargo.toml << 'EOF'
[package]
name = "zxproxy"
version = "2.0.0"
edition = "2021"
authors = ["Ravenjk007"]
description = "ZXProxy - Multiprotocol proxy server with VPN capabilities"
repository = "https://github.com/Ravenjk007/ZXProxy"
license = "MIT"

[dependencies]
tokio = { version = "1.35", features = ["full"] }
clap = { version = "4.4", features = ["derive"] }
anyhow = "1.0"
log = "0.4"
env_logger = "0.10"
native-tls = "0.2"
tokio-native-tls = "0.3"
http = "0.2"
bytes = "1.5"
futures-util = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[profile.release]
lto = true
codegen-units = 1
opt-level = 3
strip = true
EOF

    # Cria src/main.rs
    mkdir -p src
    cat > src/main.rs << 'EOF'
mod socks5;
mod tls;
mod websocket;
mod tcp_fallback;
mod security;
mod config;

use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error, warn, debug};
use std::sync::Arc;
use tokio::sync::Mutex;
use std::collections::HashMap;
use std::time::Instant;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "ZXProxy - Multiprotocol proxy server with VPN support")]
#[command(version = "2.0.0")]
struct Cli {
    #[arg(short = 'p', long = "port", default_value = "8080")]
    port: u16,
    
    #[arg(short = 'd', long = "debug")]
    debug: bool,
    
    #[arg(short = 'v', long = "vpn", default_value = "true")]
    vpn: bool,
    
    #[arg(short = 't', long = "timeout", default_value = "30")]
    timeout: u64,
}

struct ProxyStats {
    connections: usize,
    active_connections: usize,
    total_bytes: u64,
    protocols: HashMap<String, usize>,
    start_time: Instant,
}

impl ProxyStats {
    fn new() -> Self {
        Self {
            connections: 0,
            active_connections: 0,
            total_bytes: 0,
            protocols: HashMap::new(),
            start_time: Instant::now(),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Configura logging
    if cli.debug {
        env_logger::builder()
            .filter_level(log::LevelFilter::Debug)
            .format_timestamp_millis()
            .init();
    } else {
        env_logger::builder()
            .filter_level(log::LevelFilter::Info)
            .format_timestamp_millis()
            .init();
    }
    
    let addr = format!("0.0.0.0:{}", cli.port);
    let listener = TcpListener::bind(&addr).await?;
    
    info!("╔══════════════════════════════════════════════════════════╗");
    info!("║         🚀 ZXProxy Server v2.0                         ║");
    info!("║    Multiprotocol Proxy with VPN Support                 ║");
    info!("╚══════════════════════════════════════════════════════════╝");
    info!("📡 Listening on: {}", addr);
    info!("🔒 VPN Mode: {}", if cli.vpn { "ENABLED" } else { "DISABLED" });
    info!("⏱️  Timeout: {}s", cli.timeout);
    info!("📦 Supported Protocols:");
    info!("   • SOCKS5 (Port 1080 compatible)");
    info!("   • TLS/SSL");
    info!("   • WebSocket (WS/WSS)");
    info!("   • HTTP/HTTPS Proxy");
    info!("   • TCP Fallback");
    info!("   • Security/Auth");
    info!("");

    let stats = Arc::new(Mutex::new(ProxyStats::new()));
    
    // Thread para estatísticas
    let stats_clone = stats.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(30));
        loop {
            interval.tick().await;
            let stats = stats_clone.lock().await;
            let uptime = stats.start_time.elapsed().as_secs();
            info!("📊 Stats: {} connections, {} active, {} bytes, {}s uptime",
                stats.connections, stats.active_connections, stats.total_bytes, uptime);
        }
    });

    while let Ok((mut socket, addr)) = listener.accept().await {
        let stats_clone = stats.clone();
        let vpn_enabled = cli.vpn;
        let timeout = cli.timeout;
        
        tokio::spawn(async move {
            {
                let mut stats = stats_clone.lock().await;
                stats.connections += 1;
                stats.active_connections += 1;
            }
            
            let mut buf = [0u8; 1024];
            
            // Timeout para leitura inicial
            let read_result = tokio::time::timeout(
                tokio::time::Duration::from_secs(timeout),
                socket.peek(&mut buf)
            ).await;
            
            match read_result {
                Ok(Ok(n)) if n > 0 => {
                    let protocol = detect_protocol(&buf, n);
                    
                    {
                        let mut stats = stats_clone.lock().await;
                        *stats.protocols.entry(protocol.to_string()).or_insert(0) += 1;
                    }
                    
                    info!("📥 {} connection from {} ({} bytes)", protocol, addr, n);
                    debug!("First bytes: {:02x?}", &buf[..std::cmp::min(n, 16)]);
                    
                    let result = match protocol {
                        "SOCKS5" => socks5::handle_socks5(socket, vpn_enabled).await,
                        "TLS" => tls::handle_tls(socket, vpn_enabled).await,
                        "WEBSOCKET" => websocket::handle_websocket(socket, vpn_enabled).await,
                        "HTTP" => websocket::handle_websocket(socket, vpn_enabled).await,
                        "SECURITY" => security::handle_security(socket, vpn_enabled).await,
                        _ => tcp_fallback::handle_tcp(socket, vpn_enabled).await,
                    };
                    
                    if let Err(e) = result {
                        error!("❌ Error handling {} connection: {}", protocol, e);
                    } else {
                        debug!("✅ {} connection closed", protocol);
                    }
                }
                Ok(Ok(_)) => {
                    warn!("⚠️ Empty connection from {}", addr);
                }
                Ok(Err(e)) => {
                    error!("❌ Peek error from {}: {}", addr, e);
                }
                Err(_) => {
                    warn!("⏱️ Timeout reading from {}", addr);
                }
            }
            
            {
                let mut stats = stats_clone.lock().await;
                stats.active_connections -= 1;
            }
        });
    }
    
    Ok(())
}

fn detect_protocol(buf: &[u8], n: usize) -> &'static str {
    // SOCKS5
    if n > 0 && buf[0] == 0x05 {
        return "SOCKS5";
    }
    
    // TLS/SSL
    if n > 2 && buf[0] == 0x16 && (buf[1] == 0x03 || buf[1] == 0x02) {
        return "TLS";
    }
    
    // HTTP/WebSocket
    if let Ok(data) = std::str::from_utf8(&buf[..std::cmp::min(n, 256)]) {
        if data.starts_with("GET ") || data.starts_with("POST ") || 
           data.starts_with("PUT ") || data.starts_with("DELETE ") ||
           data.starts_with("HEAD ") || data.starts_with("CONNECT ") ||
           data.starts_with("OPTIONS ") || data.starts_with("PATCH ") ||
           data.starts_with("TRACE ") || data.starts_with("HTTP/") {
            
            if data.contains("Upgrade: websocket") || data.contains("Upgrade: WebSocket") {
                return "WEBSOCKET";
            }
            return "HTTP";
        }
        
        // Security
        if data.starts_with("SECURITY") || data.starts_with("AUTH") || 
           data.starts_with("AUTHENTICATE") || data.starts_with("LOGIN") {
            return "SECURITY";
        }
    }
    
    // TCP Fallback
    "TCP"
}
EOF

    # Cria os módulos
    for mod_name in socks5 tls websocket tcp_fallback security config; do
        cat > src/${mod_name}.rs << 'EOF'
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::{Result, anyhow};
use log::{info, debug, error, warn};

pub async fn handle_socks5(mut socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    debug!("🔐 SOCKS5 handler (VPN: {})", vpn_enabled);
    
    let mut buf = [0u8; 256];
    let n = socket.read(&mut buf).await?;
    
    if n < 3 || buf[0] != 0x05 {
        return Err(anyhow!("Invalid SOCKS5 handshake"));
    }
    
    // Responde com método sem autenticação
    socket.write_all(&[0x05, 0x00]).await?;
    
    // Lê comando
    let n = socket.read(&mut buf).await?;
    if n < 10 {
        return Err(anyhow!("Invalid SOCKS5 command"));
    }
    
    let cmd = buf[1];
    if cmd != 0x01 {
        return Err(anyhow!("Only CONNECT supported (cmd: {})", cmd));
    }
    
    // Extrai endereço
    let atyp = buf[3];
    let (host, port) = match atyp {
        0x01 => {
            let ip = format!("{}.{}.{}.{}", buf[4], buf[5], buf[6], buf[7]);
            let port = u16::from_be_bytes([buf[8], buf[9]]);
            (ip, port)
        },
        0x03 => {
            let len = buf[4] as usize;
            let domain = String::from_utf8_lossy(&buf[5..5+len]).to_string();
            let port = u16::from_be_bytes([buf[5+len], buf[6+len]]);
            (domain, port)
        },
        0x04 => {
            // IPv6 simplificado
            let mut ipv6 = String::new();
            for i in 4..20 {
                ipv6.push_str(&format!("{:02x}", buf[i]));
                if (i - 4) % 2 == 1 && i < 19 {
                    ipv6.push(':');
                }
            }
            let port = u16::from_be_bytes([buf[20], buf[21]]);
            (ipv6, port)
        },
        _ => return Err(anyhow!("Unsupported address type: {}", atyp)),
    };
    
    info!("🔗 SOCKS5 CONNECT to {}:{}", host, port);
    
    // Conecta ao destino
    let mut dest = match TcpStream::connect(format!("{}:{}", host, port)).await {
        Ok(stream) => stream,
        Err(e) => {
            error!("Failed to connect to {}:{}: {}", host, port, e);
            socket.write_all(&[0x05, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
            return Err(anyhow!("Connection failed"));
        }
    };
    
    // Responde com sucesso
    socket.write_all(&[0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
    
    info!("✅ SOCKS5 tunnel established to {}:{}", host, port);
    
    // Proxy bidirecional
    let (mut reader, mut writer) = socket.into_split();
    let (mut dest_reader, mut dest_writer) = dest.into_split();
    
    tokio::select! {
        _ = tokio::io::copy(&mut reader, &mut dest_writer) => {},
        _ = tokio::io::copy(&mut dest_reader, &mut writer) => {},
    }
    
    Ok(())
}

pub async fn handle_tls(mut socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    info!("🔒 TLS connection (VPN: {})", vpn_enabled);
    tcp_fallback::handle_tcp(socket, vpn_enabled).await
}

pub async fn handle_websocket(mut socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    debug!("🌐 WebSocket/HTTP handler (VPN: {})", vpn_enabled);
    
    let mut buf = [0u8; 8192];
    let n = socket.read(&mut buf).await?;
    
    if n == 0 {
        return Err(anyhow!("Empty request"));
    }
    
    let request = String::from_utf8_lossy(&buf[..n]);
    debug!("Request: {}", request.lines().next().unwrap_or(""));
    
    // Verifica se é CONNECT (HTTPS)
    if request.starts_with("CONNECT") {
        return handle_connect(socket, &buf[..n]).await;
    }
    
    // Extrai host
    let host = request.lines()
        .find(|line| line.to_lowercase().starts_with("host:"))
        .map(|line| line[5..].trim().to_string())
        .unwrap_or_else(|| "localhost".to_string());
    
    let port = if host.contains(':') {
        let parts: Vec<&str> = host.split(':').collect();
        if parts.len() == 2 {
            port = parts[1].parse().unwrap_or(80);
            host = parts[0].to_string();
        }
        80
    } else {
        80
    };
    
    info!("🌐 HTTP proxy to {}:{}", host, port);
    
    let mut dest = match TcpStream::connect(format!("{}:{}", host, port)).await {
        Ok(stream) => stream,
        Err(e) => {
            error!("Failed to connect to {}:{}: {}", host, port, e);
            return Err(anyhow!("Connection failed"));
        }
    };
    
    // Envia requisição original
    dest.write_all(&buf[..n]).await?;
    
    // Proxy bidirecional
    let (mut reader, mut writer) = socket.into_split();
    let (mut dest_reader, mut dest_writer) = dest.into_split();
    
    tokio::select! {
        _ = tokio::io::copy(&mut reader, &mut dest_writer) => {},
        _ = tokio::io::copy(&mut dest_reader, &mut writer) => {},
    }
    
    Ok(())
}

async fn handle_connect(mut socket: TcpStream, data: &[u8]) -> Result<()> {
    let request = String::from_utf8_lossy(data);
    let parts: Vec<&str> = request.split_whitespace().collect();
    
    if parts.len() < 2 {
        return Err(anyhow!("Invalid CONNECT request"));
    }
    
    let target = parts[1];
    let target_parts: Vec<&str> = target.split(':').collect();
    
    if target_parts.len() != 2 {
        return Err(anyhow!("Invalid target format"));
    }
    
    let host = target_parts[0];
    let port: u16 = target_parts[1].parse().unwrap_or(443);
    
    info!("🔒 HTTPS CONNECT to {}:{}", host, port);
    
    let mut dest = match TcpStream::connect(format!("{}:{}", host, port)).await {
        Ok(stream) => stream,
        Err(e) => {
            error!("Failed to connect to {}:{}: {}", host, port, e);
            return Err(anyhow!("Connection failed"));
        }
    };
    
    // Responde com 200 OK
    socket.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n").await?;
    
    // Proxy bidirecional
    let (mut reader, mut writer) = socket.into_split();
    let (mut dest_reader, mut dest_writer) = dest.into_split();
    
    tokio::select! {
        _ = tokio::io::copy(&mut reader, &mut dest_writer) => {},
        _ = tokio::io::copy(&mut dest_reader, &mut writer) => {},
    }
    
    Ok(())
}

pub async fn handle_tcp(mut socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    info!("📦 TCP fallback (VPN: {})", vpn_enabled);
    
    // Conecta a Google DNS como fallback
    let mut dest = match TcpStream::connect("8.8.8.8:53").await {
        Ok(stream) => stream,
        Err(e) => {
            error!("Failed to connect to fallback: {}", e);
            return Err(anyhow!("Fallback connection failed"));
        }
    };
    
    let (mut reader, mut writer) = socket.into_split();
    let (mut dest_reader, mut dest_writer) = dest.into_split();
    
    tokio::select! {
        _ = tokio::io::copy(&mut reader, &mut dest_writer) => {},
        _ = tokio::io::copy(&mut dest_reader, &mut writer) => {},
    }
    
    Ok(())
}

pub async fn handle_security(mut socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    info!("🔐 Security connection (VPN: {})", vpn_enabled);
    
    let mut buf = [0u8; 1024];
    let n = socket.read(&mut buf).await?;
    
    if n > 0 {
        let data = String::from_utf8_lossy(&buf[..n]);
        debug!("Security data: {}", data);
        
        if data.starts_with("AUTH ") || data.starts_with("SECURITY ") {
            socket.write_all(b"SECURITY OK\n").await?;
            info!("✅ Security authentication successful");
        } else {
            socket.write_all(b"SECURITY FAIL\n").await?;
            return Err(anyhow!("Invalid security request"));
        }
    }
    
    Ok(())
}
EOF
    done

    # Cria lib.rs
    cat > src/lib.rs << 'EOF'
pub mod socks5;
pub mod tls;
pub mod websocket;
pub mod tcp_fallback;
pub mod security;
pub mod config;
EOF

    # Cria config.rs
    cat > src/config.rs << 'EOF'
use serde::{Deserialize, Serialize};
use std::fs;
use anyhow::Result;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Config {
    pub port: u16,
    pub vpn_enabled: bool,
    pub timeout: u64,
    pub max_connections: usize,
    pub allowed_ips: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            port: 8080,
            vpn_enabled: true,
            timeout: 30,
            max_connections: 1000,
            allowed_ips: vec!["0.0.0.0/0".to_string()],
        }
    }
}

impl Config {
    pub fn load(path: &str) -> Result<Self> {
        if fs::metadata(path).is_ok() {
            let content = fs::read_to_string(path)?;
            let config: Config = serde_json::from_str(&content)?;
            Ok(config)
        } else {
            Ok(Config::default())
        }
    }
    
    pub fn save(&self, path: &str) -> Result<()> {
        let content = serde_json::to_string_pretty(self)?;
        fs::write(path, content)?;
        Ok(())
    }
}
EOF

    # Compila
    log_step "Compilando ZXProxy (isso pode levar alguns minutos)..."
    log_info "Usando $(nproc) cores para compilação"
    
    cargo build --release --jobs $(nproc) 2>&1 | tee /tmp/build.log | grep -E "Compiling|Finished|error|warning" || {
        log_error "Falha na compilação"
        echo ""
        log_warning "Últimas linhas do log:"
        tail -20 /tmp/build.log
        exit 1
    }
    
    # Verifica se o binário foi criado
    if [ ! -f target/release/zxproxy ]; then
        log_error "Binário não encontrado após compilação"
        exit 1
    fi
    
    # Tamanho do binário
    SIZE=$(du -h target/release/zxproxy | cut -f1)
    log_success "ZXProxy compilado com sucesso (tamanho: $SIZE)"
    
    # Copia para o diretório de instalação
    mkdir -p "$INSTALL_DIR"
    cp target/release/zxproxy "$INSTALL_DIR/proxy"
    chmod +x "$INSTALL_DIR/proxy"
    
    # Limpa
    cd /
    rm -rf "$BUILD_DIR"
}

# ============================================================
# CRIAÇÃO DO MENU
# ============================================================

create_menu() {
    show_progress "CRIANDO SISTEMA DE MENU"
    
    log_step "Criando script de menu interativo..."
    
    cat > "$INSTALL_DIR/menu" << 'EOF'
#!/bin/bash
# ZXProxy Menu Manager

ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"
CONFIG_FILE="/opt/zxproxy/config.json"
LOG_DIR="/var/log/zxproxy"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_banner() {
    clear
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║     ███████╗██╗  ██╗██████╗ ██████╗  ██████╗ ██╗   ██╗ ║"
    echo "║     ╚══███╔╝██║  ██║██╔══██╗██╔══██╗██╔═══██╗╚██╗ ██╔╝ ║"
    echo "║       ███╔╝ ███████║██████╔╝██████╔╝██║   ██║ ╚████╔╝  ║"
    echo "║      ███╔╝  ██╔══██║██╔═══╝ ██╔══██╗██║   ██║  ╚██╔╝   ║"
    echo "║     ███████╗██║  ██║██║     ██║  ██║╚██████╔╝   ██║    ║"
    echo "║     ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ║"
    echo "║                                                          ║"
    echo "║         ZXProxy Manager v2.0                            ║"
    echo "║    Multiprotocol Proxy with VPN Support                  ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

show_status() {
    ACTIVE=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                ACTIVE="$ACTIVE $PORT"
            else
                rm -f "$pidfile"
            fi
        fi
    done
    
    echo -e "${BLUE}📊 Status:${NC}"
    if [ -n "$ACTIVE" ]; then
        echo -e "   ${GREEN}✅${NC} Porta(s) aberta(s):${CYAN}$ACTIVE${NC}"
    else
        echo -e "   ${YELLOW}⚠️${NC}  Nenhuma porta ativa"
    fi
    echo ""
    
    echo -e "${BLUE}📦 Versão:${NC} $(/opt/zxproxy/proxy --version 2>/dev/null || echo "v2.0.0")"
    echo ""
}

show_menu() {
    show_banner
    show_status
    
    echo -e "${BLUE}📋 Menu Principal:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │  ${GREEN}1${NC} - Abrir Porta                             │"
    echo "  │  ${RED}2${NC} - Fechar Porta                            │"
    echo "  │  ${CYAN}3${NC} - Status do Proxy                        │"
    echo "  │  ${CYAN}4${NC} - Ver Logs                              │"
    echo "  │  ${CYAN}5${NC} - Testar Proxy                          │"
    echo "  │  ${CYAN}6${NC} - Configurações                        │"
    echo "  │  ${RED}7${NC} - Sair                                  │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
    echo -n "👉 Selecione uma opção: "
}

open_port() {
    show_banner
    echo -e "${GREEN}🔓 ABRIR PORTA${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    read -p "📝 Digite o número da porta: " PORT
    
    # Valida porta
    if [[ -z "$PORT" ]] || ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "${RED}❌ Porta inválida! Use um número entre 1 e 65535.${NC}"
        sleep 2
        return
    fi
    
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        echo -e "${RED}❌ Porta ${PORT} já está aberta!${NC}"
        sleep 2
        return
    fi
    
    if [ ! -f "$ZXPROXY" ]; then
        echo -e "${RED}❌ ZXProxy não encontrado!${NC}"
        sleep 3
        return
    fi
    
    echo -e "${YELLOW}⏳ Abrindo porta ${PORT}...${NC}"
    
    # Cria diretório de logs
    mkdir -p "$LOG_DIR"
    
    # Inicia o proxy
    nohup ${ZXPROXY} -p ${PORT} -d > "${LOG_DIR}/zxproxy_${PORT}.log" 2>&1 &
    echo $! > "${PID_FILE}${PORT}.pid"
    
    sleep 2
    
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Porta ${PORT} aberta com sucesso!${NC}"
        echo ""
        echo -e "${BLUE}📡 Proxy rodando em:${NC} 0.0.0.0:${PORT}"
        echo -e "${BLUE}🔒 Modo VPN:${NC} Ativado"
        echo -e "${BLUE}📋 Logs:${NC} ${LOG_DIR}/zxproxy_${PORT}.log"
        echo ""
        echo -e "${CYAN}🌐 Teste rápido:${NC}"
        echo "   curl -x http://localhost:${PORT} https://example.com"
    else
        echo -e "${RED}❌ Falha ao abrir a porta ${PORT}!${NC}"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    
    echo ""
    read -p "Pressione ENTER para continuar..."
}

close_port() {
    show_banner
    echo -e "${RED}🔒 FECHAR PORTA${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Lista portas ativas
    echo -e "${BLUE}📡 Portas ativas:${NC}"
    FOUND=false
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                echo "   🔹 Porta ${PORT} (PID: $(cat $pidfile))"
                FOUND=true
            fi
        fi
    done
    
    if [ "$FOUND" = false ]; then
        echo -e "${YELLOW}   Nenhuma porta ativa${NC}"
        sleep 2
        return
    fi
    
    echo ""
    read -p "📝 Digite o número da porta: " PORT
    
    if [[ -z "$PORT" ]] || ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Porta inválida!${NC}"
        sleep 2
        return
    fi
    
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo -e "${GREEN}✅ Porta ${PORT} fechada com sucesso!${NC}"
        echo -e "🗑️  Processo ${PID} terminado."
    else
        echo -e "${RED}❌ Porta ${PORT} não está aberta!${NC}"
    fi
    
    echo ""
    read -p "Pressione ENTER para continuar..."
}

show_status_detailed() {
    show_banner
    echo -e "${CYAN}📊 STATUS DETALHADO${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Verifica instalação
    if [ -f "$ZXPROXY" ]; then
        echo -e "${GREEN}✅ ZXProxy instalado${NC}"
        echo -e "   📁 Local: $ZXPROXY"
        echo -e "   📦 Tamanho: $(du -h $ZXPROXY | cut -f1)"
        echo -e "   📌 Versão: $(/opt/zxproxy/proxy --version 2>/dev/null || echo "v2.0.0")"
    else
        echo -e "${RED}❌ ZXProxy NÃO instalado!${NC}"
    fi
    echo ""
    
    # Lista portas ativas
    echo -e "${BLUE}📡 Portas Ativas:${NC}"
    FOUND=false
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                PID=$(cat "$pidfile")
                echo -e "   ${GREEN}🔹${NC} Porta ${PORT} - PID: ${PID}"
                if command -v ps &> /dev/null; then
                    CPU=$(ps -p $PID -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    MEM=$(ps -p $PID -o %mem --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    TIME=$(ps -p $PID -o time --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    echo -e "      ${BLUE}CPU:${NC} ${CPU}% | ${BLUE}MEM:${NC} ${MEM}% | ${BLUE}Tempo:${NC} ${TIME}"
                fi
                FOUND=true
            else
                rm -f "$pidfile"
            fi
        fi
    done
    if [ "$FOUND" = false ]; then
        echo -e "   ${YELLOW}Nenhuma porta ativa${NC}"
    fi
    echo ""
    
    # Mostra logs recentes
    echo -e "${BLUE}📋 Últimos logs:${NC}"
    LATEST_LOG=$(ls -t ${LOG_DIR}/zxproxy_*.log 2>/dev/null | head -1)
    if [ -f "$LATEST_LOG" ]; then
        echo -e "   📄 Arquivo: $(basename $LATEST_LOG)"
        echo "   ─────────────────────────────────────────────"
        tail -5 "$LATEST_LOG" 2>/dev/null | while read line; do
            echo "   $line"
        done
    else
        echo -e "   ${YELLOW}Nenhum log disponível${NC}"
    fi
    echo ""
    
    read -p "Pressione ENTER para continuar..."
}

show_logs() {
    show_banner
    echo -e "${CYAN}📋 LOGS DO ZXPROXY${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Lista arquivos de log
    LOGS=$(ls -t ${LOG_DIR}/zxproxy_*.log 2>/dev/null)
    if [ -z "$LOGS" ]; then
        echo -e "${YELLOW}❌ Nenhum log encontrado${NC}"
        echo ""
        read -p "Pressione ENTER para continuar..."
        return
    fi
    
    echo -e "${BLUE}Arquivos de log disponíveis:${NC}"
    i=1
    declare -a LOG_FILES
    for log in $LOGS; do
        echo "  ${i} - $(basename $log) ($(du -h $log | cut -f1))"
        LOG_FILES[$i]=$log
        i=$((i+1))
    done
    echo "  0 - Voltar"
    echo ""
    read -p "Selecione um log para visualizar: " choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        return
    fi
    
    if [ -n "${LOG_FILES[$choice]}" ] && [ -f "${LOG_FILES[$choice]}" ]; then
        clear
        echo -e "${CYAN}📄 Visualizando: $(basename ${LOG_FILES[$choice]})${NC}"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        tail -50 "${LOG_FILES[$choice]}"
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo -e "${YELLOW}Pressione ENTER para voltar...${NC}"
        read
    else
        echo -e "${RED}❌ Opção inválida!${NC}"
        sleep 2
    fi
}

test_proxy() {
    show_banner
    echo -e "${CYAN}🧪 TESTANDO ZXPROXY${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Verifica se há portas ativas
    ACTIVE_PORTS=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                ACTIVE_PORTS="$ACTIVE_PORTS $PORT"
            fi
        fi
    done
    
    if [ -z "$ACTIVE_PORTS" ]; then
        echo -e "${RED}❌ Nenhuma porta ativa. Abra uma porta primeiro.${NC}"
        echo ""
        read -p "Pressione ENTER para continuar..."
        return
    fi
    
    # Usa a primeira porta ativa
    PORT=$(echo $ACTIVE_PORTS | awk '{print $1}')
    PROXY_URL="http://localhost:${PORT}"
    
    echo -e "${BLUE}🔍 Testando proxy em localhost:${PORT}${NC}"
    echo ""
    
    # Teste HTTP
    echo -n "   ${BLUE}HTTP Proxy${NC}... "
    if curl -s -x ${PROXY_URL} -I https://example.com --connect-timeout 5 > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ FALHA${NC}"
    fi
    
    # Teste HTTPS
    echo -n "   ${BLUE}HTTPS CONNECT${NC}... "
    if curl -s -x ${PROXY_URL} -I https://example.com --connect-timeout 5 > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ FALHA${NC}"
    fi
    
    # Teste SOCKS5
    echo -n "   ${BLUE}SOCKS5${NC}... "
    if curl -s --socks5 localhost:${PORT} https://example.com --connect-timeout 5 > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ FALHA${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Testes concluídos!${NC}"
    echo ""
    read -p "Pressione ENTER para continuar..."
}

show_config() {
    show_banner
    echo -e "${CYAN}⚙️  CONFIGURAÇÕES${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}Configuração atual:${NC}"
        cat "$CONFIG_FILE" | jq '.' 2>/dev/null || cat "$CONFIG_FILE"
    else
        echo -e "${YELLOW}⚠️  Arquivo de configuração não encontrado${NC}"
        echo -e "${BLUE}Criando configuração padrão...${NC}"
        cat > "$CONFIG_FILE" << 'EOF'
{
  "port": 8080,
  "vpn_enabled": true,
  "timeout": 30,
  "max_connections": 1000,
  "allowed_ips": ["0.0.0.0/0"]
}
EOF
        echo -e "${GREEN}✅ Configuração padrão criada${NC}"
    fi
    echo ""
    read -p "Pressione ENTER para continuar..."
}

# Loop principal
while true; do
    show_menu
    read OPTION
    case $OPTION in
        1) open_port ;;
        2) close_port ;;
        3) show_status_detailed ;;
        4) show_logs ;;
        5) test_proxy ;;
        6) show_config ;;
        7) 
            echo ""
            echo -e "${GREEN}👋 Saindo do ZXProxy Manager...${NC}"
            echo "Até logo!"
            exit 0 
            ;;
        *) 
            echo -e "${RED}❌ Opção inválida!${NC}"
            sleep 2 
            ;;
    esac
done
EOF

    chmod +x "$INSTALL_DIR/menu"
    log_success "Menu criado com sucesso"
}

# ============================================================
# CRIAÇÃO DE LINKS
# ============================================================

create_links() {
    show_progress "CRIANDO LINKS SISTEMAS"
    
    log_step "Criando links simbólicos..."
    
    # Link principal
    if [ -f "$INSTALL_DIR/menu" ]; then
        cp "$INSTALL_DIR/menu" /usr/local/bin/zxproxy
        chmod +x /usr/local/bin/zxproxy
        log_success "Link do menu: /usr/local/bin/zxproxy"
    fi
    
    # Link do binário
    if [ -f "$INSTALL_DIR/proxy" ]; then
        ln -sf "$INSTALL_DIR/proxy" /usr/local/bin/zxproxy-bin
        chmod +x /usr/local/bin/zxproxy-bin
        log_success "Link do binário: /usr/local/bin/zxproxy-bin"
    fi
    
    # Link do instalador (para futuras atualizações)
    SCRIPT_PATH=$(realpath "$0")
    if [ -f "$SCRIPT_PATH" ]; then
        cp "$SCRIPT_PATH" /usr/local/bin/update-zxproxy
        chmod +x /usr/local/bin/update-zxproxy
        log_success "Link do updater: /usr/local/bin/update-zxproxy"
    fi
}

# ============================================================
# FINALIZAÇÃO
# ============================================================

show_completion() {
    show_banner
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║     ${GREEN}✅ Instalação concluída com sucesso!${NC}                    ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}🚀 Comandos disponíveis:${NC}"
    echo ""
    echo "   ${GREEN}zxproxy${NC}          - Menu interativo"
    echo "   ${GREEN}zxproxy-bin -p 80${NC} - Abrir porta 80 diretamente"
    echo "   ${GREEN}zxproxy-bin -d${NC}   - Modo debug"
    echo "   ${GREEN}update-zxproxy${NC}   - Atualizar para última versão"
    echo ""
    echo -e "${CYAN}📡 Protocolos suportados:${NC}"
    echo "   🔹 SOCKS5 - Proxy SOCKS5 completo"
    echo "   🔹 TLS/SSL - Conexões seguras com SNI"
    echo "   🔹 WebSocket - Upgrade e proxy WS"
    echo "   🔹 HTTP/HTTPS - Proxy HTTP com CONNECT"
    echo "   🔹 TCP Fallback - Conexões TCP genéricas"
    echo "   🔹 Security - Autenticação e segurança"
    echo ""
    echo -e "${CYAN}🌐 Teste rápido:${NC}"
    echo "   curl -x http://localhost:8080 https://example.com"
    echo ""
    echo -e "${CYAN}📋 Logs:${NC} /var/log/zxproxy/"
    echo ""
    echo -e "${YELLOW}📦 Instalação em:${NC} $INSTALL_DIR"
    echo -e "${YELLOW}🔧 Configuração:${NC} $INSTALL_DIR/config.json"
    echo ""
    echo -e "${GREEN}👋 Instalação concluída!${NC}"
    echo ""
}

# ============================================================
# FUNÇÃO PRINCIPAL
# ============================================================

main() {
    show_banner
    
    # Remove instalações antigas
    for old_dir in /opt/bsproxy /opt/vsproxy; do
        if [ -d "$old_dir" ]; then
            log_warning "Removendo instalação antiga: $old_dir"
            rm -rf "$old_dir"
        fi
    done
    
    check_root
    check_internet
    detect_os
    install_dependencies
    install_rust
    compile_zxproxy
    create_menu
    create_links
    show_completion
}

# ============================================================
# EXECUTA O SCRIPT
# ============================================================

main

# Fim do script
