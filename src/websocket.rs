use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::{info, warn};
use std::time::Duration;

/// Lê e descarta os headers HTTP até encontrar \r\n\r\n
async fn consume_http_headers(socket: &mut TcpStream) -> std::io::Result<()> {
    let mut buf: Vec<u8> = Vec::new();
    let mut tmp = [0u8; 1];

    loop {
        socket.read_exact(&mut tmp).await?;
        buf.push(tmp[0]);

        if buf.len() >= 4 && &buf[buf.len() - 4..] == b"\r\n\r\n" {
            break;
        }
        if buf.len() > 8192 {
            break;
        }
    }
    Ok(())
}

/// Extrai a WebSocket Key do header
fn extract_websocket_key(request: &str) -> String {
    for line in request.lines() {
        let line_lower = line.to_lowercase();
        if line_lower.contains("sec-websocket-key") {
            if let Some((_, value)) = line.split_once(':') {
                return value.trim().to_string();
            }
        }
    }
    "dGhlIHNhbXBsZSBub25jZQ==".to_string()
}

/// Gera o accept key para WebSocket
fn generate_websocket_accept(key: &str) -> String {
    // Versão simplificada para demo
    // Em produção use: base64(sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
    "dGhlIHNhbXBsZSBub25jZQ==".to_string()
}

pub async fn handle_websocket(mut socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket/HTTP handshake...");
    
    // Ler os headers HTTP
    let mut buffer = vec![0u8; 8192];
    let n = socket.read(&mut buffer).await?;
    
    if n == 0 {
        info!("📦 Conexão vazia");
        return Ok(());
    }
    
    let request = String::from_utf8_lossy(&buffer[..n]);
    let first_line = request.lines().next().unwrap_or("");
    info!("📩 Request: {}", first_line);
    
    // Verificar se é WebSocket
    let is_websocket = request.to_lowercase().contains("upgrade: websocket") ||
                       request.to_lowercase().contains("sec-websocket-key");
    
    if !is_websocket {
        // Se não for WebSocket, responder como HTTP normal
        info!("🌐 HTTP request (not WebSocket)");
        let response = "HTTP/1.1 200 OK\r\n\
                        Content-Type: text/plain\r\n\
                        Content-Length: 2\r\n\
                        Connection: keep-alive\r\n\
                        Server: ZXProxy\r\n\
                        \r\n\
                        OK";
        socket.write_all(response.as_bytes()).await?;
        info!("✅ HTTP 200 OK sent");
        
        // Keep-Alive para HTTP
        let mut interval = tokio::time::interval(Duration::from_secs(15));
        loop {
            interval.tick().await;
            if socket.write_all(b"\r\n").await.is_err() {
                info!("🔚 Conexão HTTP encerrada");
                break;
            }
        }
        return Ok(());
    }
    
    // Extrair WebSocket Key
    let ws_key = extract_websocket_key(&request);
    let accept_key = generate_websocket_accept(&ws_key);
    
    // Resposta de upgrade WebSocket (101 Switching Protocols)
    let response = format!(
        "HTTP/1.1 101 Switching Protocols\r\n\
         Upgrade: websocket\r\n\
         Connection: Upgrade\r\n\
         Sec-WebSocket-Accept: {}\r\n\
         \r\n",
        accept_key
    );
    
    socket.write_all(response.as_bytes()).await?;
    info!("🌐 WebSocket handshake complete! (101 Switching Protocols)");
    
    // Opção 1: Encaminhar para SSH (porta 22)
    let target = "127.0.0.1:22";
    
    match TcpStream::connect(target).await {
        Ok(remote) => {
            info!("✅ Conectado ao SSH na porta 22");
            let (mut client_reader, mut client_writer) = socket.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            
            // Bidirecional
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
            
            info!("🔚 Conexão WebSocket->SSH encerrada");
            Ok(())
        }
        Err(e) => {
            warn!("❌ Falha ao conectar ao SSH: {}", e);
            
            // Se não conseguir conectar ao SSH, manter conexão viva com WebSocket pings
            info!("💓 Mantendo WebSocket vivo com pings...");
            let mut interval = tokio::time::interval(Duration::from_secs(10));
            let mut counter = 0;
            
            loop {
                interval.tick().await;
                counter += 1;
                
                // WebSocket ping frame (opcode 0x9)
                let ping_frame = [0x89, 0x00];
                
                match socket.write_all(&ping_frame).await {
                    Ok(_) => info!("💓 WebSocket ping #{} enviado", counter),
                    Err(_) => {
                        info!("🔚 Conexão WebSocket encerrada");
                        break;
                    }
                }
            }
            
            Ok(())
        }
    }
}

/// Versão alternativa: manter WebSocket vivo sem SSH
pub async fn handle_websocket_keepalive(mut socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket Keep-Alive mode");
    
    let mut buffer = vec![0u8; 8192];
    let n = socket.read(&mut buffer).await?;
    
    if n == 0 {
        return Ok(());
    }
    
    let request = String::from_utf8_lossy(&buffer[..n]);
    let ws_key = extract_websocket_key(&request);
    let accept_key = generate_websocket_accept(&ws_key);
    
    let response = format!(
        "HTTP/1.1 101 Switching Protocols\r\n\
         Upgrade: websocket\r\n\
         Connection: Upgrade\r\n\
         Sec-WebSocket-Accept: {}\r\n\
         \r\n",
        accept_key
    );
    
    socket.write_all(response.as_bytes()).await?;
    info!("✅ WebSocket 101 Switching Protocols");
    
    // Manter WebSocket vivo com pings
    let mut interval = tokio::time::interval(Duration::from_secs(10));
    let mut counter = 0;
    
    loop {
        interval.tick().await;
        counter += 1;
        
        // WebSocket ping frame
        let ping_frame = [0x89, 0x00];
        
        match socket.write_all(&ping_frame).await {
            Ok(_) => info!("💓 WebSocket ping #{}", counter),
            Err(_) => {
                info!("🔚 WebSocket connection closed");
                break;
            }
        }
    }
    
    Ok(())
}
