use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;
use std::collections::HashMap;

/// Processa múltiplas requisições na mesma conexão
async fn process_requests(mut socket: TcpStream) -> Result<()> {
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
                
                while let Some((response, is_websocket, consumed)) = parse_request(&mut buffer) {
                    request_count += 1;
                    
                    if is_websocket {
                        info!("🌐 WebSocket upgrade detected!");
                        if let Err(e) = socket.write_all(response.as_bytes()).await {
                            info!("❌ Write error: {}", e);
                            break;
                        }
                        socket.flush().await?;
                        
                        // Encaminhar para SSH
                        info!("🔗 Encaminhando para SSH...");
                        match TcpStream::connect("127.0.0.1:22").await {
                            Ok(remote) => {
                                let (mut client_reader, mut client_writer) = socket.into_split();
                                let (mut remote_reader, mut remote_writer) = remote.into_split();
                                let _ = tokio::try_join!(
                                    tokio::io::copy(&mut client_reader, &mut remote_writer),
                                    tokio::io::copy(&mut remote_reader, &mut client_writer)
                                );
                            }
                            Err(e) => info!("❌ SSH error: {}", e),
                        }
                        return Ok(());
                    } else {
                        if let Err(e) = socket.write_all(response.as_bytes()).await {
                            info!("❌ Write error: {}", e);
                            break;
                        }
                        socket.flush().await?;
                        info!("📤 Sent response #{}", request_count);
                    }
                    
                    if consumed > 0 {
                        buffer.drain(..consumed);
                    }
                }
            }
            Err(e) => {
                info!("❌ Read error: {}", e);
                break;
            }
        }
    }
    
    info!("📊 Total requests: {}", request_count);
    Ok(())
}

/// Parseia uma requisição HTTP do buffer
fn parse_request(buffer: &mut Vec<u8>) -> Option<(String, bool, usize)> {
    let data = match std::str::from_utf8(buffer) {
        Ok(s) => s,
        Err(_) => return None,
    };
    
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
    
    // Detecta WebSocket
    let is_websocket = header_part.contains("Upgrade: websocket") || 
                      header_part.contains("upgrade: websocket");
    
    // Detecta CONNECT
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
    
    // Gera resposta apropriada
    let response = generate_response(method, path, is_websocket, is_connect);
    
    Some((response, is_websocket, total_len))
}

/// Gera resposta HTTP
fn generate_response(method: &str, path: &str, is_websocket: bool, is_connect: bool) -> String {
    if is_websocket {
        format!(
            "HTTP/1.1 101 Switching Protocols\r\n\
             Upgrade: websocket\r\n\
             Connection: Upgrade\r\n\
             Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
             \r\n"
        )
    } else if is_connect {
        format!(
            "HTTP/1.1 200 Connection established\r\n\
             Connection: keep-alive\r\n\
             \r\n"
        )
    } else if method == "HEAD" {
        format!(
            "HTTP/1.1 200 OK\r\n\
             Server: BSProxy\r\n\
             Content-Length: 0\r\n\
             Connection: keep-alive\r\n\
             \r\n"
        )
    } else if method == "OPTIONS" {
        format!(
            "HTTP/1.1 204 No Content\r\n\
             Server: BSProxy\r\n\
             Allow: GET, POST, PUT, DELETE, PATCH, HEAD, CONNECT, OPTIONS, TRACE\r\n\
             Connection: keep-alive\r\n\
             \r\n"
        )
    } else {
        let body = format!("OK: {} {}\n", method, path);
        format!(
            "HTTP/1.1 200 OK\r\n\
             Server: BSProxy\r\n\
             Content-Type: text/plain\r\n\
             Content-Length: {}\r\n\
             Connection: keep-alive\r\n\
             \r\n\
             {}",
            body.len(),
            body
        )
    }
}

/// Handler principal
pub async fn handle_websocket(socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket/HTTP connection established");
    process_requests(socket).await
}
