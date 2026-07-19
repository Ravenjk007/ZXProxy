mod socks5;
mod tls;
mod websocket;
mod tcp_fallback;
mod security;

use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error, warn};
use std::sync::Arc;
use std::collections::HashMap;
use tokio::sync::Mutex;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "ZXProxy - Multiprotocol proxy server with VPN capabilities")]
struct Cli {
    #[arg(short = 'p', long = "port", default_value = "8080")]
    port: u16,
    #[arg(short = 'd', long = "debug")]
    debug: bool,
    #[arg(short = 'v', long = "vpn", default_value = "true")]
    vpn: bool,
}

// Estatísticas globais
struct ProxyStats {
    connections: usize,
    bytes_transferred: u64,
    protocols: HashMap<String, usize>,
}

impl ProxyStats {
    fn new() -> Self {
        Self {
            connections: 0,
            bytes_transferred: 0,
            protocols: HashMap::new(),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Configuração de logging
    if cli.debug {
        env_logger::builder()
            .filter_level(log::LevelFilter::Debug)
            .init();
    } else {
        env_logger::builder()
            .filter_level(log::LevelFilter::Info)
            .init();
    }
    
    let addr = format!("0.0.0.0:{}", cli.port);
    let listener = TcpListener::bind(&addr).await?;
    
    info!("╔══════════════════════════════════════════════╗");
    info!("║         🚀 ZXProxy Server v2.0              ║");
    info!("║    Multiprotocol Proxy with VPN Support      ║");
    info!("╚══════════════════════════════════════════════╝");
    info!("📡 Listening on: {}", addr);
    info!("🔒 VPN Mode: {}", if cli.vpn { "ENABLED" } else { "DISABLED" });
    info!("📦 Supported Protocols:");
    info!("   • SOCKS5 (Port 1080)");
    info!("   • TLS/SSL");
    info!("   • WebSocket (WS/WSS)");
    info!("   • HTTP/HTTPS");
    info!("   • TCP Fallback");
    info!("   • Security/Auth");
    info!("");

    let stats = Arc::new(Mutex::new(ProxyStats::new()));

    while let Ok((mut socket, addr)) = listener.accept().await {
        let stats_clone = stats.clone();
        let vpn_enabled = cli.vpn;
        
        tokio::spawn(async move {
            let mut buf = [0u8; 1024];
            
            // Aguarda dados iniciais
            match socket.peek(&mut buf).await {
                Ok(n) if n > 0 => {
                    // Detecção avançada de protocolo
                    let protocol = detect_protocol(&buf, n);
                    
                    // Atualiza estatísticas
                    {
                        let mut stats = stats_clone.lock().await;
                        stats.connections += 1;
                        *stats.protocols.entry(protocol.to_string()).or_insert(0) += 1;
                    }
                    
                    info!("📥 New connection from {} - Protocol: {}", addr, protocol);
                    
                    // Processa de acordo com o protocolo
                    let result = match protocol {
                        "SOCKS5" => socks5::handle_socks5(socket, vpn_enabled).await,
                        "TLS" => tls::handle_tls(socket, vpn_enabled).await,
                        "WEBSOCKET" => websocket::handle_websocket(socket, vpn_enabled).await,
                        "HTTP" => websocket::handle_websocket(socket, vpn_enabled).await, // HTTP é tratado como WebSocket
                        "SECURITY" => security::handle_security(socket, vpn_enabled).await,
                        _ => tcp_fallback::handle_tcp(socket, vpn_enabled).await,
                    };
                    
                    if let Err(e) = result {
                        error!("❌ Error handling {} connection: {}", protocol, e);
                    } else {
                        info!("✅ {} connection closed successfully", protocol);
                    }
                }
                Ok(_) => warn!("⚠️ Connection closed without data from {}", addr),
                Err(e) => error!("❌ Peek error from {}: {}", addr, e),
            }
        });
    }
    
    Ok(())
}

// Detecção inteligente de protocolo
fn detect_protocol(buf: &[u8], n: usize) -> &'static str {
    // SOCKS5
    if n > 0 && buf[0] == 0x05 {
        return "SOCKS5";
    }
    
    // TLS/SSL (handshake)
    if n > 1 && buf[0] == 0x16 && (buf[1] == 0x03 || buf[1] == 0x02) {
        return "TLS";
    }
    
    // HTTP/WebSocket
    if let Ok(data) = std::str::from_utf8(&buf[..n]) {
        if data.starts_with("GET ") || 
           data.starts_with("POST ") || 
           data.starts_with("PUT ") || 
           data.starts_with("DELETE ") || 
           data.starts_with("HEAD ") || 
           data.starts_with("CONNECT ") || 
           data.starts_with("OPTIONS ") || 
           data.starts_with("PATCH ") || 
           data.starts_with("TRACE ") ||
           data.starts_with("HTTP/") {
            // Verifica se é WebSocket
            if data.contains("Upgrade: websocket") || data.contains("Upgrade: WebSocket") {
                return "WEBSOCKET";
            }
            return "HTTP";
        }
        
        // Security protocol
        if data.starts_with("SECURITY") || 
           data.starts_with("AUTH") || 
           data.starts_with("AUTHENTICATE") {
            return "SECURITY";
        }
    }
    
    // TCP Fallback
    "TCP"
}
