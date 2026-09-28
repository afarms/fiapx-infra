# Fila de resultados e acesso local de processamento

Terraform preparado e validado localmente; fila de resultados e role do worker ainda não provisionadas. Os consumidores dos serviços de processamento e vídeos estão implementados e testados localmente. A fila de trabalho/DLQ e a role do produtor já foram provisionadas anteriormente.

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
- Vídeos: preserva permissões anteriores do upload/produtor; passa a ReceiveMessage/ChangeMessageVisibility/DeleteMessage somente na fila de resultados e GetObject em results/*.
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

`make verify`: fmt, init sem backend, validate, quatro cenários Terraform com provider mock e oito cenários do guard de PR aprovados. O novo cenário confere filas, redrive exclusivo, TLS, confiança local e conjunto exato de permissões. Testes mock não comprovam IAM efetivo ou entrega SQS real. Ensaio de mensagens exige serviços prontos e plano controlado de dados/limpeza.
