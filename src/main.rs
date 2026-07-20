use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error, debug};
use std::collections::HashMap;

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
    
    // Ler os primeiros dados para detectar o protocolo
    let n = socket.peek(&mut buf).await?;
    
    if n == 0 {
        info!("📦 [{}] Connection closed", peer_addr);
        return Ok(());
    }
    
    // Detectar protocolo
    let protocol = detect_protocol(&buf[..n]);
    info!("📡 [{}] Protocol: {}", peer_addr, protocol);
    
    match protocol {
        "HTTP" => {
            // Handshake HTTP completo
            http_handler::handle_http(socket, peer_addr).await?;
        }
        "WEBSOCKET" => {
            websocket::handle_websocket(socket).await?;
        }
        "SOCKS5" => {
            socks5::handle_socks5(socket).await?;
        }
        "TLS" => {
            tls::handle_tls(socket).await?;
        }
        "SECURITY" => {
            security::handle_security(socket).await?;
        }
        _ => {
            tcp_fallback::handle_tcp(socket).await?;
        }
    }
    
    Ok(())
}

fn detect_protocol(data: &[u8]) -> &'static str {
    if data.is_empty() {
        return "UNKNOWN";
    }
    
    // Verificar HTTP
    if let Ok(text) = std::str::from_utf8(data) {
        // Verificar se é uma requisição HTTP
        if text.starts_with("GET ") || 
           text.starts_with("POST ") || 
           text.starts_with("PUT ") || 
           text.starts_with("DELETE ") || 
           text.starts_with("CONNECT ") ||
           text.starts_with("HEAD ") ||
           text.starts_with("OPTIONS ") ||
           text.starts_with("PATCH ") ||
           text.starts_with("HTTP/") {
            
            // Verificar se é WebSocket
            if text.contains("Upgrade: websocket") || 
               text.contains("upgrade: websocket") ||
               text.contains("Sec-WebSocket-Key") {
                return "WEBSOCKET";
            }
            return "HTTP";
        }
    }
    
    // Verificar SOCKS5
    if data.len() >= 1 && data[0] == 0x05 {
        return "SOCKS5";
    }
    
    // Verificar TLS
    if data.len() >= 3 && data[0] == 0x16 {
        let version = ((data[1] as u16) << 8) | data[2] as u16;
        if version >= 0x0301 && version <= 0x0304 {
            return "TLS";
        }
        return "SECURITY";
    }
    
    // Verificar SECURITY/AUTH
    if let Ok(text) = std::str::from_utf8(data) {
        if text.starts_with("SECURITY") || text.starts_with("AUTH") {
            return "SECURITY";
        }
    }
    
    "TCP"
}
