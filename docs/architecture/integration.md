# Integração e contratos propostos

Estado: contratos HTTP de identidade e consultas de vídeos implementados e documentados no OpenAPI dos respectivos serviços. Upload, download, processamento, notificações e eventos abaixo continuam propostos. Sem compartilhamento de entidades ou acesso cruzado a bancos.

## Contratos HTTP

| Serviço | Superfície atual e proposta |
| --- | --- |
| Identidade | Implementados cadastro, login, perfil, credenciais, listagem e gestão administrativa; exclusão e status da operação ainda propostos |
| Identidade interna | Verificar conta/permissões atuais e autorização de execução; autenticação do serviço chamador obrigatória |
| Vídeos | Implementados GET /videos e GET /videos/{id}; POST multipart e download ainda propostos |
| Notificações | GET /notifications paginado, somente avisos do dono |
| Processamento | Sem endpoint público de negócio; health/readiness e métricas internos |

JWT: emissor/audiência definidos no contrato, assinatura RS256 implementada, expiração 30min; bloquear alteração de role/status pelo cadastro ou edição de USER. Consulta interna indisponível retorna falha de dependência e não autoriza. Não cachear permissões positivas que atrasem bloqueio. As requisições já autorizadas não constituem promessa de interrupção retroativa.

## Filas (cinco funcionais + cinco DLQs)

| Fila | Publicadores | Consumidor lógico | Eventos |
| --- | --- | --- | --- |
| processing-work | Vídeos | Processamento | VideoProcessingRequested |
| processing-control | Identidade | Processamento | UserDeletionRequested |
| videos-events | Processamento, identidade | Vídeos | ProcessingStarted, ProcessingCompleted, ProcessingFailed, UserDeletionRequested |
| notifications-events | Vídeos, identidade | Notificações | VideoFailed, UserDeletionRequested |
| identity-events | Vídeos, processamento, notificações | Identidade | UserDataDeleted / confirmação por participante |

Réplicas do mesmo serviço disputam sua fila; serviços diferentes não disputam um evento que todos precisam receber. A outbox de identidade cria uma publicação por destino de exclusão. Falha em um envio não perde nem repete como efeito o que outro consumidor já concluiu. processing-control é separado de trabalho pesado para não atrasar bloqueio por backlog de vídeos.

Envelope: eventId, eventType, schemaVersion, aggregateId, ownerId, correlationId, occurredAt, payload. Exclusão inclui deletionId; resultado inclui jobId, attempt e versão. Sem credenciais ou binários. eventId estável por publicação lógica e destino; consumidores persistem inbox junto do efeito transacional. ACK/DeleteMessage somente após efeito durável. Resultados e confirmações usam outbox.

## Políticas iniciais para validação

SQS Standard; long polling e limites de consumo conforme capacidade real. Proposta: retenção principal 4 dias, DLQ 14 dias, maxReceiveCount 5; visibilidade de trabalho 120 segundos renovada a cada 30 segundos. Esses valores exigem teste de falha/carga e não são requisitos do enunciado. Lease persistido de execução identifica tentativa e vence se não renovado; resultado antigo não pode vencer tentativa atual. Falha determinística de mídia é resultado de negócio, não motivo para repetir cinco vezes.

Alarme para qualquer DLQ. Procedimento de reconciliação correlaciona job/deletionId, registra falha ou pendência e permite redrive após correção. Exclusão não é declarada concluída se confirmação estiver em DLQ. Mensagens malformadas sem identificação permanecem incidente operacional, sem inventar usuário/trabalho correspondente.

## Exclusão distribuída

1. Identidade valida ADMIN/proteção do último admin e persiste bloqueio da conta, operação de exclusão e outbox na mesma transação.
2. Consumidores persistem marcador mínimo por ownerId. Novos uploads/trabalhos/resultados são rejeitados; chamadas à identidade também impedem autorização de contas em exclusão.
3. Processamento interrompe ou aguarda encerramento seguro das execuções e elimina seus dados/temporários. Vídeos remove objetos e registros; notificações remove avisos.
4. Cada serviço confirma por outbox após cleanup e verificação de concorrência. Identidade acompanha três confirmações e remove definitivamente perfil/credenciais.
5. Marcadores técnicos sem perfil são mantidos para impedir recriação por replay; prazo final deve cobrir retenção de mensagens, outbox e redrives. Não apagar marcador enquanto houver trabalho ou replay possível.

O workflow deve reconciliar uploads/escritas iniciados antes do bloqueio, que podem terminar depois de uma primeira varredura. Confirmação de cleanup só ocorre após encerrar produtores conhecidos e verificar nova varredura. Backups seguem expiração própria; restauração reaplica exclusões antes de liberar acesso.

## Evidências exigidas

Testar crash em cada fronteira commit/publicação/ACK; mensagens duplicadas e fora de ordem; bloqueio de conta com JWT existente; exclusão concorrente a upload/extração/download; status pós-expiração; dois vídeos simultâneos; recuperação de DLQ. Sem resultados executados nesta etapa.
