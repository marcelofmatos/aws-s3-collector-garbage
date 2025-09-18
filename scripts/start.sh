#!/bin/ash

set -e

# Configuração das credenciais AWS (compatibilidade com a imagem base)
export AWS_ACCESS_KEY_ID="$KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET"
export AWS_DEFAULT_REGION="$REGION"

# Função para exibir ajuda
show_help() {
    cat << EOF
AWS S3 Sync & Garbage Collector

Uso:
    docker run [opções] imagem [comando]

Comandos disponíveis:
    sync            - Sincroniza arquivos locais com S3 (padrão da imagem original)
    gc              - Executa garbage collection (remove backups antigos)
    garbage-collect - Alias para 'gc'
    help            - Exibe esta ajuda

Variáveis de ambiente:
    KEY                     - AWS Access Key ID (obrigatório)
    SECRET                  - AWS Secret Access Key (obrigatório)
    REGION                  - AWS Region (obrigatório)
    BUCKET                  - Nome do bucket S3 (obrigatório)
    BUCKET_PATH             - Caminho dentro do bucket (padrão: /)
    BACKUP_RETENTION_DAYS   - Dias de retenção para garbage collection (padrão: 7)
    PARAMS                  - Parâmetros adicionais para comandos AWS CLI (opcional)
    CRON_SCHEDULE           - Agenda cron para execução periódica (opcional)
    DRY_RUN                 - Modo dry-run para garbage collection (padrão: false)
    VERBOSE                 - Log verboso (padrão: true)

Exemplos:
    # Execução única do garbage collector
    docker run --rm -e KEY=... -e SECRET=... -e REGION=... -e BUCKET=... imagem gc

    # Garbage collector com cron (executa às 3h da manhã diariamente)
    docker run -d -e KEY=... -e SECRET=... -e REGION=... -e BUCKET=... -e CRON_SCHEDULE="0 3 * * *" imagem gc

    # Modo dry-run (apenas simula, não executa)
    docker run --rm -e KEY=... -e SECRET=... -e REGION=... -e BUCKET=... -e DRY_RUN=true imagem gc
EOF
}

# Função para executar o sync original (compatibilidade)
run_sync() {
    echo "$(date) - Iniciando sincronização S3"
    
    if [ -n "$CRON_SCHEDULE" ]; then
        echo "Configurando cron para sincronização: $CRON_SCHEDULE"
        echo "$CRON_SCHEDULE /sync.sh" > /var/spool/cron/crontabs/root
        echo "Iniciando cron daemon..."
        crond -l 2 -f
    else
        echo "Executando sincronização única..."
        /sync.sh
    fi
}

# Função para executar garbage collection
run_garbage_collection() {
    echo "$(date) - Iniciando garbage collection S3"
    
    if [ -n "$CRON_SCHEDULE" ]; then
        echo "Configurando cron para garbage collection: $CRON_SCHEDULE"
        echo "$CRON_SCHEDULE /usr/local/bin/garbage-collector.sh" > /var/spool/cron/crontabs/root
        echo "Iniciando cron daemon..."
        crond -l 2 -f
    else
        echo "Executando garbage collection única..."
        /usr/local/bin/garbage-collector.sh
    fi
}

# Processamento dos argumentos
case "${1:-sync}" in
    "sync")
        echo "Modo: Sincronização S3"
        run_sync
        ;;
    "gc"|"garbage-collect")
        echo "Modo: Garbage Collection S3"
        run_garbage_collection
        ;;
    "help"|"--help"|"-h")
        show_help
        exit 0
        ;;
    "now")
        # Compatibilidade com a imagem original - executa sync imediatamente
        echo "Modo: Sincronização imediata (compatibilidade)"
        /sync.sh
        ;;
    *)
        echo "Comando desconhecido: $1"
        echo "Use 'help' para ver os comandos disponíveis."
        exit 1
        ;;
esac