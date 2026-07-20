use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error};

mod socks5;
mod tls;
mod websocket;
mod tcp_fallback;
mod security;
mod http;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "ZXProxy - Multiprotocol VPN/HTTP Inject")]
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
    info!("📡 Protocols: SOCKS5, TLS, WebSocket, HTTP, SECURITY, TCP");
    info!("💡 Multiprotocol Mode: Auto-detect and handle");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buf = [0u8; 1024];
            
            match socket.peek(&mut buf).await {
                Ok(n) if n > 0 => {
                    let protocol = detect_protocol(&buf[..n]);
                    info!("📡 [{}] Protocol: {}", peer_addr, protocol);
                    
                    let result = match protocol {
                        "SOCKS5" => socks5::handle_socks5(socket).await,
                        "TLS" => tls::handle_tls(socket).await,
                        "WEBSOCKET" => websocket::handle_websocket(socket).await,
                        "HTTP" => http::handle_http(socket).await,
                        "SECURITY" => security::handle_security(socket).await,
                        _ => tcp_fallback::handle_tcp(socket).await,
                    };
                    
                    if let Err(e) = result {
                        error!("❌ [{}] Error: {}", peer_addr, e);
                    }
                }
                Ok(_) => info!("📦 [{}] Connection closed", peer_addr),
                Err(e) => error!("❌ [{}] Peek error: {}", peer_addr, e),
            }
        });
    }
    Ok(())
}

fn detect_protocol(data: &[u8]) -> &'static str {
    if data.is_empty() { return "UNKNOWN"; }
    
    // HTTP/WebSocket
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
    
    // SOCKS5
    if data.len() >= 1 && data[0] == 0x05 { return "SOCKS5"; }
    
    // TLS
    if data.len() >= 3 && data[0] == 0x16 { return "TLS"; }
    
    "TCP"
}
