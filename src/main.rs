mod socks5;
mod tls;
mod tcp_fallback;

use tokio::net::TcpListener;
use tokio::io::AsyncReadExt;
use clap::Parser;
use anyhow::Result;
use log::{info, error};

#[derive(Parser)]
#[command(name = "bsproxy")]
#[command(about = "Multiprotocol proxy server (SOCKS5 + TLS + TCP)", long_about = None)]
struct Cli {
    /// Porta para escutar
    #[arg(short = 'p', long = "port", default_value = "8080")]
    port: u16,
    
    /// Modo debug
    #[arg(short = 'd', long = "debug")]
    debug: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    if cli.debug {
        env_logger::init();
    } else {
        env_logger::builder()
            .filter_level(log::LevelFilter::Info)
            .init();
    }
    
    let addr = format!("0.0.0.0:{}", cli.port);
    let listener = TcpListener::bind(&addr).await?;
    info!("🚀 BSProxy Multiprotocol listening on {}", addr);
    info!("📡 Protocols: SOCKS5, TLS/SECURITY, TCP Fallback");
    info!("💡 Use 'bsproxy -p 80' para abrir porta 80");

    while let Ok((mut socket, _)) = listener.accept().await {
        tokio::spawn(async move {
            let mut buf = [0u8; 1];
            match socket.peek(&mut buf).await {
                Ok(_) => {
                    match buf[0] {
                        0x05 => {
                            info!("🔐 SOCKS5 connection");
                            if let Err(e) = socks5::handle(socket).await {
                                error!("SOCKS5 error: {}", e);
                            }
                        }
                        0x16 => {
                            info!("🔒 TLS/SECURITY connection");
                            if let Err(e) = tls::handle(socket).await {
                                error!("TLS error: {}", e);
                            }
                        }
                        _ => {
                            info!("📦 TCP Fallback connection");
                            if let Err(e) = tcp_fallback::handle(socket).await {
                                error!("TCP error: {}", e);
                            }
                        }
                    }
                }
                Err(e) => {
                    error!("Failed to peek connection: {}", e);
                }
            }
        });
    }

    Ok(())
}
