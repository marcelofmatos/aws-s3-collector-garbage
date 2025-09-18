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

# Função para encontrar o último nível de diretórios
find_deepest_directories() {
    local current_prefix="$1"
    local current_level="$2"
    
    # Lista subdiretorios no nivel atual
    local subdirs=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$current_prefix" --delimiter "/" --query 'CommonPrefixes[*].Prefix' --output text $PARAMS 2>/dev/null | tr '\t' '\n')
    
    if [ -z "$subdirs" ] || [ "$subdirs" = "None" ]; then
        # Não há mais subdiretorios, este é o último nível
        echo "$current_prefix"
        return 0
    fi
    
    # Há subdiretorios, vamos explorá-los recursivamente
    echo "$subdirs" | while read -r subdir; do
        if [ -n "$subdir" ] && [ "$subdir" != "None" ]; then
            find_deepest_directories "$subdir" $((current_level + 1))
        fi
    done
}

# Função para processar arquivos em um diretório do último nível
process_leaf_directory() {
    local dir_prefix="$1"
    local objects_to_delete=""
    local object_count=0
    local deleted_count=0
    local expired_count=0
    
    log "Processando diretório final: $dir_prefix"
    
    # Lista apenas arquivos (não diretorios) no diretorio especifico
    aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$dir_prefix" --output text --query 'Contents[*].[Key,LastModified]' $PARAMS | while IFS=$'\t' read -r key last_modified; do
        if [ -z "$key" ] || [ "$key" = "None" ]; then
            continue
        fi
        
        # Ignora se for o próprio diretório (termina com /)
        if [ "$key" = "$dir_prefix" ]; then
            continue
        fi
        
        object_count=$((object_count + 1))
        
        # Converte a data do objeto para timestamp
        object_date=$(echo "$last_modified" | cut -c1-10)
        object_timestamp=$(date -d "$object_date" '+%s' 2>/dev/null || echo "0")
        
        # Verifica se o objeto é mais antigo que o período de retenção
        if [ "$object_timestamp" -lt "$CUTOFF_TIMESTAMP" ] && [ "$object_timestamp" -ne "0" ]; then
            log "Objeto expirado encontrado: $key (data: $object_date)"
            expired_count=$((expired_count + 1))
            
            # Remove o objeto imediatamente
            execute_or_simulate "aws s3 rm s3://$BUCKET/$key $PARAMS"
        fi
    done
    
    if [ $expired_count -gt 0 ]; then
        log "Removidos $expired_count objetos expirados de $dir_prefix"
        
        # Verifica se o diretório ficou vazio após remoção
        remaining_objects=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$dir_prefix" --max-items 1 --query 'Contents[0].Key' --output text $PARAMS 2>/dev/null)
        
        if [ "$remaining_objects" = "None" ] || [ -z "$remaining_objects" ]; then
            log "Diretório vazio detectado: $dir_prefix - removendo"
            # Remove o "diretório" se ele for representado como um objeto
            execute_or_simulate "aws s3 rm s3://$BUCKET/$dir_prefix $PARAMS 2>/dev/null || true"
        fi
    else
        log "Nenhum objeto expirado em $dir_prefix"
    fi
}

# Encontra e processa diretórios do último nível
log "Descobrindo estrutura de diretórios..."

# Se BUCKET_PATH estiver definido, usa como prefixo base
if [ -n "$BUCKET_PATH" ]; then
    search_prefix="$BUCKET_PATH/"
else
    search_prefix=""
fi

log "Procurando diretórios do último nível a partir de: $search_prefix"

# Encontra todos os diretórios do último nível
deepest_dirs=$(find_deepest_directories "$search_prefix" 1)

if [ -z "$deepest_dirs" ]; then
    log "Nenhum diretório encontrado para processar"
else
    # Processa cada diretório do último nível encontrado
    echo "$deepest_dirs" | while read -r leaf_dir; do
        if [ -n "$leaf_dir" ] && [ "$leaf_dir" != "None" ]; then
            process_leaf_directory "$leaf_dir"
        fi
    done
fi

log "=== Garbage collection finalizado ==="