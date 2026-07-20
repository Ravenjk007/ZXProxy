use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::{info, debug};
use std::collections::HashMap;

pub async fn handle_http(mut socket: TcpStream, peer_addr: std::net::SocketAddr) -> Result<()> {
    info!("🌐 [{}] HTTP Request", peer_addr);
    
    let mut buffer = [0u8; 4096];
    let n = socket.read(&mut buffer).await?;
    
    if n == 0 {
        return Ok(());
    }
    
    let request = String::from_utf8_lossy(&buffer[..n]);
    debug!("📩 [{}] Request:\n{}", peer_addr, request);
    
    // Parse da requisição
    let lines: Vec<&str> = request.lines().collect();
    if lines.is_empty() {
        return Ok(());
    }
    
    // Primeira linha: METHOD PATH PROTOCOL
    let first_line = lines[0];
    let parts: Vec<&str> = first_line.split_whitespace().collect();
    
    if parts.len() < 2 {
        return Ok(());
    }
    
    let method = parts[0];
    let path = parts[1];
    let version = if parts.len() >= 3 { parts[2] } else { "HTTP/1.1" };
    
    // Parse dos headers
    let mut headers = HashMap::new();
    for line in lines.iter().skip(1) {
        if line.is_empty() {
            break;
        }
        if let Some((key, value)) = line.split_once(':') {
            headers.insert(key.trim().to_lowercase(), value.trim().to_string());
        }
    }
    
    info!("🌐 [{}] {} {} {}", peer_addr, method, path, version);
    
    // Verificar se é CONNECT (HTTPS tunneling)
    if method == "CONNECT" {
        return handle_connect(socket, path, headers, peer_addr).await;
    }
    
    // Verificar se é WebSocket
    if headers.get("upgrade").map(|s| s.to_lowercase()) == Some("websocket".to_string()) {
        return handle_websocket_upgrade(socket, headers, peer_addr).await;
    }
    
    // Verificar se é um request para proxy
    if path.starts_with("http://") || path.starts_with("https://") {
        return handle_proxy_request(socket, method, path, headers, peer_addr).await;
    }
    
    // Resposta padrão para teste
    let response = format!(
        "HTTP/1.1 200 OK\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 20\r\n\
         Connection: keep-alive\r\n\
         Server: ZXProxy\r\n\
         \r\n\
         ZXProxy is working!"
    );
    
    socket.write_all(response.as_bytes()).await?;
    info!("✅ [{}] Response: 200 OK", peer_addr);
    
    Ok(())
}

async fn handle_websocket_upgrade(
    mut socket: TcpStream,
    headers: HashMap<String, String>,
    peer_addr: std::net::SocketAddr,
) -> Result<()> {
    info!("🌐 [{}] WebSocket Upgrade Request", peer_addr);
    
    // Extrair WebSocket key
    let ws_key = headers.get("sec-websocket-key")
        .map(|s| s.to_string())
        .unwrap_or_else(|| "dGhlIHNhbXBsZSBub25jZQ==".to_string());
    
    // Calcular accept key (simplificado)
    let accept_key = base64_encode(&ws_key);
    
    let response = format!(
        "HTTP/1.1 101 Switching Protocols\r\n\
         Upgrade: websocket\r\n\
         Connection: Upgrade\r\n\
         Sec-WebSocket-Accept: {}\r\n\
         \r\n",
        accept_key
    );
    
    socket.write_all(response.as_bytes()).await?;
    info!("✅ [{}] WebSocket 101 Switching Protocols", peer_addr);
    
    // Manter conexão aberta para WebSocket
    // Aqui você pode implementar o handshake WebSocket completo
    // Por enquanto, mantém a conexão viva
    tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;
    
    Ok(())
}

async fn handle_connect(
    mut socket: TcpStream,
    target: &str,
    _headers: HashMap<String, String>,
    peer_addr: std::net::SocketAddr,
) -> Result<()> {
    info!("🔗 [{}] CONNECT to {}", peer_addr, target);
    
    // Responder 200 Connection Established
    let response = "HTTP/1.1 200 Connection Established\r\n\
                   \r\n";
    socket.write_all(response.as_bytes()).await?;
    
    // Conectar ao destino
    let target_addr = if target.contains(':') {
        target.to_string()
    } else {
        format!("{}:443", target)
    };
    
    match TcpStream::connect(&target_addr).await {
        Ok(remote) => {
            info!("✅ [{}] Connected to {}", peer_addr, target_addr);
            let (mut client_reader, mut client_writer) = socket.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
        }
        Err(e) => {
            info!("❌ [{}] Failed to connect to {}: {}", peer_addr, target_addr, e);
        }
    }
    
    Ok(())
}

async fn handle_proxy_request(
    mut socket: TcpStream,
    method: &str,
    path: &str,
    headers: HashMap<String, String>,
    peer_addr: std::net::SocketAddr,
) -> Result<()> {
    info!("📦 [{}] Proxy {} {}", peer_addr, method, path);
    
    // Extrair host e porta do path
    let url = path;
    let host = headers.get("host").unwrap_or(&"unknown".to_string());
    
    // Para apps VPN, respondemos com 200 OK para qualquer request
    // Isso permite que o app VPN estabeleça a conexão
    let response = format!(
        "HTTP/1.1 200 OK\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 12\r\n\
         Connection: keep-alive\r\n\
         Server: ZXProxy\r\n\
         \r\n\
         OK"
    );
    
    socket.write_all(response.as_bytes()).await?;
    info!("✅ [{}] Proxy Response: 200 OK for {}", peer_addr, host);
    
    Ok(())
}

// Função simples de base64 para WebSocket Accept
fn base64_encode(input: &str) -> String {
    // Implementação simplificada - em produção use uma biblioteca
    use base64::Engine;
    let input_bytes = input.as_bytes();
    let combined = [input_bytes, b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"].concat();
    let hash = sha1::Sha1::from(&combined).digest().bytes();
    base64::engine::general_purpose::STANDARD.encode(&hash)
}
