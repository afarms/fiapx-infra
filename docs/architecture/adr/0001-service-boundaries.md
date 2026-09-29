# ADR-0001 — Repositórios e limites de serviços

Data: 2026-09-19.
Estado: ACEITO nos limites abaixo, atualizado pela [ADR-0002](0002-email-notifications-cloud-first.md). A decisão inicial de quarto serviço de avisos foi substituída por Lambda/SES, sem banco de avisos.

O desafio pede microsserviços, mensageria, concorrência e persistência. Monorepo e monólito modular foram descartados por escolha do responsável. O enunciado não exige organização específica de repositórios.

Cada serviço terá código, build, testes, migrations, imagem e pipeline próprios, sem POM agregador ou dependência de checkout dos demais para compilar. fiapx-infra mantém documentação geral e Terraform. fiapx-video-service é o repositório do domínio de vídeos, reaproveitado da estrutura inicial.

Três serviços: identidade própria com JWT, vídeos e processamento. Cada um possui seus dados, sem consultas cruzadas de tabelas ou compartilhamento de entidades JPA. Uma Lambda consome a fila de notificações e envia e-mail pelo SES, sem API ou banco próprio. Detalhes em [arquitetura](../architecture.md).

A separação permite escalar processamento e publicar serviços independentemente. Os três serviços executam em Pods no Amazon EKS. A Lambda de e-mail será implementada ao final do fluxo principal, apenas para falha definitiva; não há histórico de leitura ou avisos de sucesso.
