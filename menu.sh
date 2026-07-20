#!/bin/bash
ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"
CONFIG_FILE="/opt/zxproxy/config.conf"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações padrão
DEFAULT_PORT="80"
DEFAULT_PROTOCOL="all"

show_header() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}           ZXProxy MENU                 ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

show_menu() {
    show_header
    
    # Mostrar portas ativas
    echo -e "${YELLOW}📡 PORTAS ATIVAS:${NC}"
    ACTIVE_PORTS=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                ACTIVE_PORTS="$ACTIVE_PORTS $PORT"
                echo -e "   ${GREEN}✅ Porta $PORT (ativa)${NC}"
            else
                rm -f "$pidfile"
            fi
        fi
    done
    if [ -z "$ACTIVE_PORTS" ]; then
        echo -e "   ${RED}❌ Nenhuma porta ativa${NC}"
    fi
    echo ""
    
    echo -e "${YELLOW}📋 OPÇÕES:${NC}"
    echo "  [01] • ABRIR PORTA"
    echo "  [02] • FECHAR PORTA"
    echo "  [03] • MULTIPROTOCOLO"
    echo "  [04] • MULTISTATUS"
    echo "  [05] • WEBSOCKET SECURITY"
    echo "  [06] • SOCKS5"
    echo "  [07] • TLS/SSL"
    echo "  [08] • STATUS DO PROXY"
    echo "  [09] • VER LOGS"
    echo "  [10] • SAIR"
    echo ""
    echo -n "INFORME UMA OPCAO: "
}

# Função para abrir porta com protocolo específico
open_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    
    # Matar processo na porta se existir
    sudo fuser -k $PORT/tcp 2>/dev/null
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    
    echo ""
    echo -e "${YELLOW}🔓 Abrindo porta ${PORT}...${NC}"
    
    # Iniciar com todos os protocolos
    if [ "$PORT" -lt 1024 ]; then
        nohup sudo ${ZXPROXY} -p ${PORT} -d > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    else
        nohup ${ZXPROXY} -p ${PORT} -d > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    fi
    
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 3
    
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Porta ${PORT} aberta com sucesso!${NC}"
        echo -e "📝 Log: /tmp/zxproxy_${PORT}.log"
        echo -e "📡 Protocolos: SOCKS5, TLS, WebSocket, HTTP, TCP"
    else
        echo -e "${RED}❌ Falha ao abrir porta ${PORT}!${NC}"
        rm -f "${PID_FILE}${PORT}.pid"
        echo "📝 Verifique o log:"
        tail -n 10 "/tmp/zxproxy_${PORT}.log" 2>/dev/null
    fi
    sleep 2
}

# Fechar porta
close_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        sudo kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo -e "${GREEN}✅ Porta ${PORT} fechada!${NC}"
    else
        echo -e "${RED}❌ Porta ${PORT} não está aberta!${NC}"
    fi
    sleep 2
}

# Multiprotocolo - Mostra todos os protocolos suportados
show_multiprotocol() {
    show_header
    echo -e "${YELLOW}📡 MULTIPROTOCOLO${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo -e "${GREEN}Protocolos Suportados:${NC}"
    echo ""
    echo "  🔐 SOCKS5      - Proxy SOCKS5 (byte 0x05)"
    echo "  🔒 TLS/SSL     - Conexões TLS seguras"
    echo "  🌐 WebSocket   - WebSocket com upgrade"
    echo "  🌍 HTTP        - HTTP/HTTPS requests"
    echo "  🔐 SECURITY    - Protocolo de segurança"
    echo "  📦 TCP         - Fallback TCP"
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo -e "${YELLOW}Portas Ativas com Multiprotocolo:${NC}"
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                echo -e "  ${GREEN}✅ Porta $PORT${NC}"
            fi
        fi
    done
    echo ""
    read -p "Pressione Enter para continuar..."
}

