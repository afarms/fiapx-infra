# FIAP X — Infraestrutura e arquitetura integrada

Repositório de Terraform e documentação da integração entre os serviços FIAP X. Região da aplicação e do backend: Norte da Virgínia (`us-east-1`).

## Estado atual

- Identidade: cadastro, login JWT, perfil, credenciais e administração de usuários implementados. Exclusão distribuída pendente.
- Vídeos: persistência e consultas autenticadas por proprietário implementadas. Upload, processamento e download pendentes.
- Infraestrutura: backend Terraform S3 configurado, CI de validação e workflows manuais de autenticação OIDC e teste do backend disponíveis. A autenticação OIDC foi executada com sucesso; execução real do backend ainda pendente.
- EKS, RDS, mensageria, bucket de mídia e frontend fazem parte da arquitetura planejada e ainda não foram provisionados por este projeto.

O bucket de estado existente `fiap-fase-05`, no prefixo `fiapx-infra/tfstate/`, foi criado previamente e não é gerenciado nem destruído por esta configuração. Não há recursos de aplicação na raiz Terraform atual. O bucket de mídia será separado do estado.

## Validar e executar

Com Terraform 1.14.7 e GNU Make instalados, executar na raiz:

```bash
make verify
```

Executa formatação em modo de verificação, inicialização sem backend e validação, sem credenciais AWS. O mesmo comando roda no check `terraform-validate` em PRs para `main` e pushes na `main`.

Os workflows com acesso AWS são manuais e restritos à `main`:

- [Autenticação OIDC](docs/operations/aws-oidc.md): consulta a identidade assumida, sem acessar o estado.
- [Backend Terraform](docs/operations/terraform-backend.md): inicialização e plan com lock S3; pode criar estado vazio e arquivo temporário de lock. Não executa apply.

Configuração GitHub: `AWS_ROLE_ARN` em **Repository Secrets** para mascaramento nos logs e `AWS_REGION=us-east-1` em **Repository Variables**. O ID da conta é derivado do ARN; não há access keys permanentes no workflow. Estado, planos, credenciais e arquivos locais não devem ser versionados.

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
