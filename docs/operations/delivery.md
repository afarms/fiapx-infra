# Terraform e entrega

## Fluxo do pull request

Um único workflow, **Terraform**, executa automaticamente ao abrir, reabrir ou atualizar um PR para `main`:

1. Confere que o PR vem deste repositório e que autor e executor são o proprietário.
2. Executa `make verify`: formatação, inicialização local, validação estática.
3. Autentica na AWS por OIDC e inicializa o backend S3.
4. Confere a revisão com `make check-pr` e executa `make plan`, salvando o plano no runner.
5. Repete `make check-pr` imediatamente antes de `make apply`, que usa exatamente o plano salvo.
6. Confere que não restam mudanças com `make check-drift`.

Qualquer erro interrompe as etapas seguintes e falha o check **terraform-validate**, inclusive erro no apply. Não há `continue-on-error`, `pull_request_target`, escolha manual de operação nem apply após o merge. O checkout padrão de `pull_request` testa o merge proposto com a base. PR com conflito precisa ser corrigido para executar.

O apply acontece **antes do merge**, por escolha do projeto. A infraestrutura pode mudar mesmo se o PR depois for fechado sem merge; falha de apply também pode deixar alterações parciais. Corrigir o código e executar novamente, sem presumir rollback. A HashiCorp exemplifica plan no PR/apply após merge; o fluxo adotado aqui antecipa o apply para condicioná-lo ao check obrigatório.

Há um estado compartilhado: apenas um PR próprio para main pode estar aberto durante o deploy. `make check-pr` consulta o GitHub e falha se houver outro PR do proprietário no mesmo repositório, se o PR tiver sido fechado/atualizado ou se a base do evento e o primeiro pai do merge em checkout não coincidirem com a main atual. A verificação ocorre antes do plan e novamente antes do apply; atualizar a branch e executar o novo workflow resolve base obsoleta, enquanto repetir um run antigo não atualiza seu checkout.

A concorrência global e o lock S3 evitam operações simultâneas; a conferência de revisões não trava a main e não protege contra alterações administrativas por bypass durante o apply. Se fechar um PR já aplicado sem integrá-lo, reconcilie as mudanças aplicadas antes de iniciar outro PR. Não cancelar um apply em andamento nem excluir seu lock manualmente. Pessoas com permissão de escrita no repositório devem ser confiáveis, pois podem alterar código e workflow. PRs de forks ou de outros autores falham antes do checkout/autenticação neste fluxo solo.

## Configuração GitHub

Em Settings → Secrets and variables → Actions:

| Tipo | Nome | Valor |
| --- | --- | --- |
| Secret | AWS_ROLE_ARN | ARN da role fiapx-infra-github-actions |
| Variable | AWS_REGION | us-east-1 |
| Variable | MEDIA_BUCKET_NAME | Nome globalmente único iniciado por fiapx-media- |

Não duplicar ARN em Variable nem criar access keys. Conta derivada do ARN e mascarada nos logs; planos e estado não são publicados como artefatos. O plano local é apagado ao terminar o job. Logs de Terraform mostram as operações; valores sensíveis devem ser declarados como `sensitive` quando forem introduzidos.

Em Settings → Rules → Rulesets → protect-main, manter **terraform-validate** obrigatório e habilitar **Require branches to be up to date before merging**. O nome do check foi preservado, mas agora cobre também o apply. O bypass administrativo previamente configurado continua sendo uma exceção; um workflow não remove esse poder do administrador.

## Confiança OIDC na AWS

A role existente precisa aceitar eventos de PR. Em IAM → Roles → fiapx-infra-github-actions → Trust relationships → Edit trust policy, preservar o Principal do provedor OIDC e `sts:AssumeRoleWithWebIdentity`, e ajustar o bloco Condition para:

```json
{
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub": "repo:afarms@37558207/fiapx-infra@1391245105:pull_request"
  }
}
```

Esses números são os IDs imutáveis do proprietário/repositório GitHub, não o ID da conta AWS. Substituir o subject anterior terminado em `ref:refs/heads/main`; não usar curinga para todos os repositórios. Sem GitHub Environment: adicioná-lo muda o subject e exige outra revisão de trust. A condição de PR identifica o repositório/contexto, não um PR específico.

