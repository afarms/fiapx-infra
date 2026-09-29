# CI/CD com manifestos Kubernetes

Implementação preparada e validada por schema e dry-run na API; publicação, apply e rollout real ainda pendentes.

## Organização

Cada serviço mantém em k8s/ os arquivos configmap.yaml, deployment.yaml, hpa.yaml, secrets.yaml, service.yaml e serviceaccount.yaml. Configuração e recursos das aplicações são declarados nesses YAMLs. Terraform gerencia AWS: EKS/RDS, IAM/OIDC, Pod Identity, Metrics Server e túnel de rede. O namespace compartilhado está em k8s/namespace.yaml da infraestrutura, aplicado durante o bootstrap administrativo antes da ativação dos serviços.

No workflow de cada serviço, os comandos kubectl apply e kubectl rollout status executam diretamente no runner GitHub Actions. O runner abre uma conexão SSM até a API privada do EKS; a máquina administrativa apenas encaminha o tráfego. Não executa scripts de deploy e não recebe os manifestos das aplicações. Não há gerador Python, documento SSM Command de deploy nem definição de Deployment no Terraform.

SSM é o serviço AWS usado também no túnel do DBeaver. O documento fiapx-eks-tunnel permite encaminhar apenas para o endpoint EKS443, usando a porta local18443. TLS preserva validação da CA e do hostname via tls-server-name; não há insecure-skip-tls-verify. A conexão é encerrada no passo always do workflow.

## Fluxo

1. PR executa testes/cobertura, build e validação estrita dos YAMLs com kubeconform.
2. Push na main após merge executa as mesmas verificações, assume role AWS via OIDC e publica imagem com SHA completo.
3. Tags ECR são imutáveis; reexecução reutiliza imagem existente. A Action resolve o digest para IMAGE_REF.
4. Runner abre túnel, confere revisão da main e sequência da release, preenche ConfigMaps e aplica Secrets diretamente por stdin. Aplica ServiceAccount, Deployment, Service e HPA pelos arquivos versionados do mesmo checkout.
5. Aguarda rollout e mostra o HPA. Falhas impedem sucesso. PRs e workflow_dispatch apenas validam; Re-run jobs da execução push repete a entrega.

Concorrência por workflow/ref não cancela deploy em andamento. A Action confere a main antes da publicação e do rollout, e compara github.run_id com a anotação de release do Deployment. Nova main que surgir durante um rollout entra na próxima execução. Nenhum comando remoto de deploy continua rodando após o runner.

## Configuração antes dos merges

Aplicar primeiro o PR de infraestrutura. Antes de publicá-lo, validar e instalar application-delivery-policy.json com ACCOUNT_ID substituído, anexando à role fiapx-infra-github-actions e preservando políticas existentes. Conferir quota de anexos e plano; não há necessidade de substituir EKS/EC2/RDS.

O output application_delivery informa os valores públicos. Configurar em cada repositório:

| Tipo | Nome | Valor |
|---|---|---|
| Repository secret | AWS_ROLE_ARN | Role correspondente ao serviço |
| Repository variable | ADMIN_INSTANCE_ID | Instância administrativa atual |
| Repository variable | DB_HOST | Endpoint RDS |
| Repository variable | MEDIA_BUCKET_NAME | Bucket de mídia; vídeos/worker |
| Repository variable | PROCESSING_QUEUE_URL | Fila de trabalho; vídeos/worker |
| Repository variable | VIDEOS_EVENTS_QUEUE_URL | Fila de resultados; vídeos/worker |

A região é us-east-1; cluster fiapx; segredo agregado fiapx/runtime. Banco lógico, flags, pools/defaults e endereços internos estão nos manifests. Se a instância Spot for substituída, atualizar ADMIN_INSTANCE_ID.

A trust OIDC usa o subject imutável do GitHub: `repo:afarms@37558207/REPOSITORIO@REPOSITORY_ID:ref:refs/heads/main`. Os IDs públicos são fixados em Terraform para cada serviço; o formato antigo sem IDs não corresponde aos tokens destes repositórios e causa AccessDenied em AssumeRoleWithWebIdentity. Manter audience sts.amazonaws.com, igualdade exata e branch main, sem curinga. Ver [subjects imutáveis](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims).

## Configurações e segredos

ConfigMap contém dados não secretos e CA pública do RDS. A Action baixa o bundle regional AWS, insere em binaryData e monta /etc/fiapx/ca/rds-ca.pem. DB_URL usa sslmode=verify-full e sslrootcert nesse caminho, validando certificado e hostname do RDS.

secrets.yaml contém somente placeholders de valores base64. scripts/render-secrets.sh lê fiapx/runtime em memória e seleciona os campos do serviço: usuário/senha do banco próprio; identidade e vídeos recebem chave interna e chave JWT pública; apenas identidade recebe a chave JWT privada. A senha mestre não é entregue aos Pods. A saída vai por pipe ao kubectl, sem arquivo de credenciais, GITHUB_ENV ou logs. Server-side apply evita anotação last-applied com uma cópia dos valores. Base64 não é criptografia.

As roles CI são identidades confiáveis: leem o agregado para a projeção e têm AmazonEKSEditPolicy somente no namespace fiapx. Essa permissão abrange recursos e Secrets dos três serviços nesse namespace; não é isolamento administrativo entre repositórios. Os Pods não recebem GetSecretValue: vídeos/worker usam Pod Identity com permissões próprias S3/SQS, identidade não precisa de IAM.

Rotação de senha exige coordenar banco/Secrets Manager e novo rollout dos serviços. Bootstrap de ADMIN continua desabilitado; não são criadas credenciais administrativas automaticamente.

## HPA e recursos

HPA autoscaling/v2 usa CPU70% dos requests. APIs: mínimo1/máximo2; worker: mínimo2/máximo3. Metrics Server é add-on EKS fixado em versão compatível. Deployment omite replicas para não sobrescrever decisões do HPA. Verificar ScalingActive após os Pods fornecerem métricas; dry-run não comprova autoscaling.

Requests/limits, probes, mounts e diretórios emptyDir estão em deployment.yaml. HPA aumenta Pods, não nós: os dois nós Spot continuam fixos e a capacidade disponível limita o agendamento. Worker consome SQS; CPU é a métrica inicial simples, sem escalonamento por tamanho de fila. Processing permanece ClusterIP; Identity/Video usam NodePort privado para o ALB, conforme [entrada pública](public-api.md).

## Falhas e retorno

Se rollout falhar, inspecionar eventos/health/SSM de forma privada. Não imprimir Secrets ou logs de debug de credenciais. Para retorno, preferir git revert e novo merge, produzindo nova imagem/SHA e passando pelas verificações. Em emergência, operador pode usar kubectl rollout undo após conferir compatibilidade do schema. Migrações Liquibase e senhas não são revertidas automaticamente.

Referências: [manifests declarativos](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/), [HPA](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/), [Metrics Server EKS](https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html), [TLS JDBC](https://jdbc.postgresql.org/documentation/ssl/).
