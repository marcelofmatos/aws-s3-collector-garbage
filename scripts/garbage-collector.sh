#!/bin/ash

set -e

# Configurações e validações
# Compatibilidade com versão anterior
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-}

# Novo sistema de retenção granular
RETENTION_YEARLY=${RETENTION_YEARLY:-0}    # Quantos backups manter por ano (0 = desabilitado)
RETENTION_MONTHLY=${RETENTION_MONTHLY:-0}  # Quantos backups manter por mês (0 = desabilitado)
RETENTION_WEEKLY=${RETENTION_WEEKLY:-0}    # Quantos backups manter por semana (0 = desabilitado)
RETENTION_DAILY=${RETENTION_DAILY:-1}      # Quantos backups manter por dia (padrão: 1)

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
[ "${RETENTION_DAILY:-1}" != "1" ] && GRANULAR_DEFINED=true

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
    log "Usando política padrão diária: $RETENTION_DAILY backup por dia"
fi

log "Parâmetros AWS: $PARAMS"
log "Modo dry-run: $DRY_RUN"

# Preparação para análise de retenção
CURRENT_DATE=$(date '+%Y-%m-%d')
CURRENT_TIMESTAMP=$(date '+%s')
log "Data atual: $CURRENT_DATE (timestamp: $CURRENT_TIMESTAMP)"

# Diretório temporário para contadores por cliente
COUNTERS_DIR="/tmp/retention_counters_$$"
mkdir -p "$COUNTERS_DIR"

# Funções para gerenciar contadores
get_counter() {
    local key="$1"
    local counter_file="$COUNTERS_DIR/${key//[\/.:]/}"
    if [ -f "$counter_file" ]; then
        cat "$counter_file"
    else
        echo "0"
    fi
}

increment_counter() {
    local key="$1"
    local counter_file="$COUNTERS_DIR/${key//[\/.:]/}"
    local current=$(get_counter "$key")
    echo $((current + 1)) > "$counter_file"
}

# Função para determinar se um arquivo deve ser mantido baseado nas políticas de retenção
should_keep_file() {
    local file_date="$1"
    local file_timestamp="$2"
    local file_key="$3"
    local client_context="${4:-global}"
    
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
    
    local current_year=$(date '+%Y')
    local current_month=$(date '+%Y-%m')
    local current_week=$(date '+%Y-%U')
    local current_day=$(date '+%Y-%m-%d')
    
    # SEMPRE manter arquivos do dia atual
    if [ "$file_day" = "$current_day" ]; then
        log "Mantendo $file_key (arquivo do dia atual)"
        return 0
    fi
    
    # Calcular idade do arquivo em dias
    local days_diff=$(( ($(date '+%s') - $file_timestamp) / 86400 ))
    
    # Aplicar políticas de retenção baseada na idade
    
    # Sistema de retenção hierárquico: aplica a política mais restritiva primeiro
    
    # Política diária: manter backups dos últimos N dias
    if [ $RETENTION_DAILY -gt 0 ] && [ $days_diff -le $RETENTION_DAILY ]; then
        log "Mantendo $file_key (política diária - $days_diff dias atrás)"
        return 0
    fi
    
    # Se passou da política diária, verifica políticas de longo prazo
    
    # Política semanal: manter 1 backup por semana das últimas N semanas (por cliente)
    if [ $RETENTION_WEEKLY -gt 0 ] && [ $days_diff -gt $RETENTION_DAILY ]; then
        local weeks_diff=$(( days_diff / 7 ))
        if [ $weeks_diff -le $RETENTION_WEEKLY ]; then
            # Chave para contador: cliente_semana
            local week_key="weekly_${client_context}_$(date -d "$file_date" '+%Y-%U')"
            local current_count=$(get_counter "$week_key")
            
            if [ $current_count -lt 1 ]; then
                increment_counter "$week_key"
                log "Mantendo $file_key (política semanal - semana $weeks_diff, cliente: $client_context)"
                return 0
            fi
        fi
    fi
    
    # Política mensal: manter 1 backup por mês dos últimos N meses (por cliente)
    if [ $RETENTION_MONTHLY -gt 0 ] && [ $days_diff -gt $(( RETENTION_WEEKLY * 7 )) ]; then
        local months_diff=$(( days_diff / 30 ))
        if [ $months_diff -le $RETENTION_MONTHLY ]; then
            # Chave para contador: cliente_mes
            local month_key="monthly_${client_context}_$(date -d "$file_date" '+%Y-%m')"
            local current_count=$(get_counter "$month_key")
            
            if [ $current_count -lt 1 ]; then
                increment_counter "$month_key"
                log "Mantendo $file_key (política mensal - mês $months_diff, cliente: $client_context)"
                return 0
            fi
        fi
    fi
    
    # Política anual: manter 1 backup por ano dos últimos N anos (por cliente)
    if [ $RETENTION_YEARLY -gt 0 ] && [ $days_diff -gt $(( RETENTION_MONTHLY * 30 )) ]; then
        local years_diff=$(( days_diff / 365 ))
        if [ $years_diff -le $RETENTION_YEARLY ]; then
            # Chave para contador: cliente_ano
            local year_key="yearly_${client_context}_$(date -d "$file_date" '+%Y')"
            local current_count=$(get_counter "$year_key")
            
            if [ $current_count -lt 1 ]; then
                increment_counter "$year_key"
                log "Mantendo $file_key (política anual - ano $years_diff, cliente: $client_context)"
                return 0
            fi
        fi
    fi
    
    # Se chegou até aqui, o arquivo deve ser removido
    return 1
}

