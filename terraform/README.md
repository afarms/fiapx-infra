# Organização Terraform

Este diretório é o módulo raiz do ambiente acadêmico FIAP X, executado pelo Makefile da raiz com -chdir=terraform. Todos os arquivos .tf deste diretório compõem a mesma configuração e o mesmo estado S3.

| Arquivo | Responsabilidade |
| --- | --- |
| backend.tf | Backend S3 e lock; bucket de state preexistente fora do ciclo da aplicação |
| terraform.tf | Versões fixadas do Terraform e do provider; lock file versionado |
| providers.tf | Região e tags comuns AWS |
| variables.tf | Entradas tipadas, descritas e validadas |
| outputs.tf | Saídas descritas; identificadores de conta sensíveis onde já previsto |
| network.tf / registry.tf | Rede da aplicação e registros ECR |
| eks.tf / eks-iam.tf | Cluster privado, nós Spot, add-ons e permissões |
| administration.tf / administration-iam.tf / bootstrap/ | Host privado SSM, acesso EKS, sessão com logs e bootstrap; provisionamento pendente |
| media.tf | Bucket privado de mídia e proteções |
| processing.tf / video-events.tf | Filas e DLQs por fluxo |
| video-local.tf / processing-local.tf | Roles temporárias de desenvolvimento; não são as futuras identidades dos Pods |

Os recursos ficam em arquivos por responsabilidade. Não há main.tf vazio nem módulos que apenas embrulham um recurso. Quando surgir reutilização, múltiplos ambientes ou necessidade de separar ciclos de vida, avaliar módulos/estados menores; hoje isso acrescentaria dependências e migração de estado sem benefício demonstrado. A configuração foi reorganizada sem mudar endereços de recursos, nomes de outputs, provider ou backend; somente as descrições de outputs foram complementadas. Não exige moved/import/state mv por esta reorganização.

Políticas de bootstrap em ../docs/operations são modelos operacionais para a identidade administrativa instalar no pipeline, não recursos autogeridos pelo próprio pipeline. Estado, planos, tfvars reais, credenciais e caches ficam fora do Git. Variáveis de ambiente e TF_DATA_DIR de validação não devem ser reaproveitadas para o backend remoto por acidente.

## Revisão da estrutura

Mantidos: um módulo raiz, arquivos por domínio, backend com lock, versões/lock fixados, fmt/validate e separação de credenciais. Ajustados: provider e versões antes misturados em media.tf/backend.tf; variáveis/outputs antes espalhados; descrições ausentes em outputs. Nenhum recurso adicional foi necessário por motivo de organização. O incremento de [EKS privado/Spot](../docs/operations/eks-runtime.md) segue a mesma organização; RDS e identidades das aplicações permanecem pendentes.

Essa organização segue as opções de [nomes e agrupamento lógico da HashiCorp](https://developer.hashicorp.com/terraform/language/style#file-names). A [estrutura de módulos reutilizáveis](https://developer.hashicorp.com/terraform/language/modules/develop/structure) é referência, não obrigação de transformar este repositório operacional em módulo publicado.

Validar pela raiz com make verify. A validação estática não comprova funcionamento AWS; ver [provisionamento de rede/ECR](../docs/operations/cloud-network-registry.md) para permissões e limitações.
