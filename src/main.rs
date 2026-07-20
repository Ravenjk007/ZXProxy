use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use clap::Parser;
use anyhow::Result;
use log::{info, error};

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
    info!("📡 VPN Mode: Always respond 200 OK");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            // Ler os dados do cliente
            let mut buffer = [0u8; 4096];
            match socket.read(&mut buffer).await {
                Ok(n) if n > 0 => {
                    let request = String::from_utf8_lossy(&buffer[..n]);
                    info!("📩 [{}] Request: {}", peer_addr, request.lines().next().unwrap_or(""));
                    
                    // VERIFICAR SE É WEBSOCKET
                    if request.to_lowercase().contains("upgrade: websocket") {
                        info!("🌐 [{}] WebSocket Upgrade -> 101", peer_addr);
                        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                                        Upgrade: websocket\r\n\
                                        Connection: Upgrade\r\n\
                                        Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                                        \r\n";
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 101 Switching Protocols", peer_addr);
                        
                        // Manter conexão viva
                        tokio::time::sleep(tokio::time::Duration::from_secs(300)).await;
                        return;
                    }
                    
                    // SEMPRE RESPONDER 200 OK PARA QUALQUER REQUEST
                    info!("✅ [{}] Sending 200 OK", peer_addr);
                    let response = "HTTP/1.1 200 OK\r\n\
                                    Content-Type: text/plain\r\n\
                                    Content-Length: 12\r\n\
                                    Connection: keep-alive\r\n\
                                    Server: ZXProxy\r\n\
                                    \r\n\
                                    OK";
                    let _ = socket.write_all(response.as_bytes()).await;
                    info!("✅ [{}] 200 OK sent", peer_addr);
                }
                Ok(_) => info!("📦 [{}] Empty request", peer_addr),
                Err(e) => error!("❌ [{}] Read error: {}", peer_addr, e),
            }
        });
    }
    Ok(())
}
