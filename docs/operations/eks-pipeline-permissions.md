# Permissões de provisionamento do EKS

O pipeline precisa de permissões adicionais às de rede/ECR. A primeira execução do runtime falhou na criação de roles, log group, security group e launch template. Reexecutar sem instalar estas políticas repete o erro.

Instalar como políticas customer-managed na role `fiapx-infra-github-actions`, usando uma identidade administrativa e substituindo `ACCOUNT_ID` na cópia local:

| Documento | Nome da política | Escopo |
| --- | --- | --- |
| [eks-iam-pipeline-policy.json](eks-iam-pipeline-policy.json) | fiapx-eks-iam-provisioning | Três roles EKS, anexos limitados às respectivas políticas AWS e PassRole limitado aos serviços necessários |
| [eks-control-pipeline-policy.json](eks-control-pipeline-policy.json) | fiapx-eks-control-provisioning | Cluster fiapx, node group fiapx-spot, add-ons, Pod Identity e acesso explícito do administrador |
| [eks-compute-pipeline-policy.json](eks-compute-pipeline-policy.json) | fiapx-eks-compute-provisioning | Launch template e security group com tags do projeto; log group /aws/eks/fiapx/cluster |

Preservar todas as políticas existentes, em especial a restrição pós-bootstrap do security group padrão na política de rede. Os três documentos passam separadamente no limite de tamanho de políticas gerenciadas. Não concedem edição da role do pipeline, AdministratorAccess, execução EC2 direta ou destroy geral.

`eks:CreateCluster` exige Resource=* por limitação da API de autorização; a declaração exige região us-east-1, tags de projeto, endpoint privado e ausência de administração automática do criador. Operações posteriores usam ARNs do cluster fiapx. Leituras EC2/Logs e compatibilidade de add-ons que não suportam escopo por recurso também usam Resource=*, limitadas à região. A identidade do pipeline é confiável para provisionar; essas permissões não substituem revisão do plano.

Pré-requisitos administrativos já conferidos nesta conta: AWSServiceRoleForAmazonEKS, AWSServiceRoleForAmazonEKSNodegroup e AWSServiceRoleForEC2Spot existem. Em outra conta, criar as service-linked roles antes da execução; o pipeline não recebe criação genérica de roles de serviço.

Configurar `MaxSessionDuration=7200` na role do pipeline antes de publicar o workflow com sessão OIDC de 7200 segundos e timeout de 110 minutos. Isso evita expiração durante criação sequencial de cluster, nós e add-ons. A confiança OIDC permanece inalterada.

Validar os documentos preenchidos com IAM Access Analyzer antes de anexar. Depois executar make verify e publicar no mesmo PR; acompanhar plan/apply/drift. Uma falha parcial não exige apagar recursos: Terraform retoma os recursos registrados no estado. Conferir eventuais recursos criados fora do estado antes de importar ou repetir criação.

Referências: [autorização EKS](https://docs.aws.amazon.com/service-authorization/latest/reference/list_eks.html), [autorização EC2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html).

Instalação nesta conta: três políticas validadas no Access Analyzer sem findings e anexadas à role do pipeline; MaxSessionDuration confirmado em 7200. Políticas anteriores e confiança OIDC preservadas. Validação local make verify aprovada. Resultado remoto ainda depende da nova execução do PR.
