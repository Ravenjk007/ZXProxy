#!/bin/bash
ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"

show_menu() {
    clear
    echo "====================================="
    echo "          ZXProxy Menu              "
    echo "====================================="
    echo ""
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
        echo "Porta(s) aberta(s):$ACTIVE_PORTS"
    else
        echo "Porta(s): nenhuma"
    fi
    echo ""
    echo " 1 - Abrir Porta"
    echo " 2 - Fechar Porta"
    echo " 3 - Status do Proxy"
    echo " 4 - Sair"
    echo ""
    echo -n "--> Selecione uma opção: "
}

open_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        echo "❌ Porta ${PORT} já está aberta!"
        sleep 2
        return
    fi
    echo "🔓 Abrindo porta ${PORT}..."
    if [ ! -f "$ZXPROXY" ]; then
        echo "❌ ZXProxy não encontrado em ${ZXPROXY}!"
        echo "📦 Por favor, instale o ZXProxy primeiro."
        sleep 3
        return
    fi
    nohup ${ZXPROXY} -p ${PORT} -d > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 2
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo "✅ Porta ${PORT} aberta com sucesso!"
        echo "📡 Proxy rodando em: 0.0.0.0:${PORT}"
        echo "🔒 Modo VPN: Ativado"
        echo "📋 Logs: /tmp/zxproxy_${PORT}.log"
    else
        echo "❌ Falha ao abrir a porta ${PORT}!"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    sleep 3
}

close_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo "✅ Porta ${PORT} fechada com sucesso!"
        echo "🗑️  Processo ${PID} terminado."
    else
        echo "❌ Porta ${PORT} não está aberta!"
    fi
    sleep 2
}

show_status() {
    clear
    echo "====================================="
    echo "       ZXProxy Status               "
    echo "====================================="
    echo ""
    
    # Verifica se o ZXProxy existe
    if [ -f "$ZXPROXY" ]; then
        echo "✅ ZXProxy instalado em: $ZXPROXY"
        VERSION=$(${ZXPROXY} --version 2>/dev/null || echo "v2.0.0")
        echo "📦 Versão: $VERSION"
    else
        echo "❌ ZXProxy não encontrado em: $ZXPROXY"
        echo "📥 Instale o ZXProxy primeiro."
    fi
    echo ""
    
    # Lista portas ativas
    echo "📡 Portas Ativas:"
    FOUND=false
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                PID=$(cat "$pidfile")
                echo "   🔹 Porta ${PORT} - PID: ${PID}"
                # Mostra uso de memória e CPU
                if command -v ps &> /dev/null; then
                    CPU=$(ps -p $PID -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    MEM=$(ps -p $PID -o %mem --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    echo "      CPU: ${CPU}% | MEM: ${MEM}%"
                fi
                FOUND=true
            else
                rm -f "$pidfile"
            fi
        fi
    done
    if [ "$FOUND" = false ]; then
        echo "   Nenhuma porta ativa"
    fi
    echo ""
    
    # Mostra logs recentes
    echo "📋 Últimos logs:"
    LATEST_LOG=$(ls -t /tmp/zxproxy_*.log 2>/dev/null | head -1)
    if [ -f "$LATEST_LOG" ]; then
        echo "   Arquivo: $(basename $LATEST_LOG)"
        tail -3 "$LATEST_LOG" 2>/dev/null | while read line; do
            echo "   $line"
        done
    else
        echo "   Nenhum log disponível"
    fi
    echo ""
    echo "====================================="
    echo "Pressione ENTER para voltar..."
    read
}

# Verifica dependências
check_dependencies() {
    if ! command -v ps &> /dev/null; then
        echo "⚠️  Comando 'ps' não encontrado. Instale procps."
        exit 1
    fi
}

# Função principal
main() {
    check_dependencies
    
    # Cria diretório se não existir
    mkdir -p /opt/zxproxy
    
    while true; do
        show_menu
        read OPTION
        case $OPTION in
            1) open_port ;;
            2) close_port ;;
            3) show_status ;;
            4) echo "👋 Saindo do ZXProxy Manager..."; exit 0 ;;
            *) echo "❌ Opção inválida!"; sleep 2 ;;
        esac
    done
}

# Executa o script
main