# Função para detectar se um nome é puramente um timestamp
gc_is_timestamp_name() {
    local base="${1%/}"
    
    # Remove extensão de arquivo para teste
    local name_no_ext="${base%.*}"
    
    # Padrão YYYY-MM-DD ou YYYY-MM-DD-HHMM ou YYYY_MM_DD_HHMM
    echo "$name_no_ext" | grep -qE '^(19|20)[0-9]{2}([-_])[01][0-9]\2[0-3][0-9](-[0-2][0-9][0-5][0-9])?$' && return 0
    
    # Padrão YYYYMMDD ou YYYYMMDDHHMM
    echo "$name_no_ext" | grep -qE '^(19|20)[0-9]{8}([0-9]{4})?$' && return 0
    
    # Padrão epoch (10 ou 13 dígitos)
    echo "$name_no_ext" | grep -qE '^[0-9]{10}([0-9]{3})?$' && return 0
    
    return 1
}

# Função para extrair prefixo de um item (arquivo ou diretório)
gc_extract_prefix() {
    local name="$1"
    local type="$2"
    local base="${name%/}"
    local prefix=""
    
    # Se for diretório e o nome for puramente timestamp
    if [ "$type" = "dir" ] && gc_is_timestamp_name "$base"; then
        echo "__TS_DIR__"
        return 0
    fi
    
    # Tenta extrair prefixo antes de padrões de data (do mais específico ao menos específico)
    # YYYY-MM-DD-HHMM
    prefix=$(echo "$base" | sed -E 's/^(.+?)[._-]?(19|20)[0-9]{2}[-_][01][0-9][-_][0-3][0-9][-_][0-2][0-9][0-5][0-9].*$/\1/')
    [ "$prefix" != "$base" ] && [ -n "$prefix" ] && { echo "$prefix" | sed 's/[._-]*$//'; return 0; }
    
    # YYYY-MM-DD
    prefix=$(echo "$base" | sed -E 's/^(.+?)[._-]?(19|20)[0-9]{2}[-_][01][0-9][-_][0-3][0-9].*$/\1/')
    [ "$prefix" != "$base" ] && [ -n "$prefix" ] && { echo "$prefix" | sed 's/[._-]*$//'; return 0; }
    
    # YYYYMMDDHHMM
    prefix=$(echo "$base" | sed -E 's/^(.+?)[._-]?(19|20)[0-9]{10}.*$/\1/')
    [ "$prefix" != "$base" ] && [ -n "$prefix" ] && { echo "$prefix" | sed 's/[._-]*$//'; return 0; }
    
    # YYYYMMDD
    prefix=$(echo "$base" | sed -E 's/^(.+?)[._-]?(19|20)[0-9]{8}.*$/\1/')
    [ "$prefix" != "$base" ] && [ -n "$prefix" ] && { echo "$prefix" | sed 's/[._-]*$//'; return 0; }
    
    # Epoch (10 ou 13 dígitos)
    prefix=$(echo "$base" | sed -E 's/^(.+?)[._-]?[0-9]{10}([0-9]{3})?.*$/\1/')
    [ "$prefix" != "$base" ] && [ -n "$prefix" ] && { echo "$prefix" | sed 's/[._-]*$//'; return 0; }
    
    # Se não encontrou data mas o nome é puramente timestamp
    if gc_is_timestamp_name "$base"; then
        if [ "$type" = "file" ]; then
            echo "__TS_FILE__"
        else
            echo "__TS_DIR__"
        fi
        return 0
    fi
    
    # Fallback: usa o nome completo como prefixo (seguro)
    echo "$base"
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

# Função para extrair o cliente/subdiretório base do caminho
get_client_prefix() {
    local file_path="$1"
    # Extrai o primeiro nível do caminho (ex: cti.saas.ligerosmart.com/)
    echo "$file_path" | cut -d'/' -f1
}

# Função para processar backups por cliente
process_client_backups() {
    local client_prefix="$1"
    
    log "Processando backups do cliente: $client_prefix"
    
    # Cria arquivo temporário para armazenar informações dos backups deste cliente
    local temp_file="/tmp/backups_${client_prefix//[.\/]/_}"
    
    # Lista todos os arquivos deste cliente com suas datas
    aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$client_prefix/" \
        --output text --query 'Contents[*].[Key,LastModified]' $PARAMS | \
        while IFS=$'\t' read -r key last_modified; do
            if [ -z "$key" ] || [ "$key" = "None" ] || [[ "$key" == */ ]]; then
                continue
            fi
            
            # Extrai data do caminho ou LastModified
            object_date=$(echo "$last_modified" | cut -c1-10)
            object_timestamp=$(date -d "$object_date" '+%s' 2>/dev/null || echo "0")
            
            if [ "$object_timestamp" -ne "0" ]; then
                echo "$object_timestamp|$object_date|$key" >> "$temp_file"
            fi
        done
    
    if [ ! -f "$temp_file" ]; then
        log "Nenhum backup encontrado para $client_prefix"
        return 0
    fi
    
    # Ordena por timestamp (mais novo primeiro) e processa
    sort -nr "$temp_file" | while IFS='|' read -r timestamp object_date key; do
        if ! should_keep_file "$object_date" "$object_timestamp" "$key" "$client_prefix"; then
            log "Removendo backup expirado: $key (data: $object_date)"
            execute_or_simulate "aws s3 rm \"s3://$BUCKET/$key\" $PARAMS"
        fi
    done
    
    # Limpa arquivo temporário
    rm -f "$temp_file"
}

# Função para processar arquivos em um diretório do último nível
process_leaf_directory() {
    local dir_prefix="$1"
    local object_count=0
    local expired_count=0
    
    log "Processando diretório final: $dir_prefix"
    
    # Cria arquivos temporários para pré-processamento
    local tmp_map=$(mktemp)
    local tmp_grp_counts=$(mktemp)
    local tmp_enriched=$(mktemp)
    local tmp_skip_single=$(mktemp)
    
    # Garante limpeza dos temporários
    trap 'rm -f "$tmp_map" "$tmp_grp_counts" "$tmp_enriched" "$tmp_skip_single" 2>/dev/null || true' RETURN
    
    # Fase 1: Mapear todos os itens (arquivos e subdiretórios) e extrair prefixos
    log "Pré-processando itens para análise de versões..."
    
    # Lista TUDO no diretório (arquivos e subdiretórios)
    aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$dir_prefix" --delimiter "/" --output json $PARAMS 2>/dev/null | \
    awk '
        # Processa arquivos (Contents)
        /"Key":/ {
            gsub(/.*"Key": "/, ""); 
            gsub(/".*/, "");
            if ($0 !~ /\/$/) print $0 "\tfile";
        }
    ' > "$tmp_map.raw" || true
    
    # Adiciona subdiretórios (CommonPrefixes)
    aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$dir_prefix" --delimiter "/" --query 'CommonPrefixes[*].Prefix' --output text $PARAMS 2>/dev/null | \
    tr '\t' '\n' | while read -r subdir; do
        if [ -n "$subdir" ] && [ "$subdir" != "None" ]; then
            echo "${subdir}\tdir" >> "$tmp_map.raw"
        fi
    done
    
    # Processa cada item e extrai prefixo
    if [ ! -f "$tmp_map.raw" ] || [ ! -s "$tmp_map.raw" ]; then
        log "Diretório vazio: $dir_prefix"
        return 0
    fi
    
    while IFS=$'\t' read -r item tipo; do
        # Pula o próprio diretório
        if [ "$item" = "$dir_prefix" ]; then
            continue
        fi
        
        # Extrai apenas o nome base (sem caminho)
        local base="${item%/}"
        base="${base##*/}"
        
        # Extrai prefixo usando função auxiliar
        local prefixo=$(gc_extract_prefix "$base" "$tipo")
        
        # Registra: item, tipo, base, prefixo
        echo "${item}\t${tipo}\t${base}\t${prefixo}" >> "$tmp_map"
    done < "$tmp_map.raw"
    
    rm -f "$tmp_map.raw"
    
    # Verifica se há itens para processar
    if [ ! -s "$tmp_map" ]; then
        log "Nenhum item encontrado em: $dir_prefix"
        return 0
    fi
    
    # Fase 2: Contar itens por prefixo
    awk -F'\t' '{count[$4]++} END {for (prefix in count) print prefix "\t" count[prefix]}' "$tmp_map" > "$tmp_grp_counts"
    
    # Fase 3: Enriquecer mapa com contagens
    awk -F'\t' '
        NR==FNR { counts[$1]=$2; next }
        { print $0 "\t" counts[$4] }
    ' "$tmp_grp_counts" "$tmp_map" > "$tmp_enriched"
    
    # Fase 4: Extrair itens com apenas 1 versão (para skip)
    awk -F'\t' '$5 == 1 {print $1}' "$tmp_enriched" > "$tmp_skip_single"
    
    # Fase 5: Análise e logging
    local total_groups=$(wc -l < "$tmp_grp_counts" | tr -d ' ')
    local single_version_groups=$(awk -F'\t' '$2 == 1' "$tmp_grp_counts" | wc -l | tr -d ' ')
    local multi_version_groups=$((total_groups - single_version_groups))
    local ts_dir_count=$(awk -F'\t' '$2 == "dir" && $4 == "__TS_DIR__"' "$tmp_enriched" | wc -l | tr -d ' ')
    
    log "Pré-checagem de versões: $total_groups grupos, $single_version_groups com 1 versão, $multi_version_groups com 2+ versões, ts_dirs=$ts_dir_count"
    
    # Regra especial: todos os grupos têm apenas 1 versão?
    if [ "$multi_version_groups" -eq 0 ]; then
        log "Todos os prefixos têm 1 versão neste diretório. Pulando processamento (preservando tudo)."
        return 0
    fi
    
    # Regra da pasta raiz: exatamente 1 subpasta timestamp?
    local SKIP_ROOT_FILES=0
    if [ "$ts_dir_count" -eq 1 ]; then
        SKIP_ROOT_FILES=1
        log "Regra raiz: há exatamente 1 subpasta de versão. Arquivos do nível atual serão ignorados."
    fi
    
    # Fase 6: Processar itens aplicando as novas regras
    while IFS=$'\t' read -r item tipo base prefixo count; do
        # Regra raiz: pular arquivos se SKIP_ROOT_FILES=1
        if [ "$SKIP_ROOT_FILES" -eq 1 ] && [ "$tipo" = "file" ]; then
            log "Regra raiz: pulando arquivo '$base' (há apenas 1 subpasta de versão)"
            continue
        fi
        
        # Regra de versão única: pular se count=1
        if [ "$count" -eq 1 ]; then
            log "Regra de versão única: pulando '$base' (prefixo '$prefixo') pois só há 1 versão"
            continue
        fi
        
        # Apenas processar arquivos (não subdiretórios)
        if [ "$tipo" != "file" ]; then
            continue
        fi
        
        object_count=$((object_count + 1))
        
        # Obtém metadados do S3
        local metadata=$(aws s3api head-object --bucket "$BUCKET" --key "$item" --query 'LastModified' --output text $PARAMS 2>/dev/null || echo "")
        
        if [ -z "$metadata" ]; then
            log "Aviso: não foi possível obter metadados para: $item"
            continue
        fi
        
        # Converte a data do objeto para timestamp
        local object_date=$(echo "$metadata" | cut -c1-10)
        local object_timestamp=$(date -d "$object_date" '+%s' 2>/dev/null || echo "0")
        
        # Extrai cliente para contexto
        local client_context=$(get_client_prefix "$item")
        
        # Aplica políticas de retenção existentes (inalteradas)
        if [ "$object_timestamp" -ne "0" ] && ! should_keep_file "$object_date" "$object_timestamp" "$item" "$client_context"; then
            log "Objeto expirado encontrado: $item (data: $object_date)"
            expired_count=$((expired_count + 1))
            
            # Remove o objeto
            execute_or_simulate "aws s3 rm \"s3://$BUCKET/$item\" $PARAMS"
        fi
    done < "$tmp_enriched"
    
    # Resultado final
    if [ $expired_count -gt 0 ]; then
        log "Removidos $expired_count objetos expirados de $dir_prefix"
        
        # Verifica se o diretório ficou vazio após remoção
        remaining_objects=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$dir_prefix" --max-items 1 --query 'Contents[0].Key' --output text $PARAMS 2>/dev/null)
        
        if [ "$remaining_objects" = "None" ] || [ -z "$remaining_objects" ]; then
            log "Diretório vazio detectado: $dir_prefix - removendo"
            execute_or_simulate "aws s3 rm \"s3://$BUCKET/$dir_prefix\" $PARAMS 2>/dev/null || true"
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

# Limpa diretório temporário de contadores
rm -rf "$COUNTERS_DIR" 2>/dev/null || true

log "=== Garbage collection finalizado ==="
