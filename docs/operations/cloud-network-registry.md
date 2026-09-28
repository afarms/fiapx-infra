# Rede e registros de imagens

Estado: configuração Terraform validada localmente; políticas adicionais de rede/ECR instaladas na role do pipeline e validadas pelo IAM Access Analyzer sem findings. Recursos de rede/ECR ainda não provisionados. O workflow existente aplica o plano, não executa somente validação.

## Recursos

- VPC dedicada 10.50.0.0/16, DNS habilitado, sem peering/VPN.
- Duas AZs, por padrão us-east-1a/us-east-1b; variável network_availability_zones exige duas zonas distintas da região. Conferir disponibilidade na conta antes do plan.
- Subnets públicas 10.50.0.0/24 e 10.50.1.0/24, privadas 10.50.10.0/24 e 10.50.11.0/24. Sem atribuição automática de IP público, inclusive nas públicas.
- Internet Gateway e rota pública; uma NAT com EIP na primeira subnet pública, utilizada pelas duas privadas. Uma falha nessa AZ/NAT afeta a saída de ambas: não é alta disponibilidade.
- Security group padrão sem ingress/egress; os futuros workloads precisarão de grupos próprios. Nenhuma aplicação ou banco exposto neste incremento.
- ECR privado para fiapx-identity-service, fiapx-video-service e fiapx-processing-service, com tags imutáveis, AES256, scan no push e force_delete=false. Nenhum registro de notificações, imagem enviada ou expiração automática de imagens de rollback.

Outputs: application_network fornece VPC e subnets por AZ; container_registries fornece URLs por serviço, marcado sensível para não imprimir o identificador da conta por padrão. Não contém credenciais.

## Validação e próximos passos

Executar make verify: formatação, validação Terraform, testes mock e testes do guard do PR. Se o diretório Terraform local já estiver associado ao backend remoto, usar TF_DATA_DIR apontando para um diretório local exclusivo de validação. Os mocks não criam recursos nem comprovam disponibilidade de AZ, quotas ou permissões IAM.

Antes do provisionamento: instalar políticas EC2/ECR abaixo, conferir AZs/quotas e plano sem destruição ou substituição de mídia/filas/roles existentes. O CIDR não é conectado a outras redes nesta etapa; qualquer futura conexão requer conferir sobreposição. EKS, RDS, ALB/HTTPS, secret, Pod Identity, imagens e deploy ficam nos incrementos seguintes.

## Permissões do pipeline

Preparadas duas políticas customer-managed adicionais, sem substituir as políticas existentes de state/mídia/SQS/roles locais. A separação evita somar todo o JSON à quota agregada de políticas inline da role. Cada documento cabe no limite individual de 6.144 caracteres sem whitespace.

| Documento | Nome sugerido | Escopo |
| --- | --- | --- |
| [network-pipeline-policy.json](network-pipeline-policy.json) | fiapx-network-provisioning | Leituras EC2 explícitas; criação/configuração de rede em us-east-1, conta indicada e tags Project=fiapx/ManagedBy=terraform |
| [registry-pipeline-policy.json](registry-pipeline-policy.json) | fiapx-registry-provisioning | Criar, consultar, taguear e configurar somente os três ECR privados dos serviços existentes |

Com a identidade administrativa já utilizada para bootstrap:

1. Em IAM → Policies → Create policy → JSON, inserir o primeiro documento. Substituir todas as ocorrências de ACCOUNT_ID pelo ID da conta, sem publicar a cópia preenchida.
2. Conferir a validação do editor e criar a política com o nome indicado. Repetir para o segundo documento.
3. Em IAM → Roles → fiapx-infra-github-actions → Add permissions → Attach policies, anexar ambas. Preservar confiança OIDC e políticas atuais; conferir quota de attachments antes de anexar.
4. Somente depois publicar o PR de rede/ECR. Se um run falhar por permissão, identificar ação/recurso e corrigir o escopo específico; não adicionar AdministratorAccess. O pipeline não recebe permissão para editar sua própria role.

Instalação das duas políticas concluída na role fiapx-infra-github-actions, preservando políticas e confiança existentes. Não foram alteradas permissões das roles locais de vídeos/processamento. Sem iam:PassRole, criação de instância/cluster/banco, push/pull de imagens ou exclusão de recursos. O encerramento do ambiente exigirá política revisada de remoção; não há destroy liberado por estes documentos.

### Limites e exceção de bootstrap

Leituras EC2 usam Resource=* porque as ações Describe utilizadas não são limitadas aos IDs consultados por uma condição de tag; continuam restritas a us-east-1. Isso permite ver metadados de outras redes da região. Escritas de criação exigem tags na requisição; recursos associados existentes (VPC, subnet, EIP) exigem tags de propriedade. São declarações separadas para evitar bloquear operações que autorizam mais de um recurso.

O security group padrão nasce automaticamente com a VPC e sem tags. No provider 6.14.1, o recurso aws_default_security_group aplica tags antes de revogar as regras. BootstrapDefaultGroupTags permite somente CreateTags em security-group da conta/região, com Project/ManagedBy/Name ausentes, e exige os três valores fiapx/terraform/fiapx-default-no-access. Não permite conceder ingress/egress. A revogação posterior exige esses três valores existentes.

**Limitação real:** esse primeiro tagging não consegue provar que o grupo pertence à VPC recém-criada; também alcança outro grupo sem essas três tags na mesma conta/região. O pipeline é uma identidade de provisionamento confiável, não uma barreira contra um mantenedor malicioso. Revisar o plano para que apenas o default SG da nova VPC seja adotado. Após o primeiro apply, restringir o Resource da exceção ao ARN exato do grupo, mantendo as demais condições, ou remover a exceção se não houver nova criação prevista. Não usar a exceção para adotar grupos de outros projetos. Alterar/remover tags de propriedade por MaintainOwnedTags é bloqueado.

### Referências e validação

- [Ações, recursos e condições EC2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html).
- [Ações e recursos ECR](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ecr.html).
- [Bootstrap do default security group no provider 6.14.1](https://github.com/hashicorp/terraform-provider-aws/blob/v6.14.1/internal/service/ec2/vpc_default_security_group.go).
- [Leituras auxiliares do recurso VPC no provider fixado](https://github.com/hashicorp/terraform-provider-aws/blob/v6.14.1/internal/service/ec2/vpc_.go).

make verify inclui checagens estáticas dos JSONs: ações explícitas, região, ARNs, limites de ECR, tags de propriedade, exceção restrita e tamanho de documento. Separadamente, os documentos preenchidos para a conta passaram no IAM Access Analyzer sem findings antes da instalação. Isso não é simulação IAM nem comprova execução real: permissões efetivas dependem também de SCP, permission boundary e políticas já anexadas. Apply remoto permanece pendente.

## Ambiente temporário

Execução para apresentação durante algumas semanas, no máximo um mês. Estimativa e medição financeira dispensadas por decisão do responsável. Planejar desativação ao final: parar Pods não remove NAT/EIP, cluster, banco, balanceadores ou registros. Definir retenção/exportação antes de remover dados. force_delete=false bloqueia remoção de repositórios com imagens; não alterar essa proteção silenciosamente. Estado Terraform e recursos existentes têm ciclo separado, sem destroy geral nesta tarefa.
