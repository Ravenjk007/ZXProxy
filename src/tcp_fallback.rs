use tokio::net::TcpStream;
use anyhow::Result;
use log::{info, error};

pub async fn handle_tcp(mut socket: TcpStream, _vpn_enabled: bool) -> Result<()> {
    info!("📦 Handling TCP fallback connection...");
    
    // Para TCP fallback, tentamos fazer um proxy transparente
    // ou encaminhar para um destino padrão
    let dest = TcpStream::connect("8.8.8.8:53").await?; // DNS como exemplo
    
    info!("✅ TCP fallback connection established");
    
    tokio::io::copy_bidirectional(&mut socket, dest).await?;
    
    Ok(())
}
