# Operação e entrega

## Infraestrutura existente e configuração

Região: `us-east-1`. O bucket existente `fiap-fase-05` foi criado previamente pelo responsável. A configuração Terraform usa `fiapx-infra/tfstate/terraform.tfstate`, criptografia solicitada por `encrypt=true` e lock nativo por `use_lockfile=true`. O bucket permanece fora do ciclo de destruição da aplicação. Estado e planos não pertencem ao Git.

O teste OIDC foi executado com sucesso. O workflow de backend está disponível, mas sua execução real ainda não foi confirmada. A role possui permissões limitadas ao backend; políticas para provisionar recursos serão definidas conforme cada incremento. Não foi comprovada a configuração de versionamento, criptografia padrão ou bloqueio público do bucket; conferir no console antes de armazenar estado de recursos reais.

Guias: [autenticação OIDC](aws-oidc.md) e [validação do backend](terraform-backend.md).

## Pipelines atuais

- Identidade e vídeos: testes/cobertura antes do build da imagem; CI executada no GitHub. Imagem multi-stage JDK/JRE; Dockerfile não repete os testes executados pela CI.
- Infraestrutura: `terraform-validate` executa `make verify` sem acesso AWS em PR/main. Manter esse nome como check obrigatório na proteção de main.
- AWS: workflows manuais apenas na main, usando OIDC. `AWS_ROLE_ARN` é Repository Secret para mascaramento e `AWS_REGION` é Variable. Não há chaves permanentes no GitHub.

## Implantação planejada

Terraform provisionará VPC, EKS, node groups, RDS, SQS/DLQs, secret agregado, buckets aprovados, CloudFront, IAM e observabilidade. Esses recursos ainda não foram provisionados por este projeto. O bucket de mídia será separado do backend e do frontend.

Cada serviço terá publicação no ECR e implantação por digest no seu Deployment, com rollout e smoke tests. Definir acesso de rede do runner ao EKS antes do CD. O ALB criado por controller Kubernetes terá ciclo próprio; não gerenciar o mesmo recurso simultaneamente pelo controller e pelo Terraform.

O desenvolvimento local usa Compose e PostgreSQL. Migrations, persistência após reinício e integração HTTP entre identidade/vídeos foram verificadas localmente. FFmpeg, broker, S3 de mídia e implantação EKS continuam pendentes. CI de build não equivale a CD concluído.

## Manutenção e validações restantes

Planejado: DBeaver por túnel SSM com credencial SQL separada, Liquibase com migrations compatíveis, backups e restauração que reapliquem exclusões antes de liberar acesso. Ajustes diretos no banco não disparam eventos/outbox.

Ainda precisam de validação: concorrência de processamento, aceite durável, recuperação de filas/DLQs, isolamento de upload/download, expiração em 24 horas e exclusão definitiva distribuída. Relatórios de testes são artefatos da CI; credenciais e dados pessoais não devem aparecer em logs ou documentação pública.
