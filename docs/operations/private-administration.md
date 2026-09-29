# Administração privada por SSM

Status: máquina administrativa provisionada, SSM Online e sessão real validada com log no CloudWatch. Bootstrap concluído; dois nós Kubernetes Ready e oito pods kube-system Running. A substituição da máquina e o cancelamento da requisição Spot anterior foram executados pelo pipeline. O banco ainda não existe; o túnel DBeaver depende da etapa RDS.

## Máquina e acesso

Uma t3.micro Spot AL2023 na primeira subnet privada, sem IP público, chave SSH ou ingress. A requisição Spot é persistente, com interrupção stop: sessões e túneis podem cair; disponibilidade depende de capacidade Spot. Disco gp3 de 12 GiB criptografado, IMDSv2 obrigatório e créditos de CPU standard. A máquina é exclusiva para administração; não executa aplicações nem guarda arquivos de negócio.

Saída HTTPS usa a NAT existente para SSM, APIs AWS e download do kubectl. Resolução DNS usa o resolver da VPC. A API privada do EKS permite 443 somente a partir do SG administrativo adicional. O incremento de [banco privado](private-database.md) declara saída 5432 referenciando o SG do RDS; sua aplicação ainda está pendente.

AL2023 e kubectl 1.35.3 estão fixados; o bootstrap verifica o SHA-256 antes de instalar o binário. AWS CLI v2 e SSM Agent vêm na AMI padrão. Falha no bootstrap não equivale a falha de criação EC2: verificar cloud-init e o marcador de conclusão abaixo antes de usar a máquina.

A role da instância recebe AmazonSSMManagedInstanceCore, DescribeCluster somente no fiapx, escrita no grupo de logs administrativo e acesso administrativo explícito ao Kubernetes. O incremento RDS adiciona leitura apenas do secret fiapx/runtime e DescribeDBInstances do banco próprio. Quem consegue executar comandos nessa máquina consegue administrar cluster e banco: restringir StartSession/SendCommand a administradores confiáveis. Nenhuma credencial permanente vai para o user data.

## Permissões do pipeline antes do PR

Instalar duas políticas gerenciadas adicionais na role fiapx-infra-github-actions, preservando as existentes:

- [administration-control-pipeline-policy.json](administration-control-pipeline-policy.json): nome fiapx-administration-control-provisioning; role/profile administrativo, anexo SSM Core, inline runtime policy, access entry, documento Session e logs.
- [administration-compute-pipeline-policy.json](administration-compute-pipeline-policy.json): nome fiapx-administration-compute-provisioning; AMI fixa, subnet privada, t3.micro Spot, profile administrativo, SG e regras de API.

Substituir ACCOUNT_ID em cópias locais; em compute substituir PRIVATE_SUBNET_A_ID pela subnet fiapx-private-us-east-1a. Os documentos complementam as permissões de criação/tagging de SG e de consulta EC2/Logs já instaladas. A autorização de PutRolePolicy limita-se à role administrativa; o pipeline continua sendo uma identidade confiável de provisionamento, capaz de definir os privilégios dessa role. Não pode editar sua própria role por estas políticas.

Ambos os documentos foram validados no Access Analyzer sem findings e instalados na role do pipeline antes da publicação. O workflow aplica durante o PR, portanto instalar as permissões antes de publicá-lo. Não abrir um PR apenas para descobrir ações ausentes. Após a instalação, confirmar plan/apply/drift; Access Analyzer e plan administrativo não provam a autorização efetiva do caller OIDC.

## Sessão e Kubernetes

Pré-requisitos locais: AWS CLI, credenciais do operador e Session Manager plugin. No PowerShell, após o provisionamento:

```powershell
$adminInstance = aws ec2 describe-instances --profile rafael-admin --region us-east-1 --filters Name=tag:Name,Values=fiapx-administration Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text
aws ssm start-session --profile rafael-admin --region us-east-1 --target $adminInstance --document-name fiapx-administration-shell
```

Dentro da sessão Linux:

