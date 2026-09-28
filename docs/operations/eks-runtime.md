# Runtime EKS privado

Status: configuração implementada e validada localmente; cluster ainda não provisionado. Rede e ECR já provisionados. O acesso administrativo via SSM, RDS e secret permanecem nos próximos incrementos. As [permissões do pipeline](eks-pipeline-permissions.md) foram instaladas após a primeira falha de apply.

O cluster usa Kubernetes 1.35, endpoint somente privado e managed node group com capacidade desejada de dois nós Spot nas subnets privadas. Os tipos m6i.large, m6a.large e m5.large ampliam as opções de capacidade x86. Spot pode sofrer interrupção ou indisponibilidade; duas subnets não garantem um nó em cada zona. O reparo automático está habilitado.

A AMI AL2023 e as versões dos add-ons estão fixadas em terraform/eks.tf. Pod Identity Agent e VPC CNI precedem o node group; CoreDNS e kube-proxy dependem dele. A role do CNI é separada da role dos nós, limitada à identidade kube-system/aws-node deste cluster. As identidades das aplicações serão configuradas na etapa de deploy dos serviços.

Cada nó tem disco gp3 criptografado de 50 GiB, descartado com a instância, e IMDSv2 obrigatório. O armazenamento temporário não oferece retomada de processamento após interrupção. O EKS controla o security group e o instance profile dos nós. Não há acesso SSH configurado.

O acesso humano ao Kubernetes usa uma entrada IAM explícita; o criador do cluster não recebe administração automaticamente. A API privada dependerá da máquina administrativa SSM. O mesmo caminho permitirá túnel do DBeaver para o futuro RDS privado, com credenciais próprias do banco para consultas e manutenção. Nenhum acesso ao banco está disponível por esta configuração isolada.

Logs do control plane, incluindo auditoria, têm retenção de sete dias. A proteção contra exclusão está habilitada e deverá ser tratada explicitamente no encerramento do ambiente temporário.

## Validação e implantação

`make verify` valida formatação, configuração e proteção de revisão de PR. A validação estática não demonstra capacidade Spot, inicialização dos nós ou funcionamento dos add-ons. Após provisionar, verificar cluster ACTIVE, nós Ready, add-ons ACTIVE e acesso pela rede privada.

O workflow aplica infraestrutura durante o PR. Permissões EKS e sessão de duas horas foram preparadas; a execução remota deve confirmar a convergência. SSM e banco/configuração seguem pendentes e não impedem a criação desta base EKS.

Referências: [managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html), [roles dos nós](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html) e [launch templates](https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html).
