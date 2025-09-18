# Changelog

Todos os mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

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