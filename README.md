# AWS S3 Garbage Collector

![CI](https://github.com/marcelofmatos/aws-s3-collector-garbage/workflows/CI%20-%20Build%20and%20Test/badge.svg)
![Release](https://github.com/marcelofmatos/aws-s3-collector-garbage/workflows/Release%20-%20Build%20and%20Publish/badge.svg)
![Main](https://github.com/marcelofmatos/aws-s3-collector-garbage/workflows/Main%20-%20Build%20and%20Publish%20Latest/badge.svg)
[![Docker](https://ghcr-badge.egpl.dev/marcelofmatos/aws-s3-collector-garbage/latest_tag?trim=major&label=latest)](https://github.com/marcelofmatos/aws-s3-collector-garbage/pkgs/container/aws-s3-collector-garbage)
[![License](https://img.shields.io/github/license/marcelofmatos/aws-s3-collector-garbage)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/marcelofmatos/aws-s3-collector-garbage)](https://github.com/marcelofmatos/aws-s3-collector-garbage/releases)

Um container Docker baseado na imagem [futurevision/aws-s3-sync](https://hub.docker.com/r/futurevision/aws-s3-sync) que adiciona funcionalidade de garbage collection para limpar automaticamente backups antigos no Amazon S3.

## 📋 Funcionalidades

- ✅ **Mantém compatibilidade** com a imagem original `futurevision/aws-s3-sync`
- 🗑️ **Garbage Collection** automática de arquivos antigos no S3
- 📂 **Remove diretórios vazios** após a limpeza
- ⏰ **Execução agendada** via cron
- 🔍 **Modo dry-run** para simular operações
- 📊 **Log verboso** para monitoramento
- 🎯 **Foco no segundo nível** de diretórios conforme especificado

## 🏗️ Estrutura do Projeto

```
aws-s3-collector-garbage/
├── Dockerfile
├── README.md
├── build.sh                      # Script de build facilitado
├── scripts/
│   ├── garbage-collector.sh    # Script principal de limpeza
│   └── start.sh               # Script de inicialização estendido
├── examples/
│   ├── docker-compose-one-shot.yml  # Execução única
│   ├── docker-compose-cron.yml      # Execução periódica
│   └── .env.example                  # Exemplo de variáveis
└── .github/
    ├── workflows/              # GitHub Actions
    ├── ISSUE_TEMPLATE/         # Templates para issues
    └── pull_request_template.md # Template para PRs
```

## 🚀 Como Usar

### 1. Pull da Imagem Pré-construída (Recomendado)

```bash
# Pull da imagem do GitHub Container Registry
docker pull ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest

# Alias para uso mais fácil
docker tag ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest aws-s3-gc

# Teste a imagem
docker run --rm aws-s3-gc help
```

### 2. Build Local (Alternativo)

```bash
# Clone o repositório
git clone https://github.com/marcelofmatos/aws-s3-collector-garbage.git
cd aws-s3-collector-garbage

# Build da imagem usando o script facilitado
./build.sh

# Ou build manual
docker build -t aws-s3-gc .
```

### 3. Variáveis de Ambiente

| Variável | Obrigatório | Padrão | Descrição |
|----------|-------------|--------|-----------|
| `KEY` | ✅ | - | AWS Access Key ID |
| `SECRET` | ✅ | - | AWS Secret Access Key |
| `REGION` | ✅ | - | AWS Region (ex: us-east-1) |
| `BUCKET` | ✅ | - | Nome do bucket S3 |
| `BUCKET_PATH` | ❌ | `/` | Caminho dentro do bucket |
| `BACKUP_RETENTION_DAYS` | ❌ | `7` | Dias de retenção dos backups |
| `CRON_SCHEDULE` | ❌ | - | Agenda cron (ex: "0 3 * * *") |
| `DRY_RUN` | ❌ | `false` | Modo simulação (true/false) |
| `VERBOSE` | ❌ | `true` | Log detalhado (true/false) |

### 4. Modos de Execução

#### 🔧 Sincronização (Compatibilidade)
```bash
# Mantém a funcionalidade original da imagem base
docker run --rm \
  -e KEY=your_key \
  -e SECRET=your_secret \
  -e REGION=us-east-1 \
  -e BUCKET=my-bucket \
  -v /local/data:/data \
  ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest sync
```

#### 🗑️ Garbage Collection - Execução Única
```bash
# Remove backups com mais de 7 dias
docker run --rm \
  -e KEY=your_key \
  -e SECRET=your_secret \
  -e REGION=us-east-1 \
  -e BUCKET=my-backup-bucket \
  -e BUCKET_PATH=/backups \
  -e BACKUP_RETENTION_DAYS=7 \
  ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest gc
```

#### 🕐 Garbage Collection - Modo Dry-Run
```bash
# Simula a operação sem executar
docker run --rm \
  -e KEY=your_key \
  -e SECRET=your_secret \
  -e REGION=us-east-1 \
  -e BUCKET=my-backup-bucket \
  -e DRY_RUN=true \
  ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest gc
```

#### ⏰ Garbage Collection - Execução Agendada
```bash
# Executa todos os dias às 3h da manhã
docker run -d \
  -e KEY=your_key \
  -e SECRET=your_secret \
  -e REGION=us-east-1 \
  -e BUCKET=my-backup-bucket \
  -e CRON_SCHEDULE="0 3 * * *" \
  --name s3-gc \
  ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest gc
```

### 5. Docker Compose

#### Execução Única
```bash
cd examples/
cp .env.example .env
# Edite o arquivo .env com suas credenciais
docker-compose -f docker-compose-one-shot.yml up
```

#### Execução Periódica (Cron)
```bash
cd examples/
cp .env.example .env
# Edite o arquivo .env com suas credenciais
docker-compose -f docker-compose-cron.yml up -d
```

## 🚀 CI/CD e Container Registry

Este projeto utiliza GitHub Actions para automatizar o build e publicação das imagens Docker.

### 📏 Workflows Disponíveis

| Workflow | Trigger | Finalidade |
|----------|---------|------------|
| **CI** | Push/PR | Build e teste da imagem |
| **Main** | Push para main | Publica imagem `latest` |
| **Release** | Tags/Releases | Publica versões tagged |

### 📦 GitHub Container Registry

As imagens são publicadas automaticamente no GitHub Container Registry:

```bash
# Imagens disponíveis:
ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest  # Última versão
ghcr.io/marcelofmatos/aws-s3-collector-garbage:main    # Branch main
ghcr.io/marcelofmatos/aws-s3-collector-garbage:v1.0.0  # Versões específicas
```

### ⚙️ Plataformas Suportadas

- **linux/amd64** - Arquitetura Intel/AMD 64-bit
- **linux/arm64** - Arquitetura ARM 64-bit (em desenvolvimento)

### 🔒 Segurança

- Scan automático de vulnerabilidades com Trivy
- Imagens assinadas e verificadas
- Build reproduzível com cache otimizado

## 🎅 Como Funciona o Garbage Collection

O script de garbage collection opera especificamente no **segundo nível de diretórios** conforme solicitado:

1. **Listagem**: Navega pela estrutura `BUCKET_PATH/*/*/` (segundo nível)
2. **Análise**: Para cada arquivo, compara `LastModified` com `BACKUP_RETENTION_DAYS`
3. **Remoção**: Remove arquivos mais antigos que o período de retenção
4. **Limpeza**: Remove diretórios que ficaram vazios após a remoção dos arquivos

### Exemplo de Estrutura S3:
```
my-bucket/
├── backups/
│   ├── app1/
│   │   ├── 2024-01-01/    ← Este nível é processado
│   │   ├── 2024-01-02/    ← Este nível é processado
│   │   └── 2024-01-15/    ← Este nível é processado
│   └── app2/
│       ├── 2024-01-01/    ← Este nível é processado
│       └── 2024-01-10/    ← Este nível é processado
```

## 📊 Logs e Monitoramento

### Logs Típicos do Garbage Collection:
```
2024-01-15 03:00:01 - === AWS S3 Garbage Collector iniciado ===
2024-01-15 03:00:01 - Bucket: s3://my-backup-bucket
2024-01-15 03:00:01 - Path: backups
2024-01-15 03:00:01 - Retenção: 7 dias
2024-01-15 03:00:01 - Data de corte: 2024-01-08
2024-01-15 03:00:02 - Processando primeiro nível: backups/app1/
2024-01-15 03:00:02 - Processando diretório: backups/app1/2024-01-01/
2024-01-15 03:00:02 - Objeto expirado encontrado: backups/app1/2024-01-01/backup.tar.gz
2024-01-15 03:00:03 - Executando: aws s3 rm s3://my-backup-bucket/backups/app1/2024-01-01/backup.tar.gz
2024-01-15 03:00:03 - Diretório vazio detectado: backups/app1/2024-01-01/ - removendo
2024-01-15 03:00:04 - === Garbage collection finalizado ===
```

### Monitoramento via Docker Logs:
```bash
# Container em execução única
docker logs container_name

# Container com cron
docker logs -f container_name
```

## 🛠️ Comandos Disponíveis

| Comando | Descrição |
|---------|-----------|
| `sync` | Modo sincronização (padrão original) |
| `gc` ou `garbage-collect` | Executa garbage collection |
| `help` | Exibe ajuda completa |
| `now` | Compatibilidade: sync imediato |

## ⚠️ Considerações Importantes

1. **Backup dos dados**: Sempre teste com `DRY_RUN=true` antes da execução real
2. **Permissões AWS**: Certifique-se que as credenciais têm permissão para `s3:DeleteObject` e `s3:ListBucket`
3. **Timezone**: O container usa UTC. Ajuste o `CRON_SCHEDULE` conforme necessário
4. **Custos AWS**: Operações de listagem e deleção podem gerar custos dependendo do volume

## 🔧 Troubleshooting

### Problema: "Access Denied"
- Verifique se as credenciais AWS estão corretas
- Confirme se a IAM policy inclui as permissões necessárias:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        "Resource": [
          "arn:aws:s3:::your-bucket-name",
          "arn:aws:s3:::your-bucket-name/*"
        ]
      }
    ]
  }
  ```

### Problema: Cron não executa
- Verifique se a variável `CRON_SCHEDULE` está definida
- Confirme a sintaxe do cron (use [crontab.guru](https://crontab.guru/) para testar)
- Lembre-se que o container usa timezone UTC

### Problema: Script não encontra arquivos
- Verifique se `BUCKET_PATH` está correto (sem barra inicial)
- Confirme se existem arquivos na estrutura de segundo nível esperada
- Use `DRY_RUN=true` e `VERBOSE=true` para debug

## 📄 Licença

Este projeto mantém compatibilidade com a imagem base `futurevision/aws-s3-sync` e adiciona funcionalidades de garbage collection.

## 🤝 Contribuições

Contribuições são bem-vindas! Sinta-se à vontade para:
- Reportar bugs usando os [templates de issue](https://github.com/marcelofmatos/aws-s3-collector-garbage/issues/new/choose)
- Sugerir melhorias
- Enviar pull requests seguindo o [template de PR](https://github.com/marcelofmatos/aws-s3-collector-garbage/compare)

---

**Desenvolvido por [Marcelo Matos](https://github.com/marcelofmatos)** - Baseado na imagem `futurevision/aws-s3-sync`