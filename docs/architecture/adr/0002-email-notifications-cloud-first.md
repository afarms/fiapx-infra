# ADR-0002 — E-mail mínimo e prioridade do fluxo na cloud

Data: 2026-09-28. Estado: ACEITO. Substitui na ADR-0001 a execução de notificações como quarto serviço Java no EKS e os avisos persistidos na interface. Os três serviços existentes continuam independentes e no EKS.

## Contexto e decisão

O enunciado permite notificação em caso de erro por e-mail ou outro meio. Não exige um serviço dedicado, histórico de leitura ou notificações de sucesso. Para reduzir a implementação e a operação, uma falha definitiva de processamento originará evento durável no serviço de vídeos, entregue por SQS a uma Lambda que enviará e-mail pelo SES. A capacidade será implementada depois do fluxo principal na AWS.

O aviso identifica o vídeo e comunica a falha ao dono. Não inclui binários, credenciais ou detalhes internos de erro. Não haverá endpoint de notificações, banco de avisos, Deployment Java ou quarto banco de domínio no RDS. Runtime e localização do código da Lambda ainda serão definidos; não se presume um novo repositório já criado.

## Confiabilidade e limites a detalhar

A publicação deve acompanhar o estado FAILED de forma durável, com outbox, para sobreviver a falhas entre commit e envio. A fila terá retentativas limitadas e DLQ. Falha ao enviar o e-mail não reinicia o processamento nem modifica o resultado do vídeo. Não avisar cada tentativa transitória do worker.

O contrato do evento, a obtenção segura do endereço do dono, a configuração/verificação do remetente e destinatários de demonstração no SES e o tratamento de duplicatas serão definidos na implementação desta capacidade. Não prometer exatamente um e-mail: é necessário tratar a janela entre envio externo e confirmação do consumo. Aceite do provedor não comprova recebimento na caixa postal.

A exclusão distribuída permanece pendente. Sem banco de avisos, a Lambda não mantém o antigo participante de limpeza de avisos; a política de eventos pendentes, destinatários e mensagens após exclusão deve ser reconciliada antes dessa funcionalidade. E-mails já enviados não são removidos por exclusão da conta.

## Ordem de entrega

Ambiente temporário para demonstração: permanecer ligado por algumas semanas, no máximo um mês, e depois ser desativado. O planejamento de infraestrutura deve incluir o encerramento dos recursos e a decisão sobre retenção de dados; esta intenção não autoriza destruir recursos existentes nesta etapa. Teto de orçamento ainda não informado.

1. Base cloud para os três serviços: rede/ECR, EKS/RDS, secret e identidades de workload.
2. Deploy, migrations e acesso HTTPS; interface mínima para o fluxo principal.
3. Validação integrada na AWS de upload, concorrência, recuperação, status, download e limpeza.
4. Notificação mínima por e-mail e conclusão das demais pendências da entrega, incluindo exclusão distribuída e documentação final.

Esta decisão não representa provisionamento concluído. O pipeline de infraestrutura aplica mudanças no PR; dimensionamento, recursos e plano devem estar definidos antes da publicação de incrementos de infraestrutura.
