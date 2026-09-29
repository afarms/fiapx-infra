# Arquitetura FIAP X

Três microsserviços independentes em Amazon EKS: identidade, vídeos e processamento. A notificação mínima de erro será feita por Lambda + SES, acionada por SQS. Identidade, upload, processamento, consultas, download e limpeza estão implementados; implantação EKS concluída; acesso público, validação integrada na cloud e notificações permanecem pendentes. Prioridade: executar o fluxo principal na AWS antes de implementar e-mail.

- [Visão integrada e infraestrutura](consolidated.md).
- [Diagramas Mermaid](diagrams.md).
- [Contratos e filas](integration.md).
- [Decisão de limites](adr/0001-service-boundaries.md).
- [E-mail mínimo e prioridade cloud](adr/0002-email-notifications-cloud-first.md).
- [Operação e entrega](../operations/delivery.md).

O serviço de vídeos mantém o estado público do trabalho; processamento executa FFmpeg; identidade controla usuários e permissões atuais. Cada serviço no EKS possui seu banco lógico e contrato, sem acesso cruzado a tabelas. A Lambda envia e-mail de erro ao dono, sem banco de avisos e sem API pública.

No fluxo planejado, persistência transacional com outbox e consumo idempotente sustentarão a recuperação após aceite. A exclusão de conta bloqueia novas chamadas e coordena remoção definitiva dos dados dos serviços. Falhas de limpeza permanecem pendentes até confirmação.

A infraestrutura planejada usa RDS privado, SQS com DLQs, S3, CloudFront e um único secret no Secrets Manager. Backend, OIDC, mídia e filas de trabalho/resultados já possuem provisionamento registrado. O workflow aplica automaticamente no PR; as três aplicações já foram implantadas no EKS. Parâmetros pendentes estão na visão integrada.
