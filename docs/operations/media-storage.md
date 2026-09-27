# Armazenamento de mídia e entrega Terraform

Configuração preparada para um bucket privado em us-east-1. Provisionamento remoto ainda não verificado. Originais e ZIPs compartilharão o bucket, com prefixos distintos definidos pela aplicação. O bucket não hospeda frontend nem estado Terraform.

## Configuração inicial pelo administrador

1. Escolha um nome globalmente único começando por `fiapx-media-`, sem número da conta ou dados pessoais. Cadastre-o em Settings → Secrets and variables → Actions → Variables como `MEDIA_BUCKET_NAME`.
2. Mantenha `AWS_ROLE_ARN` em Secrets e `AWS_REGION=us-east-1` em Variables. A confiança OIDC continua restrita à main; não criar Environment para estes jobs sem revisar a confiança.
3. Na AWS, abra IAM → Roles → fiapx-infra-github-actions → Add permissions → Create inline policy. Copie [a política adicional](media-pipeline-policy.json), substitua `REPLACE_WITH_MEDIA_BUCKET_NAME` pelo nome exato e salve como `fiapx-media-provisioning`. Preserve a política existente de estado/lock. Esta role não recebe acesso aos objetos de mídia nem permissão de excluir o bucket.
4. Em S3 → fiap-fase-05, confira versionamento Enabled, criptografia padrão SSE-S3 e as quatro opções de bloqueio público habilitadas. O pipeline verifica esses atributos em modo somente leitura e falha se não corresponderem. Caso seja necessário mudá-los, faça isso conscientemente pelo console; Terraform não gerencia esse bucket existente.

## Plan e revisão privada

Depois do merge, Actions → Terraform delivery → Run workflow → main → operation `plan`. Os demais campos ficam vazios.

O summary informa ID do plano, commit e SHA-256. O plano binário, manifesto e texto ficam em `s3://fiap-fase-05/fiapx-infra/plans/<ID>/`. Não são publicados como artefatos GitHub, pois planos podem conter dados sensíveis. Abra o objeto `plan.txt` no console S3 usando sua sessão administrativa e baixe-o para revisar todos os recursos, valores e outputs. Não compartilhe o conteúdo publicamente.

Primeira entrega esperada: seis recursos S3 (bucket, bloqueio público, propriedade, criptografia, versionamento e política TLS), sem EKS/RDS/SQS/IAM. A política de acesso a objetos pelos serviços será criada quando suas identidades AWS forem implementadas. Ausência de permissões ou nome já ocupado exige correção e novo plan.

## Apply explícito

Após revisar, execute novamente Terraform delivery na main com operation `apply` e copie `plan_id`, `plan_commit` e `plan_sha256` do run de plan bem-sucedido. O próprio disparo manual confirma a execução do plano revisado; não existe aprovação por segundo revisor configurada aqui.

O script exige mesmo commit/configuração, checksum válido e plano com menos de 24 horas. Aplica exatamente o binário salvo, com lock. Main alterada exige novo plan. O Terraform também rejeita planos com estado incompatível; não use force-unlock como correção automática. O workflow bloqueia planos com exclusões/substituições.

Logs completos de apply e verificação são armazenados no mesmo prefixo privado. Depois do apply, o pipeline exige plan sem alterações. Verde confirma essas verificações; confira também os controles do bucket no console. Apply parcial/falha exige inspecionar o log privado e gerar outro plan.

Há uma única fila de execução GitHub para esse estado (`cancel-in-progress: false`) e lock nativo S3. Isso não mantém o estado travado durante a revisão humana nem impede alterações externas na AWS. Faça apply logo após revisão; havendo mudança externa conhecida, gere novo plan. Planos privados não possuem expiração física automática: ficam para revisão administrativa; a validade de 24 horas é verificada pelo script. Remova planos antigos pelo console conforme necessário, sem apagar estado ou lock.

## Mídia e proteção

SSE-S3, ACLs desabilitadas, bloqueio público e recusa de HTTP. `force_destroy=false` e `prevent_destroy=true` protegem o bucket no fluxo Terraform, mas não impedem ações administrativas fora dele. Versionamento de mídia suspenso: não oferece recuperação de exclusões. Versionamento do estado continua obrigatório e independente.

A disponibilidade funcional continua sendo 24 horas **após concluir o processamento**. Não há lifecycle apagando objetos pela idade do upload. Autorização, expiração, limpeza de uploads incompletos/órfãos e exclusão por usuário dependem dos futuros fluxos da aplicação; não considerar este bucket um fluxo de upload pronto.

## Workflows e validação

- Terraform CI: PR/main, `make verify`, testes com provider mock sem conta AWS; check obrigatório `terraform-validate` preservado.
- AWS OIDC check: diagnóstico manual da autenticação.
- Terraform delivery: plan/apply manuais na main.

Terraform backend check foi aposentado após validar o bootstrap no run 36357194092. Seu teste exigia configuração/estado vazios; os novos jobs passam a validar o backend durante a entrega.

Validações locais: `make fmt`, `make verify`; `make lock` atualiza checksums Windows/Linux do provider fixado. Testes mock não substituem a execução AWS. Não executar plan/apply diretamente sem os controles do workflow.

Referências: [planos salvos](https://developer.hashicorp.com/terraform/cli/commands/plan), [dados sensíveis em planos](https://developer.hashicorp.com/terraform/language/manage-sensitive-data), [mock de providers](https://developer.hashicorp.com/terraform/language/tests/mocking), [permissões S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-with-s3-policy-actions.html).
