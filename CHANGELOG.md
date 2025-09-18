# Changelog

Todos os mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.1.0] - 2024-09-18

### Adicionado
- ✨ **Variável PARAMS**: Suporte completo à variável `PARAMS` para compatibilidade total com a imagem original
- 🔧 **Parâmetros AWS CLI**: Todos os comandos AWS CLI agora suportam parâmetros adicionais via `PARAMS`
- 📚 **Documentação expandida**: Seção detalhada no README com exemplos de uso de `PARAMS`
- 🐳 **GitHub Actions**: Sistema completo de CI/CD com build automático e publicação no GHCR
- 🧪 **Workflow experimental**: Teste ARM64 separado para validação de compatibilidade
- 📋 **Templates**: Templates para issues e pull requests
- 🛡️ **Segurança**: Scan automático de vulnerabilidades com Trivy

### Alterado
- 🔧 **Multi-plataforma**: Temporariamente limitado a AMD64 até validação completa do ARM64
- 📦 **Build otimizado**: Comandos RUN separados para melhor compatibilidade

### Exemplos de PARAMS
- `--profile production` - Usar profile específico do AWS
- `--endpoint-url https://s3.custom.com` - Endpoints customizados (S3-compatible storage)
- `--cli-read-timeout 30` - Configurações de timeout
- `--storage-class STANDARD_IA` - Classes de armazenamento específicas

## [1.0.0] - 2024-09-18

### Adicionado
- 🎉 Versão inicial do AWS S3 Garbage Collector
- 🐳 Dockerfile baseado em `futurevision/aws-s3-sync`
- 🗑️ Script de garbage collection para limpeza automática de backups
- 📂 Remoção automática de diretórios vazios após limpeza
- ⏰ Suporte a execução agendada via cron
- 🔍 Modo dry-run para simulação de operações
- 📊 Logs verbosos para monitoramento
- 🎯 Processamento específico do segundo nível de diretórios
- 📋 Exemplos de docker-compose para execução única e periódica
- 🛠️ Script de build facilitado
- 📚 Documentação completa no README.md
- ⚙️ Variável `BACKUP_RETENTION_DAYS` configurável (padrão: 7 dias)
- 🔧 Compatibilidade total com a imagem original
- ✅ Validação de variáveis obrigatórias
- 📝 Arquivo de exemplo `.env.example`

### Funcionalidades
- Limpeza automática de arquivos antigos no S3
- Processamento otimizado por lotes
- Suporte a múltiplas regiões AWS
- Configuração flexível via variáveis de ambiente
- Execução única ou contínua via cron
- Log detalhado de operações realizadas