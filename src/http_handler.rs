use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::{info, debug, warn};
use std::collections::HashMap;

pub async fn handle_http(mut socket: TcpStream, peer_addr: std::net::SocketAddr) -> Result<()> {
    info!("🌐 [{}] HTTP Request", peer_addr);
    
    // Ler todos os dados disponíveis
    let mut buffer = vec![0u8; 8192];
    let n = socket.read(&mut buffer).await?;
    
    if n == 0 {
        return Ok(());
    }
    
    let request_data = &buffer[..n];
    let request_str = String::from_utf8_lossy(request_data);
    
    debug!("📩 [{}] Raw request:\n{}", peer_addr, request_str);
    
    // Verificar se é um request HTTP válido
    let is_http = request_str.contains("HTTP") || 
                  request_str.starts_with("GET ") || 
                  request_str.starts_with("POST ") ||
                  request_str.starts_with("CONNECT ") ||
                  request_str.starts_with("PUT ") ||
                  request_str.starts_with("DELETE ") ||
                  request_str.starts_with("HEAD ") ||
                  request_str.starts_with("OPTIONS ") ||
                  request_str.starts_with("PATCH ");
    
    if !is_http {
        // Se não for HTTP, tratar como TCP
        info!("📦 [{}] Non-HTTP request, treating as TCP", peer_addr);
        socket.write_all(b"ZXProxy TCP OK\n").await?;
        return Ok(());
    }
    
    // Verificar se é WebSocket (procura por Upgrade: websocket)
    let is_websocket = request_str.to_lowercase().contains("upgrade: websocket") ||
                       request_str.to_lowercase().contains("sec-websocket-key");
    
    if is_websocket {
        // Responder com 101 Switching Protocols
        info!("🌐 [{}] WebSocket Upgrade Request", peer_addr);
        
        // Extrair Sec-WebSocket-Key
        let ws_key = extract_websocket_key(&request_str);
        
        let response = format!(
            "HTTP/1.1 101 Switching Protocols\r\n\
             Upgrade: websocket\r\n\
             Connection: Upgrade\r\n\
             Sec-WebSocket-Accept: {}\r\n\
             \r\n",
            ws_key
        );
        
        socket.write_all(response.as_bytes()).await?;
        info!("✅ [{}] WebSocket 101 Switching Protocols", peer_addr);
        
        // Manter conexão viva para WebSocket
        tokio::time::sleep(tokio::time::Duration::from_secs(300)).await;
        return Ok(());
    }
    
    // Verificar se é CONNECT (HTTPS tunnel)
    if request_str.starts_with("CONNECT ") {
        info!("🔗 [{}] CONNECT request", peer_addr);
        let response = "HTTP/1.1 200 Connection Established\r\n\r\n";
        socket.write_all(response.as_bytes()).await?;
        return Ok(());
    }
    
    // Para qualquer outro request HTTP, responder com 200 OK
    // Isso é o que o app VPN espera
    info!("✅ [{}] Responding with 200 OK", peer_addr);
    
    let response = "HTTP/1.1 200 OK\r\n\
                    Content-Type: text/plain\r\n\
                    Content-Length: 12\r\n\
                    Connection: keep-alive\r\n\
                    Server: ZXProxy\r\n\
                    \r\n\
                    OK";
    
    socket.write_all(response.as_bytes()).await?;
    info!("✅ [{}] HTTP 200 OK sent", peer_addr);
    
    Ok(())
}

fn extract_websocket_key(request: &str) -> String {
    // Procurar por Sec-WebSocket-Key
    for line in request.lines() {
        let line_lower = line.to_lowercase();
        if line_lower.contains("sec-websocket-key") {
            if let Some((_, value)) = line.split_once(':') {
                let key = value.trim();
                // Calcular accept key (simplificado para demo)
                return format!("dGhlIHNhbXBsZSBub25jZQ==");
            }
        }
    }
    "dGhlIHNhbXBsZSBub25jZQ==".to_string()
}