# Multistatus - Mostra status detalhado
show_multistatus() {
    show_header
    echo -e "${YELLOW}📊 MULTISTATUS - Status Detalhado${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            PID=$(cat "$pidfile")
            if ps -p $PID > /dev/null 2>&1; then
                echo -e "${GREEN}✅ Porta $PORT${NC}"
                echo -e "   PID: $PID"
                echo -e "   Status: ${GREEN}ATIVO${NC}"
                echo -e "   Log: /tmp/zxproxy_${PORT}.log"
                
                # Tentar pegar últimas conexões do log
                echo -e "   Últimas conexões:"
                tail -n 5 "/tmp/zxproxy_${PORT}.log" 2>/dev/null | grep -E "(SOCKS5|TLS|WebSocket|HTTP)" | tail -3 || echo "      Nenhuma conexão recente"
                echo ""
            fi
        fi
    done
    
    if [ -z "$(ls ${PID_FILE}*.pid 2>/dev/null)" ]; then
        echo -e "${RED}❌ Nenhuma porta ativa${NC}"
    fi
    
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    read -p "Pressione Enter para continuar..."
}

# WebSocket Security
show_websocket_security() {
    show_header
    echo -e "${YELLOW}🔐 WEBSOCKET SECURITY${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo -e "${GREEN}Configurações de WebSocket Security:${NC}"
    echo ""
    echo "  • WebSocket com TLS/SSL"
    echo "  • Handshake completo"
    echo "  • Keep-Alive ativo"
    echo "  • Suporte a wss://"
    echo ""
    
    # Verificar portas com WebSocket
    echo -e "${YELLOW}Portas com WebSocket ativo:${NC}"
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                echo -e "  ${GREEN}✅ Porta $PORT${NC}"
            fi
        fi
    done
    echo ""
    read -p "Pressione Enter para continuar..."
}

# SOCKS5
show_socks5() {
    show_header
    echo -e "${YELLOW}🔐 SOCKS5 PROXY${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo -e "${GREEN}Configurações SOCKS5:${NC}"
    echo ""
    echo "  • Porta padrão: 1080"
    echo "  • Sem autenticação"
    echo "  • Suporte a IPv4 e Domínios"
    echo "  • Compatível com qualquer app"
    echo ""
    
    read -p "Deseja abrir uma porta SOCKS5? (s/n): " RESP
    if [[ "$RESP" == "s" || "$RESP" == "S" ]]; then
        read -p "Digite a porta (ex: 1080): " PORT
        if [[ -n "$PORT" ]]; then
            open_port_specific "$PORT" "socks5"
        fi
    fi
}

# Função para abrir porta com protocolo específico
open_port_specific() {
    PORT=$1
    PROTO=$2
    
    sudo fuser -k $PORT/tcp 2>/dev/null
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    
    echo -e "${YELLOW}🔓 Abrindo porta ${PORT} com ${PROTO}...${NC}"
    
    if [ "$PORT" -lt 1024 ]; then
        nohup sudo ${ZXPROXY} -p ${PORT} -d > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    else
        nohup ${ZXPROXY} -p ${PORT} -d > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    fi
    
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 3
    
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Porta ${PORT} aberta!${NC}"
        echo -e "📡 Protocolo: ${PROTO}"
    else
        echo -e "${RED}❌ Falha!${NC}"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    sleep 2
}

# Ver logs
show_logs() {
    show_header
    echo -e "${YELLOW}📝 LOGS DO ZXProxy${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    
    # Listar logs disponíveis
    echo -e "${GREEN}Logs disponíveis:${NC}"
    ls -la /tmp/zxproxy_*.log 2>/dev/null || echo "  Nenhum log encontrado"
    echo ""
    
    read -p "Digite a porta para ver o log (ou Enter para sair): " PORT
    if [ -n "$PORT" ] && [ -f "/tmp/zxproxy_${PORT}.log" ]; then
        echo ""
        echo -e "${YELLOW}=== Últimas 50 linhas do log da porta ${PORT} ===${NC}"
        echo ""
        tail -n 50 "/tmp/zxproxy_${PORT}.log"
        echo ""
        read -p "Pressione Enter para continuar..."
    fi
}

# Loop principal
while true; do
    show_menu
    read OPTION
    case $OPTION in
        01|1) open_port ;;
        02|2) close_port ;;
        03|3) show_multiprotocol ;;
        04|4) show_multistatus ;;
        05|5) show_websocket_security ;;
        06|6) show_socks5 ;;
        07|7) 
            echo "🔒 TLS/SSL ativo em todas as portas"
            sleep 2
            ;;
        08|8) 
            show_multistatus
            ;;
        09|9) show_logs ;;
        10|0) 
            echo -e "${GREEN}👋 Saindo...${NC}"
            exit 0 
            ;;
        *) 
            echo -e "${RED}❌ Opção inválida!${NC}"
            sleep 2 
            ;;
    esac
done
