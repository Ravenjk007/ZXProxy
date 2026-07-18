cat > src/tcp_fallback.rs << 'EOF'
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::Result;
use log::info;

pub async fn handle(mut socket: TcpStream) -> Result<()> {
    info!("📦 TCP Fallback: echo server");
    
    let mut buf = [0u8; 1024];
    loop {
        match socket.read(&mut buf).await {
            Ok(0) => break,
            Ok(n) => {
                let msg = String::from_utf8_lossy(&buf[..n]);
                info!("📩 Echo: {}", msg.trim());
                let response = format!("TCP: {}", msg);
                socket.write_all(response.as_bytes()).await?;
            }
            Err(e) => {
                anyhow::bail!("TCP read error: {}", e);
            }
        }
    }
    
    Ok(())
}
EOF
