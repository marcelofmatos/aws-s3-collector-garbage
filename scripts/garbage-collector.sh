#!/bin/ash

set -e

# Configurações e validações
# Compatibilidade com versão anterior
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-}

# Novo sistema de retenção granular
RETENTION_YEARLY=${RETENTION_YEARLY:-0}    # Quantos backups manter por ano (0 = desabilitado)
RETENTION_MONTHLY=${RETENTION_MONTHLY:-0}  # Quantos backups manter por mês (0 = desabilitado)
RETENTION_WEEKLY=${RETENTION_WEEKLY:-0}    # Quantos backups manter por semana (0 = desabilitado)
RETENTION_DAILY=${RETENTION_DAILY:-7}      # Quantos backups manter por dia (padrão: 7)

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

# Mostra políticas de retenção ativas
# Verifica se alguma política granular foi definida explicitamente
GRANULAR_DEFINED=false
[ "${RETENTION_YEARLY:-0}" != "0" ] && GRANULAR_DEFINED=true
[ "${RETENTION_MONTHLY:-0}" != "0" ] && GRANULAR_DEFINED=true  
[ "${RETENTION_WEEKLY:-0}" != "0" ] && GRANULAR_DEFINED=true
[ "${RETENTION_DAILY:-7}" != "7" ] && GRANULAR_DEFINED=true

if [ "$GRANULAR_DEFINED" = "true" ]; then
    log "Políticas de retenção granular:"
    [ $RETENTION_YEARLY -gt 0 ] && log "  - Anual: $RETENTION_YEARLY backups por ano"
    [ $RETENTION_MONTHLY -gt 0 ] && log "  - Mensal: $RETENTION_MONTHLY backups por mês"
    [ $RETENTION_WEEKLY -gt 0 ] && log "  - Semanal: $RETENTION_WEEKLY backups por semana"
    [ $RETENTION_DAILY -gt 0 ] && log "  - Diário: $RETENTION_DAILY backups por dia"
    # Desabilita modo compatibilidade quando granular estiver ativo
    BACKUP_RETENTION_DAYS=""
elif [ -n "$BACKUP_RETENTION_DAYS" ]; then
    log "Modo compatibilidade: $BACKUP_RETENTION_DAYS dias"
else
    log "Usando política padrão diária: $RETENTION_DAILY backups por dia"
fi

log "Parâmetros AWS: $PARAMS"
log "Modo dry-run: $DRY_RUN"

# Preparação para análise de retenção
CURRENT_DATE=$(date '+%Y-%m-%d')
CURRENT_TIMESTAMP=$(date '+%s')
log "Data atual: $CURRENT_DATE (timestamp: $CURRENT_TIMESTAMP)"

# Função para determinar se um arquivo deve ser mantido baseado nas políticas de retenção
should_keep_file() {
    local file_date="$1"
    local file_timestamp="$2"
    local file_key="$3"
    
    # Modo compatibilidade com versão anterior
    if [ -n "$BACKUP_RETENTION_DAYS" ]; then
        local cutoff_timestamp=$(date -d "$BACKUP_RETENTION_DAYS days ago" '+%s')
        if [ "$file_timestamp" -lt "$cutoff_timestamp" ]; then
            return 1  # Deve remover
        else
            return 0  # Deve manter
        fi
    fi
    
    # Novo sistema granular
    local file_year=$(date -d "$file_date" '+%Y')
    local file_month=$(date -d "$file_date" '+%Y-%m')
    local file_week=$(date -d "$file_date" '+%Y-%U')
    local file_day="$file_date"
    
    # Verifica retenção anual
    if [ $RETENTION_YEARLY -gt 0 ]; then
        local current_year=$(date '+%Y')
        if [ "$file_year" != "$current_year" ]; then
            # Arquivo de ano anterior - aplicar política anual
            if is_within_yearly_retention "$file_year" "$file_key"; then
                log "Mantendo $file_key (política anual)"
                return 0
            fi
        fi
    fi
    
    # Verifica retenção mensal  
    if [ $RETENTION_MONTHLY -gt 0 ]; then
        local current_month=$(date '+%Y-%m')
        if [ "$file_month" != "$current_month" ]; then
            # Arquivo de mês anterior - aplicar política mensal
            if is_within_monthly_retention "$file_month" "$file_key"; then
                log "Mantendo $file_key (política mensal)"
                return 0
            fi
        fi
    fi
    
    # Verifica retenção semanal
    if [ $RETENTION_WEEKLY -gt 0 ]; then
        local current_week=$(date '+%Y-%U')
        if [ "$file_week" != "$current_week" ]; then
            # Arquivo de semana anterior - aplicar política semanal
            if is_within_weekly_retention "$file_week" "$file_key"; then
                log "Mantendo $file_key (política semanal)"
                return 0
            fi
        fi
    fi
    
    # Verifica retenção diária
    if [ $RETENTION_DAILY -gt 0 ]; then
        local current_day=$(date '+%Y-%m-%d')
        if [ "$file_day" != "$current_day" ]; then
            # Arquivo de dia anterior - aplicar política diária
            if is_within_daily_retention "$file_day" "$file_key"; then
                log "Mantendo $file_key (política diária)"
                return 0
            fi
        fi
    fi
    
    # Se chegou até aqui, o arquivo deve ser removido
    return 1
}

# Verifica se o arquivo deve ser mantido pela política anual
is_within_yearly_retention() {
    local target_year="$1"
    local file_key="$2"
    
    # Conta quantos arquivos já existem para este ano
    local count=$(get_file_count_for_period "year" "$target_year")
    
    if [ "$count" -lt "$RETENTION_YEARLY" ]; then
        return 0  # Manter
    else
        return 1  # Remover
    fi
}

# Verifica se o arquivo deve ser mantido pela política mensal
is_within_monthly_retention() {
    local target_month="$1"
    local file_key="$2"
    
    local count=$(get_file_count_for_period "month" "$target_month")
    
    if [ "$count" -lt "$RETENTION_MONTHLY" ]; then
        return 0  # Manter
    else
        return 1  # Remover
    fi
}

# Verifica se o arquivo deve ser mantido pela política semanal
is_within_weekly_retention() {
    local target_week="$1"
    local file_key="$2"
    
    local count=$(get_file_count_for_period "week" "$target_week")
    
    if [ "$count" -lt "$RETENTION_WEEKLY" ]; then
        return 0  # Manter
    else
        return 1  # Remover
    fi
}

# Verifica se o arquivo deve ser mantido pela política diária
is_within_daily_retention() {
    local target_day="$1"
    local file_key="$2"
    
    local count=$(get_file_count_for_period "day" "$target_day")
    
    if [ "$count" -lt "$RETENTION_DAILY" ]; then
        return 0  # Manter
    else
        return 1  # Remover
    fi
}

# Conta arquivos para um período específico (implementação simplificada)
get_file_count_for_period() {
    local period_type="$1"
    local period_value="$2"
    
    # Para uma implementação inicial, sempre retorna 0
    # Em uma implementação mais sofisticada, isso faria uma consulta S3
    # para contar arquivos existentes no período
    echo "0"
}

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
        
        # Usa nova função para verificar se o arquivo deve ser mantido
        if [ "$object_timestamp" -ne "0" ] && ! should_keep_file "$object_date" "$object_timestamp" "$key"; then
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