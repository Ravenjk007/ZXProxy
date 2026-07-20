mod socks5;
mod tls;
mod websocket;
mod tcp_fallback;
mod security;
mod http;
mod https;
mod ssh_tunnel;
mod vpn_forward;
mod metrics;

use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error, warn, debug};
use std::sync::Arc;
use tokio::sync::RwLock;
use metrics::Metrics;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "Multiprotocol proxy server - ZXProxy")]
struct Cli {
    #[arg(short = 'p', long = "port", default_value = "8080")]
    port: u16,
    #[arg(short = 'd', long = "debug")]
    debug: bool,
    #[arg(short = 'v', long = "verbose")]
    verbose: bool,
    #[arg(short = 'm', long = "metrics")]
    metrics: bool,
}

#[derive(Clone)]
struct AppState {
    metrics: Arc<RwLock<Metrics>>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Configuração de logging
    let log_level = if cli.debug {
        log::LevelFilter::Debug
    } else if cli.verbose {
        log::LevelFilter::Info
    } else {
        log::LevelFilter::Warn
    };
    
    env_logger::builder()
        .filter_level(log_level)
        .format_timestamp_millis()
        .init();
    
    let state = AppState {
        metrics: Arc::new(RwLock::new(Metrics::new())),
    };
    
    // Iniciar servidor de métricas se solicitado
    if cli.metrics {
        let state_clone = state.clone();
        tokio::spawn(async move {
            metrics::start_metrics_server(state_clone).await;
        });
    }
    
    let addr = format!("0.0.0.0:{}", cli.port);
    let listener = TcpListener::bind(&addr).await?;
    info!("🚀 ZXProxy listening on {}", addr);
    info!("📡 Protocols: SOCKS5, TLS, WebSocket, HTTP, HTTPS, SSH Tunnel, VPN, Security, TCP Fallback");
    info!("📊 Metrics: {}", if cli.metrics { "Enabled on :9090" } else { "Disabled" });

    while let Ok((socket, peer_addr)) = listener.accept().await {
        let state_clone = state.clone();
        tokio::spawn(async move {
            handle_connection(socket, peer_addr, state_clone).await;
        });
    }
    Ok(())
}

async fn handle_connection(mut socket: tokio::net::TcpStream, peer_addr: std::net::SocketAddr, state: AppState) {
    let mut buf = [0u8; 1024];
    
    match socket.peek(&mut buf).await {
        Ok(n) if n > 0 => {
            let protocol = detect_protocol(&buf[..n]);
            info!("📡 [{}] Protocol: {}", peer_addr, protocol);
            
            // Atualizar métricas
            {
                let mut metrics = state.metrics.write().await;
                metrics.record_connection(&protocol);
            }
            
            let result = match protocol {
                "SOCKS5" => socks5::handle_socks5(socket).await,
                "TLS" => tls::handle_tls(socket).await,
                "HTTPS" => https::handle_https(socket).await,
                "HTTP" => http::handle_http(socket).await,
                "WEBSOCKET" => websocket::handle_websocket(socket).await,
                "SSH_TUNNEL" => ssh_tunnel::handle_ssh_tunnel(socket).await,
                "VPN" => vpn_forward::handle_vpn(socket).await,
                "SECURITY" => security::handle_security(socket).await,
                _ => tcp_fallback::handle_tcp(socket).await,
            };
            
            if let Err(e) = result {
                error!("❌ [{}] Error: {}", peer_addr, e);
                {
                    let mut metrics = state.metrics.write().await;
                    metrics.record_error(&protocol);
                }
            } else {
                info!("✅ [{}] Connection closed", peer_addr);
                {
                    let mut metrics = state.metrics.write().await;
                    metrics.record_success(&protocol);
                }
            }
        }
        Ok(_) => warn!("⚠️ [{}] Connection closed immediately", peer_addr),
        Err(e) => error!("❌ [{}] Peek error: {}", peer_addr, e),
    }
}

fn detect_protocol(data: &[u8]) -> &'static str {
    if data.is_empty() {
        return "UNKNOWN";
    }
    
    // Verificar por HTTP
    if data.len() >= 8 {
        if let Ok(text) = std::str::from_utf8(&data[..8]) {
            let text_lower = text.to_lowercase();
            if text_lower.starts_with("get ") || 
               text_lower.starts_with("post ") || 
               text_lower.starts_with("put ") || 
               text_lower.starts_with("delete ") || 
               text_lower.starts_with("connect ") ||
               text_lower.starts_with("http/") {
                return "HTTP";
            }
        }
    }
    
    // Verificar por WebSocket
    if data.len() >= 4 && data.starts_with(b"GET ") {
        if let Ok(text) = std::str::from_utf8(data) {
            if text.contains("Upgrade: websocket") || 
               text.contains("upgrade: websocket") ||
               text.contains("Sec-WebSocket-Key") {
                return "WEBSOCKET";
            }
        }
    }
    
    // Verificar por SSH
    if data.len() >= 4 && data.starts_with(b"SSH-") {
        return "SSH_TUNNEL";
    }
    
    // Verificar por VPN (OpenVPN, WireGuard, etc)
    if data.len() >= 4 {
        if data.starts_with(b"\x00\x00\x00\x00") || // OpenVPN
           data.starts_with(b"OpenVPN") ||
           data.starts_with(b"WireGuard") ||
           data.starts_with(b"IPSec") ||
           data.starts_with(b"L2TP") {
            return "VPN";
        }
    }
    
    match data[0] {
        0x05 => "SOCKS5",
        0x16 => {
            // TLS
            if data.len() >= 3 {
                let version = ((data[1] as u16) << 8) | data[2] as u16;
                if version >= 0x0301 && version <= 0x0304 {
                    "TLS"
                } else {
                    "SECURITY"
                }
            } else {
                "TLS"
            }
        }
        0x04 => "SOCKS4",
        0x45 | 0x46 | 0x47 => "HTTP",
        _ => {
            // Tentar detectar outros protocolos
            if data.len() >= 4 && 
               data[0] == 0x47 && data[1] == 0x45 && data[2] == 0x54 && data[3] == 0x20 {
                "HTTP"
            } else if data.len() >= 4 && 
                      data[0] == 0x50 && data[1] == 0x4F && data[2] == 0x53 && data[3] == 0x54 {
                "HTTP"
            } else if data.starts_with(b"SECURITY") || data.starts_with(b"AUTH") {
                "SECURITY"
            } else {
                "TCP"
            }
        }
    }
}
