# ADR-0001 — Repositórios e limites de serviços

Data: 2026-09-19.
Estado: ACEITO para repositórios independentes e quatro limites de serviços, conforme respostas de 2026-09-20. Contratos e implantação ainda em definição.

O desafio pede microsserviços, mensageria, concorrência e persistência. Monorepo e monólito modular foram descartados por escolha do responsável. O enunciado não exige organização específica de repositórios.

Cada serviço terá código, build, testes, migrations, imagem e pipeline próprios, sem POM agregador ou dependência de checkout dos demais para compilar. fiapx-infra mantém documentação geral e Terraform. fiapx-video-service é o repositório do domínio de vídeos, reaproveitado da estrutura inicial.

Definidos serviços de identidade própria com JWT, vídeos, processamento e notificações independentes. Cada um possui seus dados, sem consultas cruzadas de tabelas ou compartilhamento de entidades JPA. Detalhes em [arquitetura](../architecture.md).

A separação permite escalar processamento independentemente e publicar serviços separadamente, mas aumenta contratos e operação. Notificações serão persistidas e exibidas na interface; identidade oferece cadastro e login com JWT. Os quatro serviços executarão em Pods Kubernetes na AWS; Amazon EKS confirmado. A proposta anterior de monorepo com API e worker foi substituída; não há implementação a migrar.
