use tokio::io::{AsyncReadExt, AsyncWriteExt};
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
                
                // Processar todas as requisições no buffer
                loop {
                    let result = process_request(&mut buffer);
                    if let Some((response, is_websocket, consumed)) = result {
                        request_count += 1;
                        
                        if is_websocket {
                            info!("🌐 WebSocket upgrade detected!");
                            
                            if let Err(e) = socket.write_all(response.as_bytes()).await {
                                info!("❌ Error writing response: {}", e);
                                break;
                            }
                            socket.flush().await?;
                            
                            info!("🔗 Encaminhando para SSH na porta 22...");
                            let target = "127.0.0.1:22";
                            
                            match TcpStream::connect(target).await {
                                Ok(remote) => {
                                    info!("✅ Conectado ao SSH");
                                    let (mut client_reader, mut client_writer) = socket.into_split();
                                    let (mut remote_reader, mut remote_writer) = remote.into_split();
                                    
                                    let _ = tokio::try_join!(
                                        tokio::io::copy(&mut client_reader, &mut remote_writer),
                                        tokio::io::copy(&mut remote_reader, &mut client_writer)
                                    );
                                }
                                Err(e) => {
                                    info!("❌ Falha ao conectar ao SSH: {}", e);
                                }
                            }
                            break;
                        } else {
                            if let Err(e) = socket.write_all(response.as_bytes()).await {
                                info!("❌ Error writing response: {}", e);
                                break;
                            }
                            socket.flush().await?;
                            info!("📤 Sent response #{}", request_count);
                            
                            // Remove os dados processados do buffer
                            if consumed > 0 {
                                buffer.drain(..consumed);
                            }
                        }
                    } else {
                        break;
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

/// Processa uma requisição do buffer
fn process_request(buffer: &mut Vec<u8>) -> Option<(String, bool, usize)> {
    // Converte o buffer para String
    let data = match std::str::from_utf8(buffer) {
        Ok(s) => s,
        Err(_) => return None,
    };
    
    // Procura pelo fim dos headers
    let header_end = match data.find("\r\n\r\n") {
        Some(pos) => pos,
        None => return None,
    };
    
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
    
    // Verifica se é WebSocket
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
    
    // Respostas
    if is_websocket {
        let response = format!(
            "HTTP/1.1 101 Switching Protocols\r\n\
             Upgrade: websocket\r\n\
             Connection: Upgrade\r\n\
             Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
             \r\n"
        );
        return Some((response, true, total_len));
    }
    
    if is_connect {
        let response = format!(
            "HTTP/1.1 200 Connection established\r\n\
             Connection: keep-alive\r\n\
             \r\n"
        );
        return Some((response, false, total_len));
    }
    
    if method == "HEAD" {
        let response = format!(
            "HTTP/1.1 200 OK\r\n\
             Server: BSProxy\r\n\
             Content-Length: 0\r\n\
             Connection: keep-alive\r\n\
             \r\n"
        );
        return Some((response, false, total_len));
    }
    
    if method == "OPTIONS" {
        let response = format!(
            "HTTP/1.1 204 No Content\r\n\
             Server: BSProxy\r\n\
             Allow: GET, POST, PUT, DELETE, PATCH, HEAD, CONNECT, OPTIONS, TRACE\r\n\
             Connection: keep-alive\r\n\
             \r\n"
        );
        return Some((response, false, total_len));
    }
    
    // Resposta padrão
    let body = format!("OK: {} {}\n", method, path);
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
    
    Some((response, false, total_len))
}
