# Arquitetura integrada

Desenho de referência do sistema. Identidade, upload, processamento, consultas, download e limpeza assíncrona implementados; validação integrada na cloud e implantação EKS ainda pendentes. Os [diagramas Mermaid](diagrams.md) representam o alvo, não comprovam provisionamento. Prioridade: base cloud e fluxo principal; notificação por e-mail ao final, conforme [ADR-0002](adr/0002-email-notifications-cloud-first.md).

## Regras do sistema

Três serviços independentes no AWS/EKS: identidade, vídeos e processamento. Notificação de erro em Lambda + SES, consumindo SQS, sem quarto serviço Java. PostgreSQL no RDS privado, SQS/DLQ, um único secret no Secrets Manager, frontend HTML/JS em S3 + CloudFront. Terraform em projeto separado, backend S3 previamente criado. DBeaver via SSM.

Cadastro público USER, edição própria, administração de usuários restrita a ADMIN, incluindo promoção/inativação/exclusão; proteger último ADMIN. JWT por 30 minutos em memória e novo login após reload. Status/permissões atuais consultados para bloquear novas chamadas imediatamente. Exclusão definitiva com limpeza dos dados associados.

Vídeos: sete formatos da base, até 100 MB decimais e 300 segundos; referência de uma imagem PNG/segundo em ZIP; disponibilidade de 24h após conclusão. Notificação por e-mail somente em falha definitiva, sem histórico de avisos na interface.

## Topologia de referência

| Elemento | Proposta e finalidade |
| --- | --- |
| EKS | Managed node group EC2 Linux Spot com dois nós desejados; API privada via SSM; um Deployment por serviço; worker com duas réplicas na prova de concorrência |
| Rede | VPC em duas AZs; subnets públicas para entrada e privadas para workloads/RDS; saída via NAT inicialmente único, sem alegar alta disponibilidade |
| Entrada | CloudFront para HTML/S3 e comportamento /api/* para ALB com HTTPS; cache desabilitado nas APIs e encaminhamento de Authorization |
| DNS/TLS | Domínio e certificado da origem ALB necessários; disponibilidade de domínio ainda precisa ser informada antes da implementação desta opção |
| Banco | Uma instância RDS PostgreSQL Single-AZ acadêmica; três bancos/usuários de domínio e usuário separado de manutenção; sem banco de avisos |
| Objetos | Bucket privado de mídia definido em Terraform, separado do frontend e do estado; mídia sem versionamento e estado sem exigência de versionamento |
| Filas | SQS Standard; cinco filas funcionais, cada uma com sua DLQ; outbox por destinatário, sem SNS adicional nesta proposta |
| Identidade AWS | Pod Identity por service account para S3/SQS; acesso interno à identidade autenticado por credencial de serviço e restrito pela rede |
| Imagens | ECR por serviço, imagem identificada por digest; versões fixadas após build validado |
| Notificação | SQS → Lambda → SES; retentativas e DLQ; sem endpoint HTTP de notificações; implementação posterior ao fluxo principal |
| Observabilidade | Logs estruturados e métricas CloudWatch; alertas de DLQ, idade de fila, falhas e reinícios |
| Administração | EC2 gerenciada por SSM com acesso privado ao RDS; DBeaver por túnel |

Região da aplicação: Norte da Virgínia (us-east-1). Tamanhos de instância, limites de CPU/memória e retenção de logs serão fixados no dimensionamento. Base mínima adotada: duas AZs e NAT única. Estimativa financeira dispensada pelo responsável para esta demonstração temporária.

## Secret único

Exatamente um recurso no AWS Secrets Manager. JSON agrega dados de conexão com credenciais SQL distintas. Proposta: etapa de implantação restrita lê o secret e cria configurações Kubernetes separadas por serviço, protegidas por RBAC. Essas configurações não criam novos recursos no Secrets Manager. Pods não precisam ler o agregado. Evitar registrar o conteúdo em logs, arquivos de build ou outputs Terraform.

Credencial do admin inicial, chave privada JWT e credenciais internas também precisam armazenamento seguro; proposta de usar campos adicionais no mesmo secret, sem criar outro. Chave privada entregue somente à identidade; os demais serviços recebem a chave pública. Credencial de manutenção não é montada em workloads. Se Terraform gerenciar valores, o state deve ser tratado como sensível; mecanismo exato de preenchimento ainda será validado.

## Caminho do vídeo

Frontend envia upload à API de vídeos; API faz streaming para S3 com limite de bytes. Após upload durável, commit de QUEUED/outbox permite 202. Worker inspeciona duração/conteúdo antes de extrair; mídia inválida termina em FAILED. A futura notificação publicará evento durável de falha para envio de e-mail. O aceite significa trabalho durável para validação, não garantia de mídia válida.

Download também pela API, em streaming. Toda nova chamada verifica estado atual da conta, dono e expiresAt. Isso evita URLs diretas ainda válidas após inativação. Transferência já iniciada e cópia já baixada não podem ser revogadas retroativamente. Streaming aumenta tráfego/carga na API, aceitável como proposta acadêmica; timeout e limites de entrada devem ser coerentes com 100 MB.

Interface consulta status periodicamente enquanto autenticada; intervalo proposto de 5 segundos, interrompido no logout/expiração. Não há API de avisos. Cadastro, login e arquivos estáticos são públicos; administração e arquivos exigem autorização no backend.

## Consistência e recuperação

Ver [integração](integration.md). Banco/outbox, inbox idempotente, versão de agregado e tentativa de execução impedem perda após aceite e regressão por eventos fora de ordem. Worker mantém lease, renova visibilidade SQS e só reconhece após resultado/outbox persistidos. Uma falha terminal recebida por vídeos publica aviso por sua própria outbox.

Inativação impede novo acesso e submissões; efeito sobre jobs já em execução continua proposto: concluir internamente e preservar disponibilidade normal sem liberar acesso à conta inativa. Exclusão permanece pendente: identidade coordena cleanup de vídeos e processamento e só conclui após confirmações. O antigo participante de limpeza de avisos deixa de existir; tratamento de e-mails/eventos pendentes após exclusão será definido antes de implementar os contratos. Não reintroduzir dados por replay após cleanup.

## Pontos para fechamento

Ambiente de demonstração temporário: algumas semanas, no máximo um mês ligado, seguido de desativação. Incluir encerramento dos recursos e retenção dos dados. Estimativa/medição financeira dispensada explicitamente pelo responsável; não constitui bloqueio para rede/ECR. Ver [rede e registros](../operations/cloud-network-registry.md).

Backend existente fiap-fase-05 em us-east-1 já validado. Rede/ECR provisionados e convergentes. EKS privado/Spot provisionado com dois nós e quatro add-ons ACTIVE, apply e drift aprovados; seguem SSM, RDS/configuração e deploy. Ver [runtime EKS](../operations/eks-runtime.md). Período ativo definido em até um mês, sem etapa de estimativa financeira. Domínio DNS/certificado da origem é necessário na etapa de entrada HTTPS. Para os contratos operacionais: fechar política de jobs já iniciados quando apenas inativar, backups e retenção de metadados. Notificação fica para o final, com contrato, destinatário, duplicatas e configuração SES ainda por detalhar.

Fontes técnicas: [SQS Standard](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues.html), [EKS node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html), [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html). São referências de capacidade; dimensionamento ainda não foi testado.
