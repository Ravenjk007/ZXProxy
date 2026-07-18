use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle(mut socket: TcpStream) -> Result<()> {
    info!("🌐 HTTP connection");
    
    let mut buf = [0u8; 4096];
    let n = socket.read(&mut buf).await?;
    let data = String::from_utf8_lossy(&buf[..n]);
    
    info!("📩 Request: {}", data.lines().next().unwrap_or(""));
    
    let response = "HTTP/1.1 200 OK\r\n\
                    Content-Type: text/plain\r\n\
                    Content-Length: 12\r\n\
                    Connection: keep-alive\r\n\
                    \r\n\
                    Hello World!";
    
    socket.write_all(response.as_bytes()).await?;
    Ok(())
}
