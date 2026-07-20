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
    info!("📡 VPN Mode: Read all data, then 200 OK + Keep-Alive");

    let listener = TcpListener::bind(&addr).await?;
    
    while let Ok((mut socket, peer_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buffer = vec![0u8; 8192];
            
            // LER TODOS OS DADOS PRIMEIRO
            match socket.read(&mut buffer).await {
                Ok(n) if n > 0 => {
                    let request = String::from_utf8_lossy(&buffer[..n]);
                    let first_line = request.lines().next().unwrap_or("");
                    info!("📩 [{}] {}", peer_addr, first_line);
                    info!("📩 [{}] Full request:\n{}", peer_addr, request);
                    
                    // Verificar se é WebSocket
                    let is_websocket = request.to_lowercase().contains("upgrade: websocket") ||
                                       request.to_lowercase().contains("sec-websocket-key");
                    
                    // SÓ RESPONDER DEPOIS DE LER TUDO
                    if is_websocket {
                        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                                        Upgrade: websocket\r\n\
                                        Connection: Upgrade\r\n\
                                        Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                                        \r\n";
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 101 WebSocket", peer_addr);
                    } else {
                        // RESPOSTA 200 OK COM KEEP-ALIVE
                        let response = "HTTP/1.1 200 OK\r\n\
                                        Content-Type: text/plain\r\n\
                                        Content-Length: 2\r\n\
                                        Connection: keep-alive\r\n\
                                        Server: ZXProxy\r\n\
                                        \r\n\
                                        OK";
                        let _ = socket.write_all(response.as_bytes()).await;
                        info!("✅ [{}] 200 OK sent", peer_addr);
                    }
                    
                    // MANTER CONEXÃO VIVA COM KEEP-ALIVE
                    let mut interval = tokio::time::interval(Duration::from_secs(20));
                    loop {
                        interval.tick().await;
                        // Enviar keep-alive (apenas um espaço ou \r\n)
                        match socket.write_all(b"\r\n").await {
                            Ok(_) => info!("💓 [{}] Keep-alive", peer_addr),
                            Err(_) => {
                                info!("🔚 [{}] Connection closed by client", peer_addr);
                                break;
                            }
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
