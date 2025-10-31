# Feature: Pré-checagem de Versões Únicas (Single Version Precheck)

## Resumo

Esta feature adiciona uma regra inteligente ao garbage collector que **preserva automaticamente backups únicos** (sem histórico de versões anteriores), aplicando as políticas de retenção apenas quando há múltiplas versões do mesmo item.

## Motivação

O problema original: quando um backup tem apenas uma versão (sem histórico), não faz sentido aplicar políticas de retenção agressivas, pois não há "versões antigas" para remover. A nova regra garante que:

1. **Backups singletons são preservados** - Se só existe uma versão de um backup (ex: `app_2025-10-30.tgz`), ele não será removido
2. **Apenas séries com histórico são processadas** - Políticas de retenção são aplicadas apenas quando há 2+ versões (ex: `app_2025-10-29.tgz` e `app_2025-10-30.tgz`)
3. **Regra especial para pastas timestamp** - Se houver apenas 1 subpasta com nome de data/hora, os arquivos do nível raiz são ignorados

## Como Funciona

### 1. Detecção de Padrões Timestamp

A função `gc_is_timestamp_name()` detecta se um nome de arquivo/diretório é puramente um timestamp:

**Padrões suportados:**
- `YYYY-MM-DD` (ex: `2025-10-30`)
- `YYYY-MM-DD-HHMM` (ex: `2025-10-30-1430`)
- `YYYY_MM_DD_HHMM` (ex: `2025_10_30_1430`)
- `YYYYMMDD` (ex: `20251030`)
- `YYYYMMDDHHMM` (ex: `202510301430`)
- Epoch timestamps de 10 ou 13 dígitos

### 2. Extração de Prefixos

A função `gc_extract_prefix()` extrai o "nome base" antes do timestamp:

**Exemplos:**
- `a_2025-10-29-1400.tgz` → prefixo: `a`
- `backup-2025-10-30.sql` → prefixo: `backup`
- `2025-10-30-1400/` (diretório timestamp) → prefixo: `__TS_DIR__` (chave sintética)
- `2025-10-30.tar.gz` (arquivo só timestamp) → prefixo: `__TS_FILE__` (chave sintética)

### 3. Agrupamento por Prefixo

No início do processamento de cada diretório, o script:

1. **Lista todos os itens** (arquivos e subdiretórios)
2. **Extrai o prefixo** de cada item
3. **Conta quantas versões** existem por prefixo
4. **Classifica cada item:**
   - ✅ **Processar:** se o prefixo tem 2+ versões
   - ⏭️ **Pular:** se o prefixo tem apenas 1 versão

### 4. Regras Aplicadas

#### Regra 1: Pular Diretório Inteiro
Se **todos** os prefixos têm apenas 1 versão → o diretório inteiro é pulado.

**Exemplo:**
```
site1/app-backups/
├── a_2025-10-30-1400.tgz  ← única versão de "a"
└── b_2025-10-30-1400.tgz  ← única versão de "b"
```
**Resultado:** Diretório ignorado, todos os arquivos são preservados.

#### Regra 2: Processar Apenas Múltiplas Versões
Processa apenas itens cujo prefixo tem 2+ versões.

**Exemplo:**
```
site1/app-backups/
├── a_2025-10-29-1400.tgz  ← versão 1 de "a"
├── a_2025-10-30-1400.tgz  ← versão 2 de "a" (2+ versões)
└── b_2025-10-30-1400.tgz  ← única versão de "b"
```
**Resultado:**
- ✅ Processar série "a" (aplicar políticas de retenção)
- ⏭️ Pular "b" (preservar)

#### Regra 3: Pasta Raiz com Única Subpasta Timestamp
Se houver **exatamente 1 subpasta** cujo nome é puramente timestamp → arquivos do nível raiz são ignorados.

**Exemplo:**
```
site1/app-backups/
├── 2025-10-30-1400/     ← única subpasta timestamp
├── readme.txt           ← arquivo do nível raiz
└── config.yml           ← arquivo do nível raiz
```
**Resultado:**
- ⏭️ `readme.txt` e `config.yml` são ignorados (regra da pasta raiz)
- ⏭️ A subpasta também é ignorada (versão única de `__TS_DIR__`)

**Mas se houver 2+ subpastas timestamp:**
```
site1/app-backups/
├── 2025-10-29-1400/     ← subpasta timestamp 1
├── 2025-10-30-1400/     ← subpasta timestamp 2
└── readme.txt           ← arquivo do nível raiz
```
**Resultado:**
- ✅ Ambas as subpastas são processadas (2+ versões de `__TS_DIR__`)
- ✅ `readme.txt` também pode ser processado (não há apenas 1 subpasta)

## Cenários de Teste

### Cenário 1: Duas Pastas Timestamp ✅
```
site1/app-backups/2025-10-29-1400/
site1/app-backups/2025-10-30-1400/
```
**Esperado:** Processar normalmente (2 versões de `__TS_DIR__`)

### Cenário 2: Uma Única Pasta Timestamp ⏭️
```
site1/app-backups/2025-10-30-1400/
```
**Esperado:** Pular diretório inteiro (versão única)

