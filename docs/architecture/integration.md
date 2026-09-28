# Integração e contratos propostos

Estado: identidade, consultas, upload, processamento, download e limpeza implementados. Notificações e exclusão distribuída abaixo são contratos planejados; validação integrada na cloud ainda pendente. Sem compartilhamento de entidades ou acesso cruzado a bancos.

## Contratos HTTP

| Serviço | Superfície atual e proposta |
| --- | --- |
| Identidade | Implementados cadastro, login, perfil, credenciais, listagem e gestão administrativa; exclusão e status da operação ainda propostos |
| Identidade interna | Verificar conta/permissões atuais e autorização de execução; autenticação do serviço chamador obrigatória |
| Vídeos | Implementados GET /videos, GET /videos/{id}, upload multipart e GET /videos/{id}/download |
| Notificações | Sem API HTTP; Lambda consome evento de falha e envia e-mail pelo SES; ainda não implementada |
| Processamento | Sem endpoint público de negócio; health/readiness e métricas internos |

JWT: emissor/audiência definidos no contrato, assinatura RS256 implementada, expiração 30min; bloquear alteração de role/status pelo cadastro ou edição de USER. Consulta interna indisponível retorna falha de dependência e não autoriza. Não cachear permissões positivas que atrasem bloqueio. As requisições já autorizadas não constituem promessa de interrupção retroativa.

## Filas (cinco funcionais + cinco DLQs)

| Fila | Publicadores | Consumidor lógico | Eventos |
| --- | --- | --- | --- |
| processing-work | Vídeos | Processamento | VideoProcessingRequested |
| processing-control | Identidade | Processamento | UserDeletionRequested |
| videos-events | Processamento, identidade | Vídeos | ProcessingStarted, ProcessingCompleted, ProcessingFailed, UserDeletionRequested |
| notifications-events | Vídeos | Lambda de e-mail | VideoFailed; contrato pendente |
| identity-events | Vídeos, processamento | Identidade | UserDataDeleted / confirmação por participante |

Réplicas do mesmo serviço disputam sua fila; serviços diferentes não disputam um evento que todos precisam receber. A outbox de identidade cria uma publicação por destino de exclusão. Falha em um envio não perde nem repete como efeito o que outro consumidor já concluiu. processing-control é separado de trabalho pesado para não atrasar bloqueio por backlog de vídeos.

Envelope: eventId, eventType, schemaVersion, aggregateId, ownerId, correlationId, occurredAt, payload. Exclusão inclui deletionId; resultado inclui jobId, attempt e versão. Sem credenciais ou binários. eventId estável por publicação lógica e destino; consumidores transacionais persistem inbox junto do efeito. ACK/DeleteMessage somente após efeito durável. Resultados e confirmações usam outbox. Isso não oferece atomicidade entre envio de e-mail e confirmação de consumo pela Lambda; política de duplicatas será definida no contrato de notificações.

## Notificação mínima de erro (planejada)

Após registrar FAILED definitivo, vídeos publica VideoFailed por outbox na notifications-events. A Lambda envia e-mail simples pelo SES para o dono, com identificação do vídeo, sem detalhes internos. Retentativas limitadas e DLQ tratam falhas de envio; não reiniciar processamento por falha do e-mail. Não há avisos de sucesso, endpoints, histórico de leitura ou banco próprio. Detalhar endereço do destinatário, configuração SES e comportamento frente a duplicatas/exclusão antes da implementação. Ver [ADR-0002](adr/0002-email-notifications-cloud-first.md).

## Políticas iniciais para validação

SQS Standard; long polling e limites de consumo conforme capacidade real. Proposta: retenção principal 4 dias, DLQ 14 dias, maxReceiveCount 5; visibilidade de trabalho 120 segundos renovada a cada 30 segundos. Esses valores exigem teste de falha/carga e não são requisitos do enunciado. Lease persistido de execução identifica tentativa e vence se não renovado; resultado antigo não pode vencer tentativa atual. Falha determinística de mídia é resultado de negócio, não motivo para repetir cinco vezes.

Alarme para qualquer DLQ. Procedimento de reconciliação correlaciona job/deletionId, registra falha ou pendência e permite redrive após correção. Exclusão não é declarada concluída se confirmação estiver em DLQ. Mensagens malformadas sem identificação permanecem incidente operacional, sem inventar usuário/trabalho correspondente.

## Exclusão distribuída

1. Identidade valida ADMIN/proteção do último admin e persiste bloqueio da conta, operação de exclusão e outbox na mesma transação.
2. Consumidores persistem marcador mínimo por ownerId. Novos uploads/trabalhos/resultados são rejeitados; chamadas à identidade também impedem autorização de contas em exclusão.
3. Processamento interrompe ou aguarda encerramento seguro das execuções e elimina seus dados/temporários. Vídeos remove objetos e registros. Não existe banco de avisos para limpar.
4. Cada proprietário confirma por outbox após cleanup e verificação de concorrência. Identidade acompanha as confirmações de vídeos e processamento e remove definitivamente perfil/credenciais. A política para eventos de e-mail pendentes ainda precisa ser definida; esta revisão não declara o contrato de exclusão pronto.
5. Marcadores técnicos sem perfil são mantidos para impedir recriação por replay; prazo final deve cobrir retenção de mensagens, outbox e redrives. Não apagar marcador enquanto houver trabalho ou replay possível.

O workflow deve reconciliar uploads/escritas iniciados antes do bloqueio, que podem terminar depois de uma primeira varredura. Confirmação de cleanup só ocorre após encerrar produtores conhecidos e verificar nova varredura. Backups seguem expiração própria; restauração reaplica exclusões antes de liberar acesso.

## Evidências exigidas

Testar crash em cada fronteira commit/publicação/ACK; mensagens duplicadas e fora de ordem; bloqueio de conta com JWT existente; exclusão concorrente a upload/extração/download; status pós-expiração; dois vídeos simultâneos; recuperação de DLQ. Sem resultados executados nesta etapa.
