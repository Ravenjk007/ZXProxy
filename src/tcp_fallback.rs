use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;
use tokio::io;

pub async fn handle_tcp(mut socket: TcpStream) -> Result<()> {
    info!("📦 TCP Fallback");
    socket.write_all(b"TCP OK\n").await?;
    
    // Exemplo de como usar copy_bidirectional corretamente
    let mut buffer = [0u8; 1024];
    let n = socket.read(&mut buffer).await?;
    if n > 0 {
        info!("📦 Received: {}", String::from_utf8_lossy(&buffer[..n]));
        socket.write_all(&buffer[..n]).await?;
    }
    
    Ok(())
}
