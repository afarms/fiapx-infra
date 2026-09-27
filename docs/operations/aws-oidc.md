# Teste de autenticação AWS pelo GitHub Actions

O workflow `AWS OIDC check` valida a autenticação temporária na AWS usando OIDC. Executa manualmente, apenas na branch `main`, e confirma a conta e a role com `aws sts get-caller-identity`. Não executa Terraform, não acessa objetos S3 e não altera recursos ou estado.

## Pré-requisitos

Em Settings → Secrets and variables → Actions → Variables, cadastrar:

| Variável | Valor |
| --- | --- |
| AWS_ROLE_ARN | arn:aws:iam::<ID_DA_CONTA>:role/fiapx-infra-github-actions |
| AWS_REGION | us-east-1 |

Na AWS, o provedor OIDC deve ser `https://token.actions.githubusercontent.com`, com audience `sts.amazonaws.com`. A confiança da role deve permitir `sts:AssumeRoleWithWebIdentity` e restringir o subject a:

```text
repo:afarms@37558207/fiapx-infra@1391245105:ref:refs/heads/main
```

O formato inclui os IDs imutáveis de proprietário e repositório, conforme o padrão do GitHub para este repositório. Não utiliza GitHub Environment; adicioná-lo exige revisar o subject e suas proteções. A role não recebe as permissões do usuário que a criou.

## Executar após o merge

1. Integrar o PR do workflow na `main`.
2. No GitHub, abrir **Actions → AWS OIDC check**.
3. Clicar em **Run workflow**, selecionar **main** e confirmar.
4. Abrir a execução e conferir o job **check-identity**.
5. Sucesso exige status verde e resumo **AWS OIDC authentication verified**, com a conta extraída de `AWS_ROLE_ARN` e sessão da role `fiapx-infra-github-actions`.

O workflow não dispara no PR nem automaticamente no merge. Outra branch é ignorada pelo job. A autenticação não pode ser comprovada antes da execução real na main.

## Diagnóstico

- Erro em Validate configuration: conferir as duas Repository Variables.
- Erro em AssumeRoleWithWebIdentity: conferir provedor, audience, subject e política de confiança; verificar execução na main, sem Environment.
- Job skipped: a branch escolhida não é main.
- Sucesso no STS não comprova acesso ao S3: a política do backend, criptografia e lock serão verificados separadamente.

Não criar access keys para esse workflow. Ele solicita token OIDC com `id-token: write` e usa credenciais temporárias. A action está fixada por SHA, correspondente à versão v6.3.0; não há checkout do código nem exposição de tokens nos logs.

Referências: [OIDC na AWS pelo GitHub](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) e [Configure AWS Credentials](https://github.com/aws-actions/configure-aws-credentials).
