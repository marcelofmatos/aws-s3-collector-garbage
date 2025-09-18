---
name: Bug Report
about: Relatar um problema com o AWS S3 Garbage Collector
title: '[BUG] '
labels: 'bug'
assignees: 'marcelofmatos'

---

## 🐛 Descrição do Bug
Uma descrição clara e concisa do problema.

## 🔄 Para Reproduzir
Passos para reproduzir o comportamento:
1. Execute o comando '...'
2. Configure as variáveis de ambiente '...'
3. Veja o erro

## ✅ Comportamento Esperado
Uma descrição clara e concisa do que você esperava que acontecesse.

## 🖥️ Ambiente
- **Versão da Imagem**: (ex: `ghcr.io/marcelofmatos/aws-s3-collector-garbage:latest`)
- **Plataforma**: (ex: linux/amd64, linux/arm64)
- **Modo de Execução**: (ex: Docker, Docker Compose, Kubernetes)
- **AWS Region**: (ex: us-east-1)

## 📋 Variáveis de Ambiente
```bash
# Remova dados sensíveis como KEY e SECRET
REGION=us-east-1
BUCKET=my-bucket
BUCKET_PATH=/backups
BACKUP_RETENTION_DAYS=7
DRY_RUN=false
VERBOSE=true
```

## 📄 Logs
```
Cole aqui os logs relevantes
```

## 📸 Screenshots (se aplicável)
Se aplicável, adicione screenshots para ajudar a explicar seu problema.

## 🔗 Contexto Adicional
Adicione qualquer outro contexto sobre o problema aqui.