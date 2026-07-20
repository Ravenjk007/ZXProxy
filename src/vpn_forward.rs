use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_vpn(mut socket: TcpStream) -> Result<()> {
    info!("🔐 VPN connection");
    
    let mut buffer = [0u8; 256];
    let n = socket.peek(&mut buffer).await?;
    
    // Detect VPN type
    let vpn_type = detect_vpn_type(&buffer[..n]);
    info!("📩 VPN type: {}", vpn_type);
    
    match vpn_type {
        "OPENVPN" => handle_openvpn(socket).await?,
        "WIREGUARD" => handle_wireguard(socket).await?,
        "IPSEC" => handle_ipsec(socket).await?,
        "L2TP" => handle_l2tp(socket).await?,
        _ => handle_generic_vpn(socket).await?,
    }
    
    Ok(())
}

fn detect_vpn_type(data: &[u8]) -> &'static str {
    if data.len() >= 4 {
        // OpenVPN
        if data.starts_with(b"\x00\x00\x00\x00") {
            return "OPENVPN";
        }
        if data.starts_with(b"OpenVPN") {
            return "OPENVPN";
        }
        // WireGuard
        if data.starts_with(b"WireGuard") {
            return "WIREGUARD";
        }
        // IPSec
        if data.starts_with(b"IPSec") || data.starts_with(b"ISAKMP") {
            return "IPSEC";
        }
        // L2TP
        if data.starts_with(b"L2TP") || data.starts_with(b"\x80\x00\x00\x00") {
            return "L2TP";
        }
    }
    "GENERIC"
}

async fn handle_openvpn(mut socket: TcpStream) -> Result<()> {
    info!("🔐 OpenVPN connection");
    socket.write_all(b"OpenVPN OK\n").await?;
    Ok(())
}

async fn handle_wireguard(mut socket: TcpStream) -> Result<()> {
    info!("🔐 WireGuard connection");
    socket.write_all(b"WireGuard OK\n").await?;
    Ok(())
}

async fn handle_ipsec(mut socket: TcpStream) -> Result<()> {
    info!("🔐 IPSec connection");
    socket.write_all(b"IPSec OK\n").await?;
    Ok(())
}

async fn handle_l2tp(mut socket: TcpStream) -> Result<()> {
    info!("🔐 L2TP connection");
    socket.write_all(b"L2TP OK\n").await?;
    Ok(())
}

async fn handle_generic_vpn(mut socket: TcpStream) -> Result<()> {
    info!("🔐 Generic VPN connection");
    socket.write_all(b"VPN OK\n").await?;
    Ok(())
}
