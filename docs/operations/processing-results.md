# Fila de resultados e acesso local de processamento

Fila de resultados/DLQ e role local do worker provisionadas pelo pipeline; consumidores de processamento e vídeos implementados e testados localmente. As permissões de limpeza de resultados também foram integradas e aplicadas. Provisionamento não comprova execução integrada do processamento/download na AWS, que continua pendente. Este estado corrige as indicações históricas de preparação abaixo.

## Recursos

| Recurso | Configuração |
| --- | --- |
| fiapx-videos-events | SQS Standard, SSE gerenciada, retenção quatro dias, visibilidade 120 segundos, long polling 20 segundos |
| fiapx-videos-events-dlq | Standard, SSE gerenciada, retenção 14 dias; recebe exclusivamente da fila de resultados após cinco recebimentos |
| fiapx-processing-local | Role de sessão temporária, confiança no mesmo usuário rafael-admin da conta corrente |
| fiapx-video-results-consumer | Policy adicional na role fiapx-video-local; preserva a policy existente do produtor |

As filas rejeitam transporte sem TLS e possuem prevent_destroy. O contador de recebimentos SQS é independente de tentativas de processamento de mídia. Não adicionar permissão de consumo das DLQs às aplicações como solução para falhas.

## Permissões das aplicações

- Worker: GetObject em originals/*; GetObject/PutObject/DeleteObject e listagem restrita a results/*; ReceiveMessage/ChangeMessageVisibility/DeleteMessage somente na fila de trabalho; SendMessage somente na fila de resultados.
- Vídeos: preserva permissões anteriores do upload/produtor; ReceiveMessage/ChangeMessageVisibility/DeleteMessage somente na fila de resultados e GetObject/DeleteObject em results/*, para download e limpeza assíncrona.
- Nenhuma destas policies permite escrever no estado Terraform, gerenciar IAM, consumir DLQs ou alterar a configuração de filas. A policy do worker não permite remover originais ou consumir resultados.

As permissões DeleteMessage habilitam ACK explícito. As aplicações o executam somente após commit do efeito durável; IAM não consegue impor a ordem da transação. Eventos de resultado usam inbox + efeito em uma transação, e worker usa resultado + outbox. Heartbeat/ACK e deduplicação foram testados localmente; a validação AWS do processamento permanece pendente.

## Preparação do provisionamento

Atualizar a política adicional da role GitHub conforme [processing-pipeline-policy.json](processing-pipeline-policy.json), substituindo ACCOUNT_ID apenas na configuração administrativa real. O arquivo cobre filas de trabalho/resultados e as duas roles locais; não concede consumo/envio de mensagens ao pipeline. Preservar as permissões existentes de backend e mídia. A alteração IAM real não foi executada nesta preparação.

O workflow existente executa plan e apply automaticamente em PR autorizado. Antes da publicação, revisar essa consequência e o escopo: duas filas, redrive/TLS, uma role e suas policies; sem EKS/RDS ou mudança de state. O plan real deve ser inspecionado: nenhuma destruição/substituição de recursos existentes é esperada. Não há plan remoto nem apply executado nesta validação local.

Após implantação, conferir atributos, redrive, TLS, trust e políticas por leitura AWS. Outputs sensíveis: video_events_queue_url, video_events_queue_arn, video_events_dlq_url e processing_local_role_arn. URLs devem ser configuradas diretamente nas aplicações; policies não concedem descoberta/listagem de filas.

Configuração local futura, com ARN real fora do Git:

```ini
[profile fiapx-processing-local]
role_arn = arn:aws:iam::ACCOUNT_ID:role/fiapx-processing-local
source_profile = rafael-admin
region = us-east-1
```

Não compartilhar sessões do produtor/worker nem usar role de provisionamento nas aplicações. Não foram criados perfis, chaves, mensagens ou objetos nesta entrega.

## Validação

`make verify`: fmt, init sem backend, validate e oito cenários do guard de PR. Testes Terraform com mocks foram removidos; IAM efetivo e entrega SQS exigem validação na AWS. Ensaio de mensagens exige serviços prontos e plano controlado de dados/limpeza.

## Limpeza de resultados expirados

A policy de resultados da role fiapx-video-local inclui DeleteObject apenas em results/* no bucket de mídia. O serviço de vídeos usa essa permissão para excluir ZIPs expirados após adquirir claim PostgreSQL e verificar ausência de downloads ativos. Não acrescenta PutObject, ListBucket ou DeleteObjectVersion.

A policy é provisionada pelo workflow Terraform; sua efetividade exige validação na AWS. Confirmar a execução correspondente e as permissões da identidade usada pela aplicação antes de habilitar RESULT_CLEANUP_ENABLED; sucesso no apply não substitui o teste do workload na cloud. A rotina preserva metadados e repete falhas de forma idempotente. Originais e órfãos do worker mantêm suas responsabilidades existentes.
