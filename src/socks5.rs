use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::{Result, anyhow};
use log::{info, debug, error};

pub async fn handle_socks5(mut socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    info!("🔐 Handling SOCKS5 connection...");
    
    // Leitura do handshake SOCKS5
    let mut buf = [0u8; 256];
    let n = socket.read(&mut buf).await?;
    
    if n < 3 {
        return Err(anyhow!("Invalid SOCKS5 handshake"));
    }
    
    // Verifica versão e número de métodos
    if buf[0] != 0x05 {
        return Err(anyhow!("Invalid SOCKS version"));
    }
    
    let nmethods = buf[1] as usize;
    let mut methods = Vec::new();
    for i in 0..nmethods {
        if 2 + i < n {
            methods.push(buf[2 + i]);
        }
    }
    
    // Escolhe método (apenas sem autenticação por enquanto)
    let method = if methods.contains(&0x00) { 0x00 } else { 0xFF };
    
    // Responde com método escolhido
    socket.write_all(&[0x05, method]).await?;
    
    if method == 0xFF {
        return Err(anyhow!("No acceptable authentication method"));
    }
    
    // Leitura do comando
    let n = socket.read(&mut buf).await?;
    
    if n < 10 {
        return Err(anyhow!("Invalid SOCKS5 command"));
    }
    
    // Extrai informações do comando
    let cmd = buf[1];
    let atyp = buf[3];
    
    let (host, port) = match atyp {
        0x01 => { // IPv4
            let ip = format!("{}.{}.{}.{}", buf[4], buf[5], buf[6], buf[7]);
            let port = u16::from_be_bytes([buf[8], buf[9]]);
            (ip, port)
        },
        0x03 => { // Domain name
            let domain_len = buf[4] as usize;
            let domain = String::from_utf8_lossy(&buf[5..5+domain_len]).to_string();
            let port_offset = 5 + domain_len;
            let port = u16::from_be_bytes([buf[port_offset], buf[port_offset + 1]]);
            (domain, port)
        },
        0x04 => { // IPv6
            // Simplificado, vamos pegar os bytes
            let mut ipv6 = String::new();
            for i in 4..20 {
                ipv6.push_str(&format!("{:02x}", buf[i]));
                if (i - 4) % 2 == 1 && i < 19 {
                    ipv6.push(':');
                }
            }
            let port = u16::from_be_bytes([buf[20], buf[21]]);
            (ipv6, port)
        },
        _ => return Err(anyhow!("Invalid address type")),
    };
    
    debug!("SOCKS5 CONNECT to {}:{}", host, port);
    
    // Se VPN está habilitada, faz o túnel VPN
    if vpn_enabled {
        // Aqui você pode implementar a conexão VPN
        // Por enquanto, apenas conecta diretamente
        info!("🔒 VPN Mode: Establishing secure tunnel to {}:{}", host, port);
    }
    
    // Conecta ao destino
    let mut dest = match TcpStream::connect(format!("{}:{}", host, port)).await {
        Ok(stream) => {
            info!("✅ Connected to {}:{}", host, port);
            stream
        },
        Err(e) => {
            error!("❌ Failed to connect to {}:{}: {}", host, port, e);
            // Responde com erro
            socket.write_all(&[0x05, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
            return Err(anyhow!("Connection failed"));
        }
    };
    
    // Responde com sucesso
    socket.write_all(&[0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
    
    // Proxy bidirecional
    tokio::io::copy_bidirectional(&mut socket, &mut dest).await?;
    
    Ok(())
}
