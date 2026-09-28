# Arquitetura FIAP X

Quatro microsserviços independentes em Amazon EKS: identidade, vídeos, processamento e notificações. A documentação descreve a arquitetura alvo. Identidade e consultas autenticadas de vídeos estão implementadas; processamento, notificações e implantação EKS permanecem planejados.

- [Visão integrada e infraestrutura](consolidated.md).
- [Diagramas Mermaid](diagrams.md).
- [Contratos e filas](integration.md).
- [Decisão de limites](adr/0001-service-boundaries.md).
- [Operação e entrega](../operations/delivery.md).

O serviço de vídeos mantém o estado público do trabalho; processamento executa FFmpeg; identidade controla usuários e permissões atuais; notificações mantém avisos do dono. Cada serviço possui seu banco lógico e contrato, sem acesso cruzado a tabelas.

No fluxo planejado, persistência transacional com outbox e consumo idempotente sustentarão a recuperação após aceite. A exclusão de conta bloqueia novas chamadas e coordena remoção definitiva dos dados dos serviços. Falhas de limpeza permanecem pendentes até confirmação.

A infraestrutura planejada usa RDS privado, SQS com DLQs, S3, CloudFront e um único secret no Secrets Manager. Este repositório possui backend Terraform em bucket S3 preexistente, OIDC e lock verificados. Mídia está definida em Terraform e o workflow único aplica automaticamente no PR, com execução completa ainda pendente. Parâmetros de implantação pendentes estão na visão integrada.
