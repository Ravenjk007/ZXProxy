use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;
use std::collections::HashMap;

/// Processa múltiplas requisições HTTP na mesma conexão
async fn process_http_requests(mut socket: TcpStream) -> Result<()> {
    info!("📦 Processando múltiplas requisições HTTP...");
    
    let mut buffer = Vec::new();
    let mut tmp = [0u8; 4096];
    let mut response_count = 0;
    
    loop {
        match socket.read(&mut tmp).await {
            Ok(0) => {
                info!("🔚 Conexão fechada pelo cliente");
                break;
            }
            Ok(n) => {
                buffer.extend_from_slice(&tmp[..n]);
                
                // Processar todas as requisições no buffer
                while let Some((request, consumed)) = parse_http_request(&buffer) {
                    buffer.drain(..consumed);
                    response_count += 1;
                    
                    info!("📩 Requisição #{}: {}", response_count, request.method);
                    
                    // Gerar resposta apropriada para cada método
                    let response = match request.method.as_str() {
                        "GET" => generate_get_response(&request),
                        "POST" => generate_post_response(&request),
                        "PUT" => generate_put_response(&request),
                        "DELETE" => generate_delete_response(&request),
                        "PATCH" => generate_patch_response(&request),
                        "HEAD" => generate_head_response(&request),
                        "CONNECT" => generate_connect_response(&request),
                        "OPTIONS" => generate_options_response(&request),
                        "TRACE" => generate_trace_response(&request),
                        _ => generate_default_response(&request),
                    };
                    
                    socket.write_all(response.as_bytes()).await?;
                    info!("✅ Resposta #{} enviada", response_count);
                }
            }
            Err(e) => {
                info!("❌ Erro na leitura: {}", e);
                break;
            }
        }
    }
    
    info!("📊 Total de requisições processadas: {}", response_count);
    Ok(())
}

/// Estrutura para representar uma requisição HTTP
struct HttpRequest {
    method: String,
    path: String,
    version: String,
    headers: HashMap<String, String>,
    body: String,
}

/// Analisa uma requisição HTTP do buffer
fn parse_http_request(buffer: &[u8]) -> Option<(HttpRequest, usize)> {
    let data = String::from_utf8_lossy(buffer);
    
    // Procura pelo fim dos headers (\r\n\r\n)
    if let Some(header_end) = data.find("\r\n\r\n") {
        let header_part = &data[..header_end];
        let body_part = &data[header_end + 4..];
        
        let lines: Vec<&str> = header_part.lines().collect();
        if lines.is_empty() {
            return None;
        }
        
        // Parse da primeira linha (method path version)
        let first_line: Vec<&str> = lines[0].split_whitespace().collect();
        if first_line.len() < 3 {
            return None;
        }
        
        let method = first_line[0].to_string();
        let path = first_line[1].to_string();
        let version = first_line[2].to_string();
        
        // Parse dos headers
        let mut headers = HashMap::new();
        for line in &lines[1..] {
            if let Some(colon_pos) = line.find(':') {
                let key = line[..colon_pos].trim().to_string();
                let value = line[colon_pos + 1..].trim().to_string();
                headers.insert(key, value);
            }
        }
        
        // Corpo (se houver)
        let body = body_part.to_string();
        
        // Calcular o total consumido
        let consumed = header_end + 4 + body.len();
        
        // Verificar se a requisição está completa
        if !is_request_complete(&method, &headers, &body) {
            return None;
        }
        
        Some((HttpRequest {
            method,
            path,
            version,
            headers,
            body,
        }, consumed))
    } else {
        None
    }
}

/// Verifica se a requisição está completa
fn is_request_complete(method: &str, headers: &HashMap<String, String>, body: &str) -> bool {
    // GET, HEAD, DELETE geralmente não têm corpo
    if method == "GET" || method == "HEAD" || method == "DELETE" {
        return true;
    }
    
    // POST, PUT, PATCH têm corpo
    if method == "POST" || method == "PUT" || method == "PATCH" {
        if let Some(content_length) = headers.get("Content-Length") {
            if let Ok(len) = content_length.parse::<usize>() {
                return body.len() >= len;
            }
        }
        // Se não tem Content-Length, assume que é completo
        return true;
    }
    
    true
}

// ============================================
// Geradores de respostas para cada método
// ============================================

fn generate_get_response(request: &HttpRequest) -> String {
    format!(
        "HTTP/1.1 200 OK\r\n\
         Server: BSProxy\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 20\r\n\
         Connection: keep-alive\r\n\
         \r\n\
         GET OK! Path: {}\r\n",
        request.path
    )
}

fn generate_post_response(request: &HttpRequest) -> String {
    format!(
        "HTTP/1.1 201 Created\r\n\
         Server: BSProxy\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 22\r\n\
         Connection: keep-alive\r\n\
         \r\n\
         POST OK! Body: {}\r\n",
        request.body
    )
}

fn generate_put_response(request: &HttpRequest) -> String {
    format!(
        "HTTP/1.1 200 OK\r\n\
         Server: BSProxy\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 20\r\n\
         Connection: keep-alive\r\n\
         \r\n\
         PUT OK! Path: {}\r\n",
        request.path
    )
}

fn generate_delete_response(request: &HttpRequest) -> String {
    format!(
        "HTTP/1.1 200 OK\r\n\
         Server: BSProxy\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 23\r\n\
         Connection: keep-alive\r\n\
         \r\n\
         DELETE OK! Path: {}\r\n",
        request.path
    )
}

fn generate_patch_response(request: &HttpRequest) -> String {
    format!(
        "HTTP/1.1 200 OK\r\n\
         Server: BSProxy\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 22\r\n\
         Connection: keep-alive\r\n\
         \r\n\
         PATCH OK! Body: {}\r\n",
        request.body
    )
}

fn generate_head_response(_request: &HttpRequest) -> String {
    "HTTP/1.1 200 OK\r\n\
     Server: BSProxy\r\n\
     Content-Length: 0\r\n\
     Connection: keep-alive\r\n\
     \r\n".to_string()
}

fn generate_connect_response(_request: &HttpRequest) -> String {
    "HTTP/1.1 200 Connection established\r\n\
     Server: BSProxy\r\n\
     Connection: keep-alive\r\n\
     \r\n".to_string()
}

fn generate_options_response(_request: &HttpRequest) -> String {
    "HTTP/1.1 204 No Content\r\n\
     Server: BSProxy\r\n\
     Allow: GET, POST, PUT, DELETE, PATCH, HEAD, CONNECT, OPTIONS, TRACE\r\n\
     Connection: keep-alive\r\n\
     \r\n".to_string()
}

fn generate_trace_response(request: &HttpRequest) -> String {
    format!(
        "HTTP/1.1 200 OK\r\n\
         Server: BSProxy\r\n\
         Content-Type: message/http\r\n\
         Content-Length: {}\r\n\
         Connection: keep-alive\r\n\
         \r\n\
         {} {} {}\r\n",
        request.method.len() + request.path.len() + request.version.len() + 4,
        request.method,
        request.path,
        request.version
    )
}

fn generate_default_response(request: &HttpRequest) -> String {
    format!(
        "HTTP/1.1 200 OK\r\n\
         Server: BSProxy\r\n\
         Content-Type: text/plain\r\n\
         Content-Length: 30\r\n\
         Connection: keep-alive\r\n\
         \r\n\
         OK! Method: {} Path: {}\r\n",
        request.method, request.path
    )
}

/// Handler principal para WebSocket/HTTP
pub async fn handle_websocket(socket: TcpStream) -> Result<()> {
    info!("🌐 Conexão WebSocket/HTTP estabelecida");
    
    // Processar múltiplas requisições na mesma conexão
    process_http_requests(socket).await?;
    
    Ok(())
}