```bash
sudo cloud-init status --wait
test -f /var/lib/fiapx-administration-ready
aws --version
kubectl version --client
fiapx-kubeconfig
kubectl get nodes
kubectl get pods -n kube-system
```

Se o marcador não existir, revisar /var/log/cloud-init-output.log e corrigir a causa; não considerar bootstrap concluído apenas porque o SSM está Online. O helper usa credenciais temporárias da role EC2 e grava kubeconfig para o usuário da sessão. Não copia chaves AWS. Confirmados dois nós Ready, pods de sistema saudáveis e acesso pela API privada na primeira validação remota. Repetir a checagem após substituições.

O documento fiapx-administration-shell envia a sessão interativa para /fiapx/administration/sessions, retenção sete dias, timeout ocioso de 20 minutos e máximo de 60. Não altera o documento global de preferências SSM da conta. Fluxo de logs confirmado na primeira sessão. Comandos/conteúdo sensível digitados no shell podem aparecer no log; manutenção do banco deve usar credenciais fora de parâmetros/logs de comandos.

## Túnel DBeaver após o RDS

Na etapa do RDS, liberar 5432 do SG administrativo para o SG do banco e configurar usuário de manutenção separado dos usuários das aplicações. O túnel exige conectividade da máquina ao endpoint e credenciais PostgreSQL; IAM/SSM não concede permissões SQL.

Exemplo PowerShell para manter o túnel aberto, substituindo o endpoint real:

```powershell
aws ssm start-session --profile rafael-admin --region us-east-1 --target $adminInstance --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters 'host=ENDPOINT_RDS,portNumber=5432,localPortNumber=15432'
```

A porta local é 15432; não configurar SSH no DBeaver. A conexão PostgreSQL, credenciais e validação TLS do certificado/hostname serão concluídas no runbook do RDS antes do primeiro uso. Não desabilitar a validação de certificado para contornar o endereço local do túnel. Esta etapa prepara o caminho, não afirma conectividade com um banco ainda inexistente.

Port forwarding não registra consultas nem conteúdo do túnel no log de sessão SSM. CloudTrail registra as chamadas de controle; isso não é auditoria SQL. Encerrar a sessão ao terminar. Uma interrupção Spot encerra a conexão e exige novo túnel quando a máquina estiver disponível; conferir o resultado da transação antes de repetir uma alteração.

## Encerramento

O bootstrap usa user_data_replace_on_change: alterações relevantes podem substituir a máquina e encerrar sessões. O pipeline pode cancelar a requisição Spot e terminar a instância somente em us-east-1, na conta configurada, com as três tags Project=fiapx, ManagedBy=terraform e Name=fiapx-administration. O Launch Template aplica essas tags à requisição Spot no lançamento; aws_instance sozinho não as propaga. Não remover as tags antes da substituição. A requisição inicial, criada antes desse template, recebeu as mesmas tags após conferência de vínculo com a instância administrativa.

O provider cancela primeiro a requisição Spot persistente e depois termina a instância. Isso evita que a requisição antiga permaneça ativa. A política de controle também permite DeleteDocument somente em fiapx-administration-shell para seu ciclo de recriação; não autoriza exclusão de documentos genéricos. Dados locais são descartáveis e devem ficar fora dessa máquina.

Interromper a máquina não remove seu volume ou os demais recursos do ambiente. No encerramento definitivo, planejar a remoção da requisição Spot persistente junto da instância, acesso EKS, profile/role, documento e SG. Não há destroy automático neste incremento; não armazenar dados que precisem sobreviver nessa máquina.

Referências: [sessões e port forwarding](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html), [documento de preferências](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-create-preferences-cli.html), [SSM Agent em AMIs](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html).

As tags do volume são gerenciadas por volume_tags, incluindo Name/Project/ManagedBy explicitamente. Não combinar esse campo com root_block_device.tags: a transição entre os dois mecanismos pode tentar remover tags de propriedade; a política bloqueia essa remoção. Plano administrativo final sem diferenças após a configuração convergir.
