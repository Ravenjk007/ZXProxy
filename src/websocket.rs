use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

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

pub async fn handle_websocket(mut socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket handshake...");
    
    consume_http_headers(&mut socket).await?;
    
    let response = "HTTP/1.1 101 Switching Protocols\r\n\
                    Upgrade: websocket\r\n\
                    Connection: Upgrade\r\n\
                    Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                    \r\n";
    
    socket.write_all(response.as_bytes()).await?;
    info!("🌐 WebSocket handshake complete!");
    
    // Eco simples para teste
    loop {
        let mut header = [0u8; 2];
        match socket.read_exact(&mut header).await {
            Ok(_) => {
                let opcode = header[0] & 0x0F;
                let mut payload_len = (header[1] & 0x7F) as u64;
                
                if payload_len == 126 {
                    let mut ext_len = [0u8; 2];
                    socket.read_exact(&mut ext_len).await?;
                    payload_len = u16::from_be_bytes(ext_len) as u64;
                } else if payload_len == 127 {
                    let mut ext_len = [0u8; 8];
                    socket.read_exact(&mut ext_len).await?;
                    payload_len = u64::from_be_bytes(ext_len);
                }
                
                let masked = (header[1] & 0x80) != 0;
                let mask = if masked {
                    let mut mask_bytes = [0u8; 4];
                    socket.read_exact(&mut mask_bytes).await?;
                    Some(mask_bytes)
                } else {
                    None
                };
                
                let mut payload = vec![0u8; payload_len as usize];
                socket.read_exact(&mut payload).await?;
                
                if let Some(mask) = mask {
                    for (i, byte) in payload.iter_mut().enumerate() {
                        *byte ^= mask[i % 4];
                    }
                }
                
                let msg = String::from_utf8_lossy(&payload);
                info!("📩 WS: {}", msg);
                
                if opcode == 0x08 {
                    break;
                }
                
                let response_data = format!("ECHO: {}", msg);
                let response_bytes = response_data.as_bytes();
                
                let mut response_frame = Vec::new();
                response_frame.push(0x81);
                
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
            Err(_) => break,
        }
    }
    
    Ok(())
}
