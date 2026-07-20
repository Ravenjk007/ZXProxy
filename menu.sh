#!/bin/bash
ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"
CONFIG_FILE="/opt/zxproxy/config.conf"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurações padrão
mkdir -p /opt/zxproxy
cat > /opt/zxproxy/config.conf << 'INNEREOF'
PORT=80
WEBSOCKET=active
SECURITY=active
SOCKS5=active
TLS=active
INNEREOF

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}
load_config

show_header() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ZXProxy - SMALI VPS           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""
}

show_menu_principal() {
    show_header
    echo -e "${YELLOW}📡 WEBSOCKET SECURITY${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    
    # Mostrar portas ativas
    ACTIVE_PORTS=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                ACTIVE_PORTS="$ACTIVE_PORTS $PORT"
            else
                rm -f "$pidfile"
            fi
        fi
    done
    if [ -n "$ACTIVE_PORTS" ]; then
        echo -e "${GREEN}PORTA(S): ${ACTIVE_PORTS}${NC}"
    else
        echo -e "${RED}PORTA(S): nenhuma${NC}"
    fi
    echo ""
    echo -e "${CYAN}[01] • ABRIR PORTA${NC}"
    echo -e "${CYAN}[02] • ALTERAR STATUS${NC}"
    echo -e "${CYAN}[03] • MULTIPROTOCOLO${NC}"
    echo -e "${CYAN}[04] • MULTISTATUS${NC}"
    echo -e "${CYAN}[05] • PARAR WEBSOCKET SECURITY${NC}"
    echo -e "${CYAN}[06] • RETORNAR AO MENU${NC}"
    echo ""
    echo -n -e "${YELLOW}INFORME UMA OPCAO: ${NC}"
}

