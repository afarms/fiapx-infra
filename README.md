# FIAP X — Infraestrutura e arquitetura integrada

Repositório de Terraform e documentação da integração entre os serviços FIAP X. Região da aplicação e do backend: Norte da Virgínia (`us-east-1`).

## Estado atual

- Identidade: cadastro, login JWT, perfil, credenciais e administração de usuários implementados. Exclusão distribuída pendente.
- Vídeos: consultas autenticadas, upload durável/outbox, resultados, download e limpeza assíncrona implementados e integrados.
- Processamento: worker/FFmpeg, concorrência e recuperação implementados. Validação integrada na cloud pendente.
- Infraestrutura: OIDC, backend S3/lock, bucket privado de mídia e workflow único de validação, plan e apply automático no PR verificados na AWS.
- Filas de processamento/resultados, DLQs, roles locais e permissões de resultados/limpeza provisionadas pelo pipeline. Isso não comprova execução integrada das aplicações na AWS. Ver [guia de resultados](docs/operations/processing-results.md).
- EKS privado com dois nós Spot e administração SSM provisionados e validados. RDS privado, secret único e bootstrap dos três bancos implementados localmente; provisionamento pendente. Ver [banco privado](docs/operations/private-database.md). Demais filas e frontend permanecem pendentes.
- Rede em duas AZs, NAT e três ECR privados provisionados com apply e drift verificados; ver [rede/ECR](docs/operations/cloud-network-registry.md).
- Prioridade: rede/ECR → EKS/RDS/configuração → deploy e fluxo principal → validação cloud. Notificação mínima de erro por e-mail fica ao final, via SQS/Lambda/SES, conforme [ADR-0002](docs/architecture/adr/0002-email-notifications-cloud-first.md).

O bucket de estado existente `fiap-fase-05`, no prefixo `fiapx-infra/tfstate/`, foi criado previamente e não é gerenciado nem destruído por esta configuração. O bucket de mídia é separado do estado. Ambos operam sem novas versões; o pipeline não exige versionamento. O plano permanece somente no runner durante a execução.

## Validar e executar

Com Terraform 1.14.7, GNU Make e Python instalados, instalar as dependências de `scripts/database/requirements.txt` em um venv e executar na raiz:

```bash
make verify
```

Executa formatação, inicialização sem backend, validação, guard de revisão e teste de preservação do secret, sem credenciais AWS. Não há testes Terraform com provider mock. O primeiro uso baixa o provider fixado no lock file. `make verify-database` valida o bootstrap em PostgreSQL real com Docker; detalhes e parâmetro `PYTHON` no [runbook](docs/operations/private-database.md).

O workflow **Terraform** executa automaticamente nos PRs para `main`: validação → autenticação OIDC → init → plan salvo → apply → verificação final. O check obrigatório `terraform-validate` só passa se todas as etapas passarem. Deploy permitido apenas em PR próprio do proprietário, no mesmo repositório. Apply ocorre antes do merge; fechar o PR não reverte recursos já alterados.

Configuração GitHub: `AWS_ROLE_ARN` em **Repository Secrets** para mascaramento nos logs e `AWS_REGION=us-east-1` em **Repository Variables**. O ID da conta é derivado do ARN; não há access keys permanentes no workflow. Estado, planos, credenciais e arquivos locais não devem ser versionados.

Configure também `MEDIA_BUCKET_NAME`, a política IAM adicional e a confiança OIDC de PR conforme o [guia único de operação](docs/operations/delivery.md). Não há escolha manual de plan/apply nem execução duplicada após o merge.

## Documentação

- [Estrutura Terraform](terraform/README.md).
- [RDS privado, bootstrap e DBeaver](docs/operations/private-database.md).
- [Rede/ECR e permissões de provisionamento](docs/operations/cloud-network-registry.md).

- [Arquitetura integrada](docs/architecture/consolidated.md).
- [Diagramas Mermaid](docs/architecture/diagrams.md).
- [Contratos e topologia das filas](docs/architecture/integration.md).
- [Visão geral](docs/architecture/architecture.md).
- [Serviços e repositórios](docs/services/README.md).
- [Requisitos e situação da entrega](docs/requirements/requirements.md).
- [Stack e versões](docs/development/stack.md).
- [Operação e entrega](docs/operations/delivery.md).

Os diagramas descrevem a arquitetura alvo; sua presença não indica que os recursos já estão implantados. Cada serviço possui build e repositório próprios, e as migrations pertencem aos respectivos serviços.
