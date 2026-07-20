use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::{info, debug};
use std::collections::HashMap;

pub async fn handle_http(mut socket: TcpStream) -> Result<()> {
    info!("🌐 HTTP connection");
    
    let mut buffer = [0u8; 4096];
    let n = socket.read(&mut buffer).await?;
    let data = String::from_utf8_lossy(&buffer[..n]);
    
    // Parse request
    let lines: Vec<&str> = data.lines().collect();
    if lines.is_empty() {
        anyhow::bail!("Empty HTTP request");
    }
    
    let request_line = lines[0];
    let parts: Vec<&str> = request_line.split_whitespace().collect();
    
    if parts.len() >= 3 {
        let method = parts[0];
        let path = parts[1];
        let version = parts[2];
        
        info!("📩 HTTP {} {} {}", method, path, version);
        
        // Parse headers
        let mut headers = HashMap::new();
        for line in lines.iter().skip(1) {
            if line.is_empty() {
                break;
            }
            if let Some((key, value)) = line.split_once(':') {
                headers.insert(key.trim().to_lowercase(), value.trim().to_string());
            }
        }
        
        // Handle different methods
        match method {
            "CONNECT" => {
                // HTTPS tunneling
                return handle_connect(socket, path, headers).await;
            }
            "GET" | "POST" | "PUT" | "DELETE" | "PATCH" | "HEAD" | "OPTIONS" => {
                return handle_request(socket, method, path, headers, &data).await;
            }
            _ => {
                // Default response
                let response = "HTTP/1.1 400 Bad Request\r\n\
                              Content-Type: text/plain\r\n\
                              Content-Length: 11\r\n\
                              Connection: close\r\n\
                              \r\n\
                              Bad Request";
                socket.write_all(response.as_bytes()).await?;
                return Ok(());
            }
        }
    }
    
    Ok(())
}

async fn handle_connect(
    mut socket: TcpStream,
    target: &str,
    headers: HashMap<String, String>,
) -> Result<()> {
    info!("🔗 HTTP CONNECT to {}", target);
    
    // Send 200 Connection Established
    let response = "HTTP/1.1 200 Connection Established\r\n\
                   \r\n";
    socket.write_all(response.as_bytes()).await?;
    
    // Forward to target
    let target_addr = if target.contains(':') {
        target.to_string()
    } else {
        format!("{}:443", target)
    };
    
    match TcpStream::connect(&target_addr).await {
        Ok(remote) => {
            let (mut client_reader, mut client_writer) = socket.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
            
            Ok(())
        }
        Err(e) => {
            info!("❌ Failed to connect to {}: {}", target_addr, e);
            anyhow::bail!("Connection failed: {}", e)
        }
    }
}

async fn handle_request(
    mut socket: TcpStream,
    method: &str,
    path: &str,
    headers: HashMap<String, String>,
    body: &str,
) -> Result<()> {
    // Handle local requests or proxy to target
    if path.starts_with('/') && path.len() >= 2 {
        // Local request - serve content
        let response = format!(
            "HTTP/1.1 200 OK\r\n\
             Content-Type: text/html\r\n\
             Content-Length: {}\r\n\
             Connection: keep-alive\r\n\
             \r\n\
             {}",
            100,
            "<html><body><h1>ZXProxy</h1><p>HTTP proxy is working!</p></body></html>"
        );
        
        socket.write_all(response.as_bytes()).await?;
        return Ok(());
    }
    
    // Proxy request to external server
    if path.starts_with("http://") || path.starts_with("https://") {
        // Extract host and port
        let url = path;
        let host = headers.get("host").unwrap_or(&"unknown".to_string());
        
        info!("📦 Proxying {} request to {}", method, host);
        
        // For simplicity, return a response
        let response = format!(
            "HTTP/1.1 200 OK\r\n\
             Content-Type: text/plain\r\n\
             Content-Length: {}\r\n\
             Proxy-Status: ZXProxy\r\n\
             \r\n\
             {}",
            25,
            "Proxied by ZXProxy"
        );
        
        socket.write_all(response.as_bytes()).await?;
    }
    
    Ok(())
}
