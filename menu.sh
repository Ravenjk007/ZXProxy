#!/bin/bash
ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"
CONFIG_FILE="/opt/zxproxy/config.conf"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Criar diretório se não existir
mkdir -p /opt/zxproxy

# Configurações padrão
cat > /opt/zxproxy/config.conf << 'EOF'
PORT=80
PROTOCOL=all
WEBSOCKET=active
SECURITY=active
SOCKS5=active
TLS=active
MULTIPROTOCOL=active
MULTISTATUS=active
EOF

# Função para carregar configurações
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Função para salvar configurações
save_config() {
    cat > "$CONFIG_FILE" << EOF
PORT=$PORT
PROTOCOL=$PROTOCOL
WEBSOCKET=$WEBSOCKET
SECURITY=$SECURITY
SOCKS5=$SOCKS5
TLS=$TLS
MULTIPROTOCOL=$MULTIPROTOCOL
MULTISTATUS=$MULTISTATUS
EOF
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
    echo -e "${GREEN}PORTA(S): ${PORT:-80}${NC}"
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
        echo -e "${CYAN}[07] • VOLTAR${NC}"
        echo ""
        echo -n -e "${YELLOW}INFORME UMA OPCAO: ${NC}"
        read OPT
        
        case $OPT in
            01|1) WEBSOCKET="active"; save_config; echo -e "${GREEN}✅ WebSocket ativado!${NC}"; sleep 2 ;;
            02|2) WEBSOCKET="inactive"; save_config; echo -e "${RED}❌ WebSocket desativado!${NC}"; sleep 2 ;;
            03|3) SECURITY="active"; save_config; echo -e "${GREEN}✅ SECURITY ativado!${NC}"; sleep 2 ;;
            04|4) SECURITY="inactive"; save_config; echo -e "${RED}❌ SECURITY desativado!${NC}"; sleep 2 ;;
            05|5) SOCKS5="active"; save_config; echo -e "${GREEN}✅ SOCKS5 ativado!${NC}"; sleep 2 ;;
            06|6) SOCKS5="inactive"; save_config; echo -e "${RED}❌ SOCKS5 desativado!${NC}"; sleep 2 ;;
            07|7) return ;;
            *) echo -e "${RED}❌ Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

show_multistatus() {
    show_header
    echo -e "${YELLOW}📊 MULTISTATUS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    
    # Status do Proxy
    echo -e "${GREEN}Status do Proxy:${NC}"
    if pgrep -f "zxproxy.*-p" > /dev/null; then
        echo -e "  ${GREEN}✅ ATIVO${NC}"
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
    else
        echo -e "  ${RED}❌ INATIVO${NC}"
    fi
    
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    read -p "Pressione Enter para continuar..."
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
    
    # Matar processo na porta
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
    
    # Construir argumentos baseado nas configurações
    ARGS="-p ${PORT}"
    
    if [ "$WEBSOCKET" = "active" ]; then
        ARGS="$ARGS --websocket"
    fi
    if [ "$SECURITY" = "active" ]; then
        ARGS="$ARGS --security"
    fi
    if [ "$SOCKS5" = "active" ]; then
        ARGS="$ARGS --socks5"
    fi
    if [ "$TLS" = "active" ]; then
        ARGS="$ARGS --tls"
    fi
    
    # Iniciar
    if [ "$PORT" -lt 1024 ]; then
        nohup sudo ${ZXPROXY} ${ARGS} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    else
        nohup ${ZXPROXY} ${ARGS} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    fi
    
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 3
    
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Porta ${PORT} aberta com sucesso!${NC}"
        echo -e "📝 Log: /tmp/zxproxy_${PORT}.log"
        echo -e "📡 Protocolos ativos:"
        [ "$WEBSOCKET" = "active" ] && echo -e "   ✅ WebSocket"
        [ "$SECURITY" = "active" ] && echo -e "   ✅ SECURITY"
        [ "$SOCKS5" = "active" ] && echo -e "   ✅ SOCKS5"
        [ "$TLS" = "active" ] && echo -e "   ✅ TLS/SSL"
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
    
    if pgrep -f "zxproxy.*-p" > /dev/null; then
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
                sudo pkill -9 zxproxy 2>/dev/null
                sudo rm -f /tmp/*proxy*.pid
                echo -e "${GREEN}✅ Proxy parado!${NC}"
                sleep 2
                ;;
            02|2)
                echo -e "${YELLOW}🔄 Reiniciando proxy...${NC}"
                sudo pkill -9 zxproxy 2>/dev/null
                sudo rm -f /tmp/*proxy*.pid
                sleep 2
                abrir_porta
                ;;
            03|3)
                return
                ;;
            *)
                echo -e "${RED}❌ Opção inválida!${NC}"
                sleep 2
                ;;
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
            01|1)
                abrir_porta
                ;;
            02|2)
                return
                ;;
            *)
                echo -e "${RED}❌ Opção inválida!${NC}"
                sleep 2
                ;;
        esac
    fi
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
        
        # Parar todos os processos
        sudo pkill -9 zxproxy 2>/dev/null
        sudo rm -f /tmp/*proxy*.pid
        
        # Desativar WebSocket nas configurações
        WEBSOCKET="inactive"
        save_config
        
        echo -e "${GREEN}✅ WebSocket Security parado!${NC}"
        echo -e "📝 Para reativar, vá em MULTIPROTOCOLO"
        sleep 3
    else
        echo -e "${GREEN}✅ Operação cancelada!${NC}"
        sleep 2
    fi
}

# Loop principal do menu
while true; do
    show_menu_principal
    read OPT
    
    case $OPT in
        01|1) abrir_porta ;;
        02|2) alterar_status ;;
        03|3) show_multiprotocol ;;
        04|4) show_multistatus ;;
        05|5) parar_websocket_security ;;
        06|6) 
            echo -e "${GREEN}👋 Saindo...${NC}"
            exit 0 
            ;;
        *) 
            echo -e "${RED}❌ Opção inválida!${NC}"
            sleep 2 
            ;;
    esac
done