### Cenário 3: Arquivos Versionados e Singleton 📊
```
site1/app-backups/a_2025-10-29-1400.tgz
site1/app-backups/a_2025-10-30-1400.tgz
site1/app-backups/b_2025-10-30-1400.tgz
```
**Esperado:**
- ✅ Processar série "a" (2 versões)
- ⏭️ Pular "b" (1 versão)

### Cenário 4: Todas as Séries com Versão Única ⏭️
```
site1/app-backups/a_2025-10-30-1400.tgz
site1/app-backups/b_2025-10-30-1400.tgz
```
**Esperado:** Pular diretório inteiro (todos têm 1 versão)

### Cenário 5: Regra da Pasta Raiz ⏭️
```
site1/app-backups/2025-10-30-1400/  ← única subpasta timestamp
site1/app-backups/file1.txt         ← arquivo do nível raiz
site1/app-backups/file2.txt         ← arquivo do nível raiz
```
**Esperado:**
- ⏭️ Todos os arquivos do nível raiz são ignorados
- ⏭️ A subpasta também é ignorada (versão única)

## Logs Esperados

Com `VERBOSE=true`, você verá mensagens como:

```
Pré-processando itens para análise de versões...
Pré-checagem de versões: 3 grupos, 1 com 1 versão, 2 com 2+ versões, ts_dirs=0
Regra de versão única: pulando 'b_2025-10-30-1400.tgz' (prefixo 'b') pois só há 1 versão
Objeto expirado encontrado: site1/app-backups/a_2025-10-29-1400.tgz (data: 2025-10-29)
```

Ou, quando todos têm versão única:

```
Pré-checagem de versões: 2 grupos, 2 com 1 versão, 0 com 2+ versões, ts_dirs=0
Todos os prefixos têm 1 versão neste diretório. Pulando processamento (preservando tudo).
```

Regra da pasta raiz:

```
Pré-checagem de versões: 1 grupos, 1 com 1 versão, 0 com 2+ versões, ts_dirs=1
Regra raiz: há exatamente 1 subpasta de versão. Arquivos do nível atual serão ignorados.
Todos os prefixos têm 1 versão neste diretório. Pulando processamento (preservando tudo).
```

## Compatibilidade

✅ **Totalmente compatível** com:
- Todas as políticas de retenção existentes (`RETENTION_YEARLY`, `RETENTION_MONTHLY`, `RETENTION_WEEKLY`, `RETENTION_DAILY`)
- Modo de compatibilidade (`BACKUP_RETENTION_DAYS`)
- Modo dry-run (`DRY_RUN=true`)
- Logging verboso (`VERBOSE=true`)

⚠️ **Importante:** A nova regra é aplicada **ANTES** das políticas de retenção, apenas filtrando quais itens serão processados. As políticas existentes permanecem inalteradas.

## Testes com DRY_RUN

Para testar sem fazer alterações reais:

```bash
docker run --rm \
  -e DRY_RUN=true \
  -e VERBOSE=true \
  -e KEY=your_key \
  -e SECRET=your_secret \
  -e REGION=us-east-1 \
  -e BUCKET=my-bucket \
  ghcr.io/marcelofmatos/aws-s3-collector-garbage:feat-single-version-precheck gc
```

Você verá todos os logs e decisões, mas nenhum arquivo será removido.

## Implementação Técnica

### Funções Adicionadas

1. **`gc_is_timestamp_name()`**
   - Detecta se um nome é puramente um timestamp
   - Suporta múltiplos formatos de data/hora
   - Retorna 0 (verdadeiro) ou 1 (falso)

2. **`gc_extract_prefix()`**
   - Extrai o prefixo antes do timestamp
   - Usa chaves sintéticas para itens sem prefixo real
   - Fallback seguro para o nome completo

### Modificações em `process_leaf_directory()`

A função foi reescrita para incluir 6 fases:

1. **Fase 1:** Mapear todos os itens (arquivos + subdiretórios)
2. **Fase 2:** Contar itens por prefixo
3. **Fase 3:** Enriquecer mapa com contagens
4. **Fase 4:** Extrair itens com versão única
5. **Fase 5:** Análise e aplicação de regras especiais
6. **Fase 6:** Processar itens (com filtros aplicados)

### Arquivos Temporários

O script cria arquivos temporários seguros:
- `tmp_map`: mapeamento item→tipo→base→prefixo
- `tmp_grp_counts`: contagem por prefixo
- `tmp_enriched`: mapa enriquecido com contagens
- `tmp_skip_single`: lista de itens a pular

Todos são limpos automaticamente via `trap`.

## Desativação (Futura)

Para facilitar rollback futuro, pode-se adicionar uma variável de feature-flag:

```bash
ENABLE_SINGLE_VERSION_PRERULE=false  # desabilita a nova regra
```

(Não implementado na versão atual, mas pode ser adicionado facilmente)

## Autor

Implementado por Marcelo Matos em 2025-10-31
Branch: `feat/single-version-precheck`