abrir_porta() {
    show_header
    echo -e "${YELLOW}🔓 ABRIR PORTA${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo -e "${RED}❌ Porta inválida!${NC}"
        sleep 2
        return
    fi
    
    sudo fuser -k $PORT/tcp 2>/dev/null
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    
    echo -e "${YELLOW}🔓 Abrindo porta ${PORT}...${NC}"
    if [ ! -f "$ZXPROXY" ]; then
        echo -e "${RED}❌ ZXProxy não encontrado!${NC}"
        sleep 3
        return
    fi
    
    if [ "$PORT" -lt 1024 ]; then
        nohup sudo ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    else
        nohup ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    fi
    
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 3
    
    if ps -p $(cat "${PID_FILE}${PORT}.pid})" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Porta ${PORT} aberta com sucesso!${NC}"
        echo -e "📝 Log: /tmp/zxproxy_${PORT}.log"
    else
        echo -e "${RED}❌ Falha ao abrir porta ${PORT}!${NC}"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    sleep 3
}

alterar_status() {
    show_header
    echo -e "${YELLOW}🔄 ALTERAR STATUS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    
    if pgrep -f "/opt/zxproxy/proxy" > /dev/null; then
        echo -e "${GREEN}✅ Proxy está ATIVO${NC}"
        echo ""
        echo -e "${CYAN}[01] • PARAR PROXY${NC}"
        echo -e "${CYAN}[02] • REINICIAR PROXY${NC}"
        echo -e "${CYAN}[03] • VOLTAR${NC}"
        echo ""
        echo -n -e "${YELLOW}INFORME UMA OPCAO: ${NC}"
        read OPT
        case $OPT in
            01|1)
                echo -e "${YELLOW}🛑 Parando proxy...${NC}"
                sudo pkill -f "/opt/zxproxy/proxy" 2>/dev/null
                sudo rm -f /tmp/*proxy*.pid
                echo -e "${GREEN}✅ Proxy parado!${NC}"
                sleep 2
                ;;
            02|2)
                echo -e "${YELLOW}🔄 Reiniciando proxy...${NC}"
                sudo pkill -f "/opt/zxproxy/proxy" 2>/dev/null
                sudo rm -f /tmp/*proxy*.pid
                sleep 2
                read -p "Digite a porta para reiniciar: " PORT
                if [ -n "$PORT" ]; then
                    if [ "$PORT" -lt 1024 ]; then
                        nohup sudo ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
                    else
                        nohup ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
                    fi
                    echo $! > "${PID_FILE}${PORT}.pid"
                    echo -e "${GREEN}✅ Proxy reiniciado na porta $PORT!${NC}"
                fi
                sleep 2
                ;;
            03|3) return ;;
            *) echo -e "${RED}❌ Opção inválida!${NC}"; sleep 2 ;;
        esac
    else
        echo -e "${RED}❌ Proxy está INATIVO${NC}"
        echo ""
        echo -e "${CYAN}[01] • INICIAR PROXY${NC}"
        echo -e "${CYAN}[02] • VOLTAR${NC}"
        echo ""
        echo -n -e "${YELLOW}INFORME UMA OPCAO: ${NC}"
        read OPT
        case $OPT in
            01|1) abrir_porta ;;
            02|2) return ;;
            *) echo -e "${RED}❌ Opção inválida!${NC}"; sleep 2 ;;
        esac
    fi
}

show_multiprotocol() {
    while true; do
        show_header
        echo -e "${YELLOW}📡 MULTIPROTOCOLO${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════${NC}"
        echo ""
        echo -e "${GREEN}Status atual:${NC}"
        echo -e "  ${CYAN}WebSocket: ${WEBSOCKET:-active}${NC}"
        echo -e "  ${CYAN}SECURITY: ${SECURITY:-active}${NC}"
        echo -e "  ${CYAN}SOCKS5: ${SOCKS5:-active}${NC}"
        echo -e "  ${CYAN}TLS/SSL: ${TLS:-active}${NC}"
        echo ""
        echo -e "${CYAN}[01] • ATIVAR WEBSOCKET${NC}"
        echo -e "${CYAN}[02] • DESATIVAR WEBSOCKET${NC}"
        echo -e "${CYAN}[03] • ATIVAR SECURITY${NC}"
        echo -e "${CYAN}[04] • DESATIVAR SECURITY${NC}"
        echo -e "${CYAN}[05] • ATIVAR SOCKS5${NC}"
        echo -e "${CYAN}[06] • DESATIVAR SOCKS5${NC}"
        echo -e "${CYAN}[07] • ATIVAR TLS${NC}"
        echo -e "${CYAN}[08] • DESATIVAR TLS${NC}"
        echo -e "${CYAN}[09] • VOLTAR${NC}"
        echo ""
        echo -n -e "${YELLOW}INFORME UMA OPCAO: ${NC}"
        read OPT
        
        save_config() {
            cat > "$CONFIG_FILE" << EOF
PORT=$PORT
WEBSOCKET=$WEBSOCKET
SECURITY=$SECURITY
SOCKS5=$SOCKS5
TLS=$TLS
EOF
        }
        
        case $OPT in
            01|1) WEBSOCKET="active"; save_config; echo -e "${GREEN}✅ WebSocket ativado!${NC}"; sleep 2 ;;
            02|2) WEBSOCKET="inactive"; save_config; echo -e "${RED}❌ WebSocket desativado!${NC}"; sleep 2 ;;
            03|3) SECURITY="active"; save_config; echo -e "${GREEN}✅ SECURITY ativado!${NC}"; sleep 2 ;;
            04|4) SECURITY="inactive"; save_config; echo -e "${RED}❌ SECURITY desativado!${NC}"; sleep 2 ;;
            05|5) SOCKS5="active"; save_config; echo -e "${GREEN}✅ SOCKS5 ativado!${NC}"; sleep 2 ;;
            06|6) SOCKS5="inactive"; save_config; echo -e "${RED}❌ SOCKS5 desativado!${NC}"; sleep 2 ;;
            07|7) TLS="active"; save_config; echo -e "${GREEN}✅ TLS ativado!${NC}"; sleep 2 ;;
            08|8) TLS="inactive"; save_config; echo -e "${RED}❌ TLS desativado!${NC}"; sleep 2 ;;
            09|9) return ;;
            *) echo -e "${RED}❌ Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

show_multistatus() {
    show_header
    echo -e "${YELLOW}📊 MULTISTATUS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    
    if pgrep -f "/opt/zxproxy/proxy" > /dev/null; then
        echo -e "${GREEN}✅ Proxy está ATIVO${NC}"
        echo ""
        echo -e "${GREEN}Portas ativas:${NC}"
        for pidfile in ${PID_FILE}*.pid; do
            if [ -f "$pidfile" ]; then
                PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
                PID=$(cat "$pidfile")
                if ps -p $PID > /dev/null 2>&1; then
                    echo -e "  ${CYAN}✅ Porta $PORT (PID: $PID)${NC}"
                    echo -e "     ${GREEN}WebSocket: ${WEBSOCKET:-active}${NC}"
                    echo -e "     ${GREEN}SECURITY: ${SECURITY:-active}${NC}"
                    echo -e "     ${GREEN}SOCKS5: ${SOCKS5:-active}${NC}"
                    echo -e "     ${GREEN}TLS: ${TLS:-active}${NC}"
                    echo ""
                fi
            fi
        done
        
        echo -e "${GREEN}Estatísticas:${NC}"
        for pidfile in ${PID_FILE}*.pid; do
            if [ -f "$pidfile" ]; then
                PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
                LOG="/tmp/zxproxy_${PORT}.log"
                if [ -f "$LOG" ]; then
                    CONNECTIONS=$(grep -c "📩" "$LOG" 2>/dev/null || echo "0")
                    KEEP_ALIVE=$(grep -c "💓" "$LOG" 2>/dev/null || echo "0")
                    echo -e "  ${CYAN}Porta $PORT:${NC}"
                    echo -e "     Conexões: $CONNECTIONS"
                    echo -e "     Keep-Alive: $KEEP_ALIVE"
                fi
            fi
        done
    else
        echo -e "${RED}❌ Proxy está INATIVO${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    read -p "Pressione Enter para continuar..."
}

parar_websocket_security() {
    show_header
    echo -e "${YELLOW}🛑 PARAR WEBSOCKET SECURITY${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}⚠️  ATENÇÃO: Isso vai parar o WebSocket Security${NC}"
    echo ""
    read -p "Tem certeza? (s/n): " CONFIRM
    if [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]]; then
        echo -e "${YELLOW}🛑 Parando WebSocket Security...${NC}"
        sudo pkill -f "/opt/zxproxy/proxy" 2>/dev/null
        sudo rm -f /tmp/*proxy*.pid
        WEBSOCKET="inactive"
        cat > "$CONFIG_FILE" << EOF
PORT=$PORT
WEBSOCKET=$WEBSOCKET
SECURITY=$SECURITY
SOCKS5=$SOCKS5
TLS=$TLS
EOF
        echo -e "${GREEN}✅ WebSocket Security parado!${NC}"
        sleep 3
    else
        echo -e "${GREEN}✅ Operação cancelada!${NC}"
        sleep 2
    fi
}

# Loop principal
while true; do
    show_menu_principal
    read OPT
    case $OPT in
        01|1) abrir_porta ;;
        02|2) alterar_status ;;
        03|3) show_multiprotocol ;;
        04|4) show_multistatus ;;
        05|5) parar_websocket_security ;;
        06|6) echo -e "${GREEN}👋 Saindo...${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Opção inválida!${NC}"; sleep 2 ;;
    esac
done
