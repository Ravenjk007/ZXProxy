use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::Result;
use log::info;
use sha1::{Sha1, Digest};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;

pub async fn handle(mut socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket handshake...");
    
    // Ler requisição HTTP
    let mut buf = [0u8; 4096];
    let n = socket.read(&mut buf).await?;
    let request = String::from_utf8_lossy(&buf[..n]);
    
    info!("📩 WebSocket request:\n{}", request);
    
    // Extrair WebSocket key
    let key = request
        .lines()
        .find(|line| line.starts_with("Sec-WebSocket-Key:"))
        .and_then(|line| line.split(':').nth(1))
        .map(|s| s.trim())
        .unwrap_or("");
    
    if key.is_empty() {
        anyhow::bail!("WebSocket key not found");
    }
    
    // Gerar resposta de handshake
    let accept_key = generate_accept_key(key);
    let response = format!(
        "HTTP/1.1 101 Switching Protocols\r\n\
         Upgrade: websocket\r\n\
         Connection: Upgrade\r\n\
         Sec-WebSocket-Accept: {}\r\n\
         \r\n",
        accept_key
    );
    
    socket.write_all(response.as_bytes()).await?;
    info!("🌐 WebSocket handshake complete!");
    
    // Agora fazer proxy WebSocket (echo simples)
    loop {
        let mut header = [0u8; 2];
        match socket.read_exact(&mut header).await {
            Ok(_) => {
                let fin = (header[0] & 0x80) != 0;
                let opcode = header[0] & 0x0F;
                let masked = (header[1] & 0x80) != 0;
                let mut payload_len = (header[1] & 0x7F) as u64;
                
                // Ler payload length estendido
                if payload_len == 126 {
                    let mut ext_len = [0u8; 2];
                    socket.read_exact(&mut ext_len).await?;
                    payload_len = u16::from_be_bytes(ext_len) as u64;
                } else if payload_len == 127 {
                    let mut ext_len = [0u8; 8];
                    socket.read_exact(&mut ext_len).await?;
                    payload_len = u64::from_be_bytes(ext_len);
                }
                
                // Ler mascara se houver
                let mask = if masked {
                    let mut mask_bytes = [0u8; 4];
                    socket.read_exact(&mut mask_bytes).await?;
                    Some(mask_bytes)
                } else {
                    None
                };
                
                // Ler payload
                let mut payload = vec![0u8; payload_len as usize];
                socket.read_exact(&mut payload).await?;
                
                // Desmascarar se necessário
                if let Some(mask) = mask {
                    for (i, byte) in payload.iter_mut().enumerate() {
                        *byte ^= mask[i % 4];
                    }
                }
                
                let msg = String::from_utf8_lossy(&payload);
                info!("📩 WebSocket message: {}", msg);
                
                // Se for close frame, encerrar
                if opcode == 0x08 {
                    info!("🔚 WebSocket close frame received");
                    break;
                }
                
                // Responder eco (com texto)
                let response_data = format!("ECHO: {}", msg);
                let response_bytes = response_data.as_bytes();
                
                // Montar frame de resposta (sem máscara)
                let mut response_frame = Vec::new();
                response_frame.push(0x81); // FIN + opcode text
                
                let len = response_bytes.len();
                if len <= 125 {
                    response_frame.push(len as u8);
                } else if len <= 65535 {
                    response_frame.push(126);
                    response_frame.extend_from_slice(&(len as u16).to_be_bytes());
                } else {
                    response_frame.push(127);
                    response_frame.extend_from_slice(&(len as u64).to_be_bytes());
                }
                
                response_frame.extend_from_slice(response_bytes);
                socket.write_all(&response_frame).await?;
            }
            Err(e) => {
                info!("WebSocket error: {}", e);
                break;
            }
        }
    }
    
    Ok(())
}

fn generate_accept_key(key: &str) -> String {
    const WS_GUID: &str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    let combined = format!("{}{}", key, WS_GUID);
    let mut hasher = Sha1::new();
    hasher.update(combined.as_bytes());
    let result = hasher.finalize();
    BASE64.encode(&result)
}
