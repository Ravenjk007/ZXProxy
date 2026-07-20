use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error};
use std::time::Duration;
use sha1::{Sha1, Digest};
use base64::Engine;

#[derive(Parser)]
#[command(name = "zxproxy")]
#[command(about = "ZXProxy - VPN/HTTP Inject Optimized")]
struct Cli {
    #[arg(short = 'p', long = "port", default_value = "8080")]
    port: u16,
    #[arg(short = 'd', long = "debug")]
    debug: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    env_logger::builder()
        .filter_level(if cli.debug { 
            log::LevelFilter::Debug 
        } else { 
            log::LevelFilter::Info 
        })
        .format_timestamp_millis()
        .init();
    
    let addr = format!("0.0.0.0:{}", cli.port);
    info!("🚀 ZXProxy listening on {}", addr);
    info!("📡 HTTP Injector Mode: Real WebSocket + Keep-Alive");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buffer = vec![0u8; 8192];
            
            match socket.read(&mut buffer).await {
                Ok(n) if n > 0 => {
                    let request = String::from_utf8_lossy(&buffer[..n]);
                    let first_line = request.lines().next().unwrap_or("");
                    info!("📩 [{}] {}", peer_addr, first_line);
                    
                    let is_websocket = request.to_lowercase().contains("upgrade: websocket") ||
                                       request.to_lowercase().contains("sec-websocket-key");
                    
                    if is_websocket {
                        info!("🌐 [{}] WebSocket request", peer_addr);
                        
                        // Extrair WebSocket Key corretamente
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
                        
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 101 Switching Protocols", peer_addr);
                        
                        // Manter WebSocket vivo com pings
                        let mut counter = 0;
                        let mut interval = tokio::time::interval(Duration::from_secs(10));
                        
                        loop {
                            interval.tick().await;
                            counter += 1;
                            
                            // WebSocket ping frame
                            let ping_frame = [0x89, 0x00];
                            
                            match socket.write_all(&ping_frame).await {
                                Ok(_) => info!("💓 [{}] WebSocket ping #{}", peer_addr, counter),
                                Err(_) => {
                                    info!("🔚 [{}] Connection closed", peer_addr);
                                    break;
                                }
                            }
                            
                            // Tentar ler pong
                            let mut pong_buf = [0u8; 2];
                            let _ = socket.read(&mut pong_buf).await;
                        }
                    } else {
                        // HTTP normal
                        let response = "HTTP/1.1 200 OK\r\n\
                                        Content-Type: text/plain\r\n\
                                        Content-Length: 2\r\n\
                                        Connection: keep-alive\r\n\
                                        Server: ZXProxy\r\n\
                                        \r\n\
                                        OK";
                        
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 200 OK sent", peer_addr);
                        
                        let mut counter = 0;
                        let mut interval = tokio::time::interval(Duration::from_secs(15));
                        
                        loop {
                            interval.tick().await;
                            counter += 1;
                            
                            match socket.write_all(b"\r\n\r\n").await {
                                Ok(_) => info!("💓 [{}] Keep-alive #{}", peer_addr, counter),
                                Err(_) => {
                                    info!("🔚 [{}] Connection closed", peer_addr);
                                    break;
                                }
                            }
                        }
                    }
                }
                Ok(_) => info!("📦 [{}] Empty", peer_addr),
                Err(e) => error!("❌ [{}] Error: {}", peer_addr, e),
            }
        });
    }
    Ok(())
}

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

fn generate_websocket_accept(key: &str) -> String {
    let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    let combined = format!("{}{}", key, guid);
    
    let mut hasher = Sha1::new();
    hasher.update(combined.as_bytes());
    let result = hasher.finalize();
    
    base64::engine::general_purpose::STANDARD.encode(result)
}
