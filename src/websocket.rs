use tokio::io::{copy_bidirectional, AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

/// Lê e descarta os headers HTTP até encontrar \r\n\r\n
async fn consume_http_headers(socket: &mut TcpStream) -> std::io::Result<()> {
    let mut buf: Vec<u8> = Vec::new();
    let mut tmp = [0u8; 1];

    loop {
        socket.read_exact(&mut tmp).await?;
        buf.push(tmp[0]);

        if buf.len() >= 4 && &buf[buf.len() - 4..] == b"\r\n\r\n" {
            break;
        }
        if buf.len() > 8192 {
            break;
        }
    }
    Ok(())
}

/// Modo WebSocket: consome handshake HTTP, responde com upgrade e encaminha para SSH
pub async fn handle_websocket(mut socket: TcpStream) -> Result<()> {
    info!("🌐 WebSocket handshake...");
    
    // Consumir headers HTTP
    consume_http_headers(&mut socket).await?;
    
    // Resposta de upgrade (status 101)
    let response = "HTTP/1.1 101 Switching Protocols\r\n\
                    Upgrade: websocket\r\n\
                    Connection: Upgrade\r\n\
                    Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                    \r\n";
    
    socket.write_all(response.as_bytes()).await?;
    info!("🌐 WebSocket handshake complete! Encaminhando para SSH...");
    
    // --- ENCAMINHAR PARA SSH (DESTINO FINAL) ---
    // Altere para o IP/porta do seu SSH
    let target = "127.0.0.1:22";  // SSH local
    
    match TcpStream::connect(target).await {
        Ok(remote) => {
            info!("✅ Conectado ao SSH, encaminhando tráfego...");
            let (mut client_reader, mut client_writer) = socket.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
            
            info!("🔚 Conexão WebSocket->SSH encerrada");
            Ok(())
        }
        Err(e) => {
            info!("❌ Falha ao conectar ao SSH: {}", e);
            anyhow::bail!("SSH connection failed: {}", e)
        }
    }
}

/// Modo Direct/Security: igual ao seu wsproxy com status 200
pub async fn handle_direct(mut socket: TcpStream) -> Result<()> {
    info!("🔒 Direct/Security mode");
    
    let response = "HTTP/1.1 200 OK\r\n\r\n";
    socket.write_all(response.as_bytes()).await?;
    
    let target = "127.0.0.1:22";
    let mut remote = TcpStream::connect(target).await?;
    copy_bidirectional(&mut socket, &mut remote).await?;
    
    Ok(())
}