Se a role continuar aceitando só main, a etapa Authenticate using OIDC falhará e impedirá o merge normal. Não contornar isso com bypass: corrigir a confiança e executar **Re-run failed jobs**. O restante do fluxo será automático.

## Permissões e S3

Preservar a política existente para listar `fiap-fase-05`, ler/gravar `fiapx-infra/tfstate/terraform.tfstate` e ler/gravar/excluir `fiapx-infra/tfstate/terraform.tfstate.tflock`.

Adicionar ou atualizar a política de provisionamento usando [media-pipeline-policy.json](media-pipeline-policy.json), já preenchida para `fiapx-media-files`, o nome configurado no GitHub. Na role fiapx-infra-github-actions, editar a inline policy `fiapx-media-provisioning_policy`; o Resource de ProvisionMediaBucket deve ser `arn:aws:s3:::fiapx-media-files`. O nome da política não é o nome do bucket. Se mudar MEDIA_BUCKET_NAME futuramente, ajustar esse ARN também. Não substituir a política do estado por essa política adicional. Não há acesso aos objetos de mídia nem permissão de excluir o bucket. Permissões antigas exclusivas de planos em `fiapx-infra/plans/` deixam de ser necessárias; o workflow não grava nesse prefixo. Nada existente é removido automaticamente.

O bucket de estado é preexistente e não é gerenciado pelo Terraform. Região `us-east-1`, workspace `default`, criptografia solicitada SSE-S3 e lock nativo (`use_lockfile=true`), sem DynamoDB. Mantenha criptografia e bloqueio de acesso público. Versionamento não é requisito do pipeline: decisão do projeto de operar sem novas versões para limitar custos. A HashiCorp recomenda versionamento para recuperar estado; sem ele, sobrescritas/exclusões não têm essa recuperação garantida. Suspender versionamento não apaga versões antigas nem seus custos, caso existam.

O bucket privado de mídia contém originais e ZIPs em prefixos distintos, separados do estado e do frontend. SSE-S3, ACLs desabilitadas, bloqueio público, recusa de HTTP e versionamento Suspended. `prevent_destroy=true` e `force_destroy=false` protegem o fluxo Terraform; não impedem alterações administrativas fora dele.

A disponibilidade funcional permanece 24 horas após conclusão do processamento. Não há lifecycle apagando arquivos pela idade do upload. Upload/download, autorização por dono, limpeza de órfãos e exclusão distribuída serão implementados nos serviços.

## Filas de processamento e acesso local

O Terraform define `fiapx-processing-work` e `fiapx-processing-work-dlq` como filas Standard em `us-east-1`, com SSE-SQS e recusa de HTTP. A principal retém mensagens por 4 dias, usa visibilidade inicial de 120 segundos e long polling de 20 segundos; após 5 recebimentos sem exclusão, as mensagens podem seguir para a DLQ, que retém por 14 dias. Somente a principal pode usar essa DLQ. O worker precisará renovar a visibilidade durante processamentos longos e tratar duplicatas; ele ainda não está implementado.

Antes do primeiro apply deste incremento, usando `rafael-admin` no console:

1. Abra **IAM → Roles → fiapx-infra-github-actions → Permissions → Add permissions → Create inline policy**.
2. Na aba JSON, cole [processing-pipeline-policy.json](processing-pipeline-policy.json). Substitua as três ocorrências de `ACCOUNT_ID` pelo ID da sua conta, consultável no menu superior do console. Não salve a cópia preenchida no Git.
3. Nomeie a política `fiapx-processing-provisioning` e salve. Preserve as políticas existentes de estado e mídia.
4. No PR, execute **Re-run failed jobs** se o run já tiver falhado por falta dessas permissões. O workflow continua único e automático.

A política permite provisionar somente essas duas filas e a role `fiapx-video-local`. Não concede envio/consumo de mensagens ao pipeline, nem `iam:PassRole` ou gestão de usuários. A permissão de editar a role exige manter o controle do repositório e revisar suas políticas. Exclusão das filas/role não está habilitada; `prevent_destroy` também bloqueia substituições no fluxo normal.

