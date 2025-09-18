#!/bin/ash

set -e

# Configurações e validações
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
DRY_RUN=${DRY_RUN:-false}
VERBOSE=${VERBOSE:-true}
PARAMS=${PARAMS:-}

# Configuração do AWS
export AWS_ACCESS_KEY_ID="$KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET"
export AWS_DEFAULT_REGION="$REGION"

# Validação das variáveis obrigatórias
if [ -z "$KEY" ] || [ -z "$SECRET" ] || [ -z "$REGION" ] || [ -z "$BUCKET" ]; then
    echo "ERROR: Variáveis obrigatórias não definidas:"
    echo "  KEY (AWS_ACCESS_KEY_ID)"
    echo "  SECRET (AWS_SECRET_ACCESS_KEY)"
    echo "  REGION (AWS_DEFAULT_REGION)"
    echo "  BUCKET"
    exit 1
fi

# Configuração de paths
BUCKET_PATH=${BUCKET_PATH:-/}
if [ "$BUCKET_PATH" = "/" ]; then
    BUCKET_PATH=""
fi

# Remove leading slash se existir
BUCKET_PATH=$(echo "$BUCKET_PATH" | sed 's|^/||')

# Log function
log() {
    if [ "$VERBOSE" = "true" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Dry run function
execute_or_simulate() {
    local cmd="$1"
    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY RUN] $cmd"
    else
        log "Executando: $cmd"
        eval "$cmd"
    fi
}

log "=== AWS S3 Garbage Collector iniciado ==="
log "Bucket: s3://$BUCKET"
log "Path: $BUCKET_PATH"
log "Retenção: $BACKUP_RETENTION_DAYS dias"
log "Parâmetros AWS: $PARAMS"
log "Modo dry-run: $DRY_RUN"

# Calcula a data de corte (retention window)
CUTOFF_DATE=$(date -d "$BACKUP_RETENTION_DAYS days ago" '+%Y-%m-%d')
CUTOFF_TIMESTAMP=$(date -d "$CUTOFF_DATE" '+%s')

log "Data de corte: $CUTOFF_DATE (timestamp: $CUTOFF_TIMESTAMP)"

# Função para processar objetos de um diretório específico
process_directory() {
    local dir_prefix="$1"
    local objects_to_delete=""
    local object_count=0
    local deleted_count=0
    
    log "Processando diretório: $dir_prefix"
    
    # Lista todos os objetos no diretório específico
    aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$dir_prefix" --output text --query 'Contents[*].[Key,LastModified]' $PARAMS | while IFS=$'\t' read -r key last_modified; do
        if [ -z "$key" ] || [ "$key" = "None" ]; then
            continue
        fi
        
        object_count=$((object_count + 1))
        
        # Converte a data do objeto para timestamp
        object_date=$(echo "$last_modified" | cut -c1-10)
        object_timestamp=$(date -d "$object_date" '+%s' 2>/dev/null || echo "0")
        
        # Verifica se o objeto é mais antigo que o período de retenção
        if [ "$object_timestamp" -lt "$CUTOFF_TIMESTAMP" ] && [ "$object_timestamp" -ne "0" ]; then
            log "Objeto expirado encontrado: $key (data: $object_date)"
            
            if [ -n "$objects_to_delete" ]; then
                objects_to_delete="$objects_to_delete "
            fi
            objects_to_delete="$objects_to_delete$key"
            deleted_count=$((deleted_count + 1))
            
            # Remove o objeto (em lotes para eficiência)
            if [ $deleted_count -ge 50 ]; then
                execute_or_simulate "aws s3 rm s3://$BUCKET/$key $PARAMS"
                objects_to_delete=""
                deleted_count=0
            fi
        fi
    done
    
    # Remove objetos restantes
    if [ -n "$objects_to_delete" ]; then
        for obj in $objects_to_delete; do
            execute_or_simulate "aws s3 rm s3://$BUCKET/$obj $PARAMS"
        done
    fi
    
    # Verifica se o diretório ficou vazio e o remove se necessário
    remaining_objects=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$dir_prefix" --max-items 1 --query 'Contents[0].Key' --output text $PARAMS)
    if [ "$remaining_objects" = "None" ] || [ -z "$remaining_objects" ]; then
        log "Diretório vazio detectado: $dir_prefix - removendo"
        execute_or_simulate "aws s3api delete-object --bucket '$BUCKET' --key '$dir_prefix' $PARAMS"
    fi
}

# Lista todos os prefixos do segundo nível (diretórios)
log "Listando diretórios no segundo nível..."

# Se BUCKET_PATH estiver definido, usa como prefixo base
if [ -n "$BUCKET_PATH" ]; then
    search_prefix="$BUCKET_PATH/"
else
    search_prefix=""
fi

# Lista todos os "diretórios" no segundo nível usando delimitador
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$search_prefix" --delimiter "/" --query 'CommonPrefixes[*].Prefix' --output text $PARAMS | tr '\t' '\n' | while read -r first_level_prefix; do
    if [ -z "$first_level_prefix" ] || [ "$first_level_prefix" = "None" ]; then
        continue
    fi
    
    log "Processando primeiro nível: $first_level_prefix"
    
    # Para cada diretório de primeiro nível, lista os do segundo nível
    aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$first_level_prefix" --delimiter "/" --query 'CommonPrefixes[*].Prefix' --output text $PARAMS | tr '\t' '\n' | while read -r second_level_prefix; do
        if [ -z "$second_level_prefix" ] || [ "$second_level_prefix" = "None" ]; then
            continue
        fi
        
        # Processa este diretório de segundo nível
        process_directory "$second_level_prefix"
    done
done

log "=== Garbage collection finalizado ==="