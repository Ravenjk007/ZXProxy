mod socks5;
mod tls;
mod websocket;
mod tcp_fallback;
mod security;
mod http;
mod https;

use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error};
use std::time::Duration;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "Multiprotocol proxy server - ZXProxy")]
struct Cli {
    #[arg(short = 'p', long = "port", default_value = "8080")]
    port: u16,
    #[arg(short = 'd', long = "debug")]
    debug: bool,
    #[arg(short = 's', long = "ssl")]
    ssl: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    if cli.debug {
        env_logger::init();
    } else {
        env_logger::builder()
            .filter_level(log::LevelFilter::Info)
            .format_timestamp_millis()
            .init();
    }
    
    let addr = format!("0.0.0.0:{}", cli.port);
    let listener = TcpListener::bind(&addr).await?;
    info!("🚀 ZXProxy listening on {}", addr);
    info!("📡 Protocols: SOCKS5, TLS, WebSocket, HTTP, HTTPS, SECURITY, TCP");
    info!("💡 Multiprotocol Mode: Auto-detect and handle");

    while let Ok((socket, peer_addr)) = listener.accept().await {
        let peer = peer_addr;
        tokio::spawn(async move {
            let mut buf = [0u8; 1024];
            
            match socket.peek(&mut buf).await {
                Ok(n) if n > 0 => {
                    let protocol = detect_protocol(&buf[..n]);
                    info!("📡 [{}] Protocol: {}", peer, protocol);
                    
                    let result = match protocol {
                        "SOCKS5" => socks5::handle_socks5(socket).await,
                        "TLS" => tls::handle_tls(socket).await,
                        "WEBSOCKET" => websocket::handle_websocket(socket).await,
                        "HTTP" => http::handle_http(socket).await,
                        "HTTPS" => https::handle_https(socket).await,
                        "SECURITY" => security::handle_security(socket).await,
                        _ => tcp_fallback::handle_tcp(socket).await,
                    };
                    
                    if let Err(e) = result {
                        error!("❌ [{}] Error: {}", peer, e);
                    }
                }
                Ok(_) => info!("📦 [{}] Connection closed", peer),
                Err(e) => error!("❌ [{}] Peek error: {}", peer, e),
            }
        });
    }
    Ok(())
}

fn detect_protocol(data: &[u8]) -> &'static str {
    if data.is_empty() { return "UNKNOWN"; }
    
    // SOCKS5
    if data.len() >= 1 && data[0] == 0x05 {
        return "SOCKS5";
    }
    
    // TLS
    if data.len() >= 3 && data[0] == 0x16 {
        let version = ((data[1] as u16) << 8) | data[2] as u16;
        if version >= 0x0301 && version <= 0x0304 {
            return "TLS";
        }
        return "SECURITY";
    }
    
    // HTTP/WebSocket
    if let Ok(text) = std::str::from_utf8(data) {
        let text_lower = text.to_lowercase();
        
        // WebSocket
        if text_lower.contains("upgrade: websocket") || 
           text_lower.contains("sec-websocket-key") {
            return "WEBSOCKET";
        }
        
        // HTTPS (CONNECT method)
        if text.starts_with("CONNECT ") {
            return "HTTPS";
        }
        
        // HTTP
        if text.starts_with("GET ") || 
           text.starts_with("POST ") || 
           text.starts_with("PUT ") || 
           text.starts_with("DELETE ") || 
           text.starts_with("PATCH ") || 
           text.starts_with("HEAD ") || 
           text.starts_with("OPTIONS ") || 
           text.starts_with("TRACE ") || 
           text.contains("HTTP/") {
            return "HTTP";
        }
        
        // SECURITY
        if text.starts_with("SECURITY") || text.starts_with("AUTH") {
            return "SECURITY";
        }
    }
    
    "TCP"
}