A role local confia exclusivamente no usuário IAM `rafael-admin` da mesma conta, com caminho `/`. Sua política permite `GetObject`, `PutObject` e `DeleteObject` apenas em `originals/*`, `ListBucket` restrito a esse prefixo e `SendMessage` somente na fila principal. Não autoriza acesso ao estado Terraform, ZIPs de resultado, DLQ ou consumo de mensagens. O ARN da conta é obtido dinamicamente; não há chaves permanentes criadas pelo Terraform.

Após o apply verde, consulte o ARN em **IAM → Roles → fiapx-video-local** e a URL em **SQS → fiapx-processing-work → Details**. Os outputs Terraform correspondentes são sensíveis para não imprimir a conta por padrão. Configure em `%USERPROFILE%\.aws\config` (não no repositório), preservando os perfis existentes:

```ini
[profile fiapx-video-local]
role_arn = arn:aws:iam::ACCOUNT_ID:role/fiapx-video-local
source_profile = rafael-admin
region = us-east-1
```

O perfil fonte precisa estar autenticado como o usuário autorizado e poder executar `sts:AssumeRole`. Se a configuração do usuário exigir MFA, configure `mfa_serial` com seu dispositivo no perfil. A aplicação usará esse perfil com credenciais temporárias; a integração do SDK será preparada junto ao upload. Pod Identity para EKS permanece para a implantação das aplicações.

Para conferir a identidade local, sem criar objetos nem enviar mensagens:

```bash
aws sts get-caller-identity --profile fiapx-video-local
```

A saída deve conter `assumed-role/fiapx-video-local/`. Ela contém o ID da conta: consulte localmente, sem publicar a saída. Não use a role do pipeline ou o perfil administrativo como credencial de execução da aplicação. O teste confirma a assunção da role; a integração real S3/SQS será validada com o fluxo de upload.

## Uso local e diagnóstico

Para o incremento de rede/ECR, instalar as políticas adicionais de [rede e registros](cloud-network-registry.md#permissões-do-pipeline) antes de publicar o PR. São políticas customer-managed separadas, sem substituir as atuais. A [estrutura Terraform](../../terraform/README.md) separa versões, provider, entradas e saídas dos recursos sem mudar o backend.

`make verify` não usa AWS; baixa o provider fixado e valida a configuração. `make fmt` formata arquivos e `make lock` gera checksums Windows/Linux. `make init`, `make plan`, `make apply` e `make check-drift` são comandos remotos usados pelo workflow; apply altera recursos.

- Falha em validação: corrigir o arquivo indicado antes de autenticar.
- Falha em configuração: conferir Secret/Variables.
- Falha em OIDC: conferir audience, subject e Principal da role.
- AccessDenied no init/plan/apply: conferir ação/recurso negados e a política correspondente; não conceder AdministratorAccess ao pipeline.
- Plano obsoleto ou apply parcial: corrigir a causa e executar novamente, gerando novo plano.
- Mudanças na verificação final: investigar drift; o check permanece vermelho.

OIDC, backend, bucket de mídia, filas de processamento/resultados, rede, ECR, EKS privado e administração SSM já tiveram execução real validada. RDS privado e bootstrap dos bancos estão implementados localmente; antes do próximo PR, criar o secret único e instalar a política adicional conforme o [runbook do banco](private-database.md). O workflow executa o documento SSM após o apply para configurar os bancos e conferir acesso e isolamento. Provisionamento RDS, demais filas, publicação das imagens ECR e deploy das aplicações continuam pendentes. Os serviços mantêm seus próprios workflows de testes e build.

## Referências oficiais

- [Validação Terraform](https://developer.hashicorp.com/terraform/cli/commands/validate).
- [Apply de plano salvo](https://developer.hashicorp.com/terraform/cli/commands/apply#saved-plan-mode).
- [Automação GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions).
- [Backend S3 e recomendação de versionamento](https://developer.hashicorp.com/terraform/language/backend/s3).
- [Subject OIDC e IDs imutáveis](https://docs.github.com/en/actions/reference/security/oidc).
- [Permissões de API SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-api-permissions-reference.html).
- [Filas de mensagens mortas](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html).
- [Perfis com role na AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html).
