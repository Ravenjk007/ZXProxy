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
    info!("📡 HTTP Injector Mode: 200 OK + Real Keep-Alive");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buffer = vec![0u8; 8192];
            
            match socket.read(&mut buffer).await {
                Ok(n) if n > 0 => {
                    let request = String::from_utf8_lossy(&buffer[..n]);
                    let first_line = request.lines().next().unwrap_or("");
                    info!("📩 [{}] {}", peer_addr, first_line);
                    
                    // Verificar se é WebSocket
                    let is_websocket = request.to_lowercase().contains("upgrade: websocket") ||
                                       request.to_lowercase().contains("sec-websocket-key");
                    
                    // Responder com 200 OK ou 101 Switching Protocols
                    let response = if is_websocket {
                        "HTTP/1.1 101 Switching Protocols\r\n\
                         Upgrade: websocket\r\n\
                         Connection: Upgrade\r\n\
                         Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                         \r\n"
                    } else {
                        "HTTP/1.1 200 OK\r\n\
                         Content-Type: text/plain\r\n\
                         Content-Length: 2\r\n\
                         Connection: keep-alive\r\n\
                         Server: ZXProxy\r\n\
                         \r\n\
                         OK"
                    };
                    
                    let _ = socket.write_all(response.as_bytes()).await;
                    info!("✅ [{}] Response sent", peer_addr);
                    
                    // KEEP-ALIVE COM DADOS REAIS
                    let mut counter = 0;
                    let mut interval = tokio::time::interval(Duration::from_secs(15));
                    
                    loop {
                        interval.tick().await;
                        counter += 1;
                        
                        // Enviar keep-alive com dados reais
                        let keep_alive = format!("\r\n\r\n");
                        
                        match socket.write_all(keep_alive.as_bytes()).await {
                            Ok(_) => info!("💓 [{}] Keep-alive #{}", peer_addr, counter),
                            Err(_) => {
                                info!("🔚 [{}] Connection closed", peer_addr);
                                break;
                            }
                        }
                        
                        // Pequeno delay para o app processar
                        tokio::time::sleep(Duration::from_millis(100)).await;
                    }
                }
                Ok(_) => info!("📦 [{}] Empty request", peer_addr),
                Err(e) => error!("❌ [{}] Read error: {}", peer_addr, e),
            }
        });
    }
    Ok(())
}
