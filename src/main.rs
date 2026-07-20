use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error};
use std::time::Duration;

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
    info!("📡 VPN Mode: Always respond 200 OK and keep connection alive");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buffer = [0u8; 4096];
            
            // Ler a requisição
            match socket.read(&mut buffer).await {
                Ok(n) if n > 0 => {
                    let request = String::from_utf8_lossy(&buffer[..n]);
                    let first_line = request.lines().next().unwrap_or("");
                    info!("📩 [{}] {}", peer_addr, first_line);
                    
                    // Verificar se é WebSocket
                    let is_websocket = request.to_lowercase().contains("upgrade: websocket") ||
                                       request.to_lowercase().contains("sec-websocket-key");
                    
                    if is_websocket {
                        // Resposta WebSocket 101
                        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                                        Upgrade: websocket\r\n\
                                        Connection: Upgrade\r\n\
                                        Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                                        \r\n";
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 101 Switching Protocols - Keeping connection alive", peer_addr);
                        
                        // MANTER CONEXÃO VIVA - ESSE É O SEGREDO!
                        loop {
                            tokio::time::sleep(Duration::from_secs(30)).await;
                            // Enviar keep-alive (ping)
                            let _ = socket.write_all(b"\r\n").await;
                            info!("💓 [{}] Keep-alive ping sent", peer_addr);
                        }
                    } else {
                        // Resposta 200 OK para qualquer outra requisição
                        let response = "HTTP/1.1 200 OK\r\n\
                                        Content-Type: text/plain\r\n\
                                        Content-Length: 2\r\n\
                                        Connection: keep-alive\r\n\
                                        Server: ZXProxy\r\n\
                                        \r\n\
                                        OK";
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 200 OK sent - Keeping connection alive", peer_addr);
                        
                        // MANTER CONEXÃO VIVA
                        loop {
                            tokio::time::sleep(Duration::from_secs(30)).await;
                            // Enviar keep-alive
                            let _ = socket.write_all(b"\r\n").await;
                            info!("💓 [{}] Keep-alive ping sent", peer_addr);
                        }
                    }
                }
                Ok(_) => info!("📦 [{}] Empty request", peer_addr),
                Err(e) => error!("❌ [{}] Read error: {}", peer_addr, e),
            }
        });
    }
    Ok(())
}
