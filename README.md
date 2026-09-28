# FIAP X — Infraestrutura e arquitetura integrada

Repositório de Terraform e documentação da integração entre os serviços FIAP X. Região da aplicação e do backend: Norte da Virgínia (`us-east-1`).

## Estado atual

- Identidade: cadastro, login JWT, perfil, credenciais e administração de usuários implementados. Exclusão distribuída pendente.
- Vídeos: persistência, consultas autenticadas e upload com aceite durável/outbox implementados. Processamento e download pendentes.
- Infraestrutura: OIDC, backend S3/lock, bucket privado de mídia e workflow único de validação, plan e apply automático no PR verificados na AWS.
- Fila de processamento Standard, DLQ e role local do produtor provisionadas. Fila de resultados/DLQ, role local do worker e permissões de consumo de resultados preparadas e testadas localmente; implantação pendente. Ver [guia de resultados](docs/operations/processing-results.md).
- EKS, RDS, demais filas e frontend fazem parte da arquitetura planejada e ainda não foram provisionados por este projeto.

O bucket de estado existente `fiap-fase-05`, no prefixo `fiapx-infra/tfstate/`, foi criado previamente e não é gerenciado nem destruído por esta configuração. O bucket de mídia é separado do estado. Ambos operam sem novas versões; o pipeline não exige versionamento. O plano permanece somente no runner durante a execução.

## Validar e executar

Com Terraform 1.14.7 e GNU Make instalados, executar na raiz:

```bash
make verify
```

Executa formatação em modo de verificação, inicialização sem backend, validação e testes com provider mock, sem credenciais AWS. O primeiro uso baixa o provider AWS fixado no lock file.

O workflow **Terraform** executa automaticamente nos PRs para `main`: validação → autenticação OIDC → init → plan salvo → apply → verificação final. O check obrigatório `terraform-validate` só passa se todas as etapas passarem. Deploy permitido apenas em PR próprio do proprietário, no mesmo repositório. Apply ocorre antes do merge; fechar o PR não reverte recursos já alterados.

Configuração GitHub: `AWS_ROLE_ARN` em **Repository Secrets** para mascaramento nos logs e `AWS_REGION=us-east-1` em **Repository Variables**. O ID da conta é derivado do ARN; não há access keys permanentes no workflow. Estado, planos, credenciais e arquivos locais não devem ser versionados.

Configure também `MEDIA_BUCKET_NAME`, a política IAM adicional e a confiança OIDC de PR conforme o [guia único de operação](docs/operations/delivery.md). Não há escolha manual de plan/apply nem execução duplicada após o merge.

## Documentação

- [Arquitetura integrada](docs/architecture/consolidated.md).
- [Diagramas Mermaid](docs/architecture/diagrams.md).
- [Contratos e topologia das filas](docs/architecture/integration.md).
- [Visão geral](docs/architecture/architecture.md).
- [Serviços e repositórios](docs/services/README.md).
- [Requisitos e situação da entrega](docs/requirements/requirements.md).
- [Stack e versões](docs/development/stack.md).
- [Operação e entrega](docs/operations/delivery.md).

Os diagramas descrevem a arquitetura alvo; sua presença não indica que os recursos já estão implantados. Cada serviço possui build e repositório próprios, e as migrations pertencem aos respectivos serviços.
