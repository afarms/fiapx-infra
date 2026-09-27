# Validação do backend Terraform no S3

Configuração inicial sem recursos de aplicação. O bucket existente permanece fora do gerenciamento desta raiz Terraform; não será criado, importado ou destruído por ela.

| Item | Valor |
| --- | --- |
| Terraform | 1.14.7 |
| Região | us-east-1 |
| Bucket | fiap-fase-05 |
| Key | fiapx-infra/tfstate/terraform.tfstate |
| Lock | fiapx-infra/tfstate/terraform.tfstate.tflock |
| Workspace | default |

`use_lockfile=true` habilita o lock nativo S3. `encrypt=true` solicita SSE-S3, sem chave KMS configurada. Não cria tabela DynamoDB. A política IAM existente permite listar o bucket, ler/gravar o estado e ler/gravar/excluir o lock.

## Validação local

Instalar Terraform 1.14.7 e GNU Make. Na raiz do repositório, executar `make verify`: fmt, init sem backend e validate. Não requer credenciais AWS, não valida acesso remoto e não aplica recursos.

## Execução real após o merge

PRs para main e pushes na main executam **Terraform CI**, com check **terraform-validate** (make verify, sem credenciais AWS ou inicialização do backend remoto). Configurar exatamente `terraform-validate` como status check obrigatório no ruleset de main. Os workflows manuais OIDC/backend não devem ser obrigatórios para merge, pois só executam na main após integração.

1. Abrir **Actions → Terraform backend check → Run workflow → main**.
2. Conferir o job **check-backend** e o resumo **Terraform S3 backend check passed**.
3. Em caso de falha, consultar a etapa que falhou; não executar force-unlock ou excluir um lock sem confirmar que não há execução ativa.

Usa as mesmas variáveis AWS_ROLE_ARN e AWS_REGION e confiança OIDC do teste de identidade. Somente execução manual na main, sem GitHub Environment. `concurrency` evita sobreposição deste workflow; o lock S3 protege operações Terraform cooperantes fora dele também.

O workflow recusa um estado existente com recursos ou outputs. `make backend-check` executa init, validate e plan com locking, exigindo código de saída zero. Não existe apply neste fluxo. A primeira inicialização pode gravar um estado vazio; Terraform cria e libera o lock nas operações necessárias. Não envia estado ou plano como artefatos e não mostra conteúdo do estado no preflight.

Um resultado verde comprova inicialização e plan com lock habilitado, mas não um teste de contenção com dois processos simultâneos. Se o estado já existia, não comprova uma nova escrita do estado. Antes de acrescentar recursos de aplicação, substituir este diagnóstico de configuração vazia pelo fluxo normal de plan/apply.

## Conferência do bucket pelo proprietário

Antes de armazenar estado de recursos reais, conferir no console S3:

- **Propriedades → Versionamento:** habilitado, para recuperação do estado.
- **Propriedades → Criptografia padrão:** confirmar o modo; este backend solicita SSE-S3. Se houver exigência de SSE-KMS por política, ajustar backend e permissões da chave antes de executar.
- **Permissões → Bloqueio de acesso público:** todas as opções habilitadas; revisar também a política do bucket.

O workflow não consulta nem altera essas proteções: a role atual não tem as permissões de leitura dessas configurações. Sucesso no backend não certifica a segurança global do bucket. Não conceder acesso administrativo para resolver um erro de backend; identificar a ação e o recurso negados.

Referência: [backend S3 do Terraform](https://developer.hashicorp.com/terraform/language/backend/s3).
