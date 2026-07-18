use tokio::io::{AsyncReadExt, AsyncWriteExt, copy_bidirectional};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

/// Processa requisições HTTP/WebSocket na mesma conexão
pub async fn handle(mut socket: TcpStream) -> Result<()> {
    info!("🌐 HTTP/WebSocket connection established");
    
    let mut buffer = Vec::new();
    let mut tmp = [0u8; 8192];
    let mut request_count = 0;
    
    loop {
        match socket.read(&mut tmp).await {
            Ok(0) => {
                info!("🔚 Connection closed by client");
                break;
            }
            Ok(n) => {
                buffer.extend_from_slice(&tmp[..n]);
                info!("📥 Received {} bytes", n);
                
                while let Some((response, is_websocket)) = process_request(&mut buffer) {
                    request_count += 1;
                    
                    if is_websocket {
                        info!("🌐 WebSocket upgrade detected!");
                        
                        // Enviar resposta de upgrade (101 Switching Protocols)
                        if let Err(e) = socket.write_all(response.as_bytes()).await {
                            info!("❌ Error writing response: {}", e);
                            break;
                        }
                        socket.flush().await?;
                        
                        // Encaminhar para SSH (tunnel)
                        info!("🔗 Encaminhando para SSH na porta 22...");
                        let target = "127.0.0.1:22";
                        
                        match TcpStream::connect(target).await {
                            Ok(remote) => {
                                info!("✅ Conectado ao SSH");
                                let (mut client_reader, mut client_writer) = socket.into_split();
                                let (mut remote_reader, mut remote_writer) = remote.into_split();
                                
                                let _ = tokio::try_join!(
                                    copy_bidirectional(&mut client_reader, &mut remote_writer),
                                    copy_bidirectional(&mut remote_reader, &mut client_writer)
                                );
                            }
                            Err(e) => {
                                info!("❌ Falha ao conectar ao SSH: {}", e);
                            }
                        }
                        break;
                    } else {
                        // Resposta HTTP normal
                        if let Err(e) = socket.write_all(response.as_bytes()).await {
                            info!("❌ Error writing response: {}", e);
                            break;
                        }
                        socket.flush().await?;
                        info!("📤 Sent response #{}", request_count);
                    }
                }
            }
            Err(e) => {
                info!("❌ Read error: {}", e);
                break;
            }
        }
    }
    
    info!("📊 Total requests processed: {}", request_count);
    Ok(())
}

fn process_request(buffer: &mut Vec<u8>) -> Option<(String, bool)> {
    let data = String::from_utf8_lossy(buffer);
    
    // Procura pelo fim dos headers
    if let Some(header_end) = data.find("\r\n\r\n") {
        let header_part = &data[..header_end];
        
        let lines: Vec<&str> = header_part.lines().collect();
        if lines.is_empty() {
            return None;
        }
        
        let first_line: Vec<&str> = lines[0].split_whitespace().collect();
        if first_line.len() < 2 {
            return None;
        }
        
        let method = first_line[0];
        let path = first_line[1];
        
        // Verifica se é WebSocket (Upgrade)
        let is_websocket = header_part.contains("Upgrade: websocket") || 
                          header_part.contains("upgrade: websocket");
        
        // Verifica se é CONNECT
        let is_connect = method == "CONNECT";
        
        // Calcula Content-Length
        let mut content_length = 0;
        for line in &lines[1..] {
            if line.to_lowercase().contains("content-length:") {
                if let Some(len) = line.split(':').nth(1) {
                    if let Ok(l) = len.trim().parse::<usize>() {
                        content_length = l;
                        break;
                    }
                }
            }
        }
        
        let total_len = header_end + 4 + content_length;
        
        if buffer.len() < total_len {
            return None;
        }
        
        buffer.drain(..total_len);
        
        if is_websocket {
            // Resposta WebSocket (101 Switching Protocols)
            let response = format!(
                "HTTP/1.1 101 Switching Protocols\r\n\
                 Upgrade: websocket\r\n\
                 Connection: Upgrade\r\n\
                 Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                 \r\n"
            );
            Some((response, true))
        } else if is_connect {
            let response = format!(
                "HTTP/1.1 200 Connection established\r\n\
                 Connection: keep-alive\r\n\
                 \r\n"
            );
            Some((response, false))
        } else if method == "HEAD" {
            let response = format!(
                "HTTP/1.1 200 OK\r\n\
                 Server: BSProxy\r\n\
                 Content-Length: 0\r\n\
                 Connection: keep-alive\r\n\
                 \r\n"
            );
            Some((response, false))
        } else if method == "OPTIONS" {
            let response = format!(
                "HTTP/1.1 204 No Content\r\n\
                 Server: BSProxy\r\n\
                 Allow: GET, POST, PUT, DELETE, PATCH, HEAD, CONNECT, OPTIONS, TRACE\r\n\
                 Connection: keep-alive\r\n\
                 \r\n"
            );
            Some((response, false))
        } else {
            // Resposta padrão
            let body = format!(
                "OK: {} {}\n",
                method, path
            );
            let response = format!(
                "HTTP/1.1 200 OK\r\n\
                 Server: BSProxy\r\n\
                 Content-Type: text/plain\r\n\
                 Content-Length: {}\r\n\
                 Connection: keep-alive\r\n\
                 \r\n\
                 {}",
                body.len(),
                body
            );
            Some((response, false))
        }
    } else {
        None
    }
}
