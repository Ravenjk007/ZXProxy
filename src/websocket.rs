use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::{Result, anyhow};
use log::{info, debug, error};
use http::Request;
use std::str;

pub async fn handle_websocket(mut socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    info!("🌐 Handling WebSocket/HTTP connection...");
    
    let mut buf = [0u8; 8192];
    let n = socket.read(&mut buf).await?;
    
    if n == 0 {
        return Err(anyhow!("Empty request"));
    }
    
    // Tenta parsear como HTTP
    let request_str = String::from_utf8_lossy(&buf[..n]);
    
    // Verifica se é WebSocket
    let is_websocket = request_str.contains("Upgrade: websocket") || 
                       request_str.contains("Upgrade: WebSocket") ||
                       request_str.contains("Sec-WebSocket-Key");
    
    if is_websocket {
        info!("🔌 WebSocket connection detected");
        handle_websocket_upgrade(socket, &buf[..n], vpn_enabled).await
    } else {
        info!("🌐 HTTP connection detected");
        handle_http_proxy(socket, &buf[..n], vpn_enabled).await
    }
}

async fn handle_websocket_upgrade(mut socket: TcpStream, data: &[u8], _vpn_enabled: bool) -> Result<()> {
    // Extrai host da requisição
    let request_str = String::from_utf8_lossy(data);
    let host = extract_host(&request_str).unwrap_or("localhost");
    let port = extract_port(&request_str).unwrap_or(80);
    
    info!("WebSocket proxy to {}:{}", host, port);
    
    // Conecta ao destino
    let mut dest = TcpStream::connect(format!("{}:{}", host, port)).await?;
    
    // Envia requisição original
    dest.write_all(data).await?;
    
    // Proxy bidirecional
    tokio::io::copy_bidirectional(&mut socket, &mut dest).await?;
    
    Ok(())
}

async fn handle_http_proxy(mut socket: TcpStream, data: &[u8], _vpn_enabled: bool) -> Result<()> {
    let request_str = String::from_utf8_lossy(data);
    
    // Verifica se é CONNECT (HTTPS)
    if request_str.starts_with("CONNECT") {
        return handle_https_connect(socket, data).await;
    }
    
    // Extrai host e porta
    let host = extract_host(&request_str).unwrap_or("localhost");
    let port = extract_port(&request_str).unwrap_or(80);
    
    info!("HTTP proxy to {}:{}", host, port);
    
    // Conecta ao destino
    let mut dest = TcpStream::connect(format!("{}:{}", host, port)).await?;
    
    // Envia requisição
    dest.write_all(data).await?;
    
    // Proxy bidirecional
    tokio::io::copy_bidirectional(&mut socket, &mut dest).await?;
    
    Ok(())
}

async fn handle_https_connect(mut socket: TcpStream, data: &[u8]) -> Result<()> {
    let request_str = String::from_utf8_lossy(data);
    let parts: Vec<&str> = request_str.split_whitespace().collect();
    
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
    
    info!("HTTPS CONNECT to {}:{}", host, port);
    
    // Conecta ao destino
    let dest = TcpStream::connect(format!("{}:{}", host, port)).await?;
    
    // Responde com 200 OK
    socket.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n").await?;
    
    // Proxy bidirecional
    tokio::io::copy_bidirectional(&mut socket, dest).await?;
    
    Ok(())
}

fn extract_host(request: &str) -> Option<String> {
    for line in request.lines() {
        if line.to_lowercase().starts_with("host:") {
            let host = line[5..].trim();
            return Some(host.split(':').next().unwrap_or(host).to_string());
        }
    }
    None
}

fn extract_port(request: &str) -> Option<u16> {
    for line in request.lines() {
        if line.to_lowercase().starts_with("host:") {
            let host = line[5..].trim();
            if let Some(port) = host.split(':').nth(1) {
                return port.parse().ok();
            }
        }
    }
    Some(80)
}
