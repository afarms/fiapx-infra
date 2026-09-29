# PostgreSQL privado e bootstrap

Status: implementação validada localmente, secret criado pelo operador e política do pipeline instalada. Plano revisado: um import, nove criações, uma atualização de metadados do secret e nenhuma destruição. RDS e bootstrap remoto aguardam o apply do pipeline. Os testes locais não comprovam TLS, regras de rede ou permissões efetivas durante a criação na AWS.

## Recursos e credenciais

RDS PostgreSQL 17.11, db.t4g.small, Single-AZ, 20 GiB gp3 criptografados, sem acesso público, backup automático de sete dias. O SG aceita TCP 5432 somente do SG dos nós EKS e da máquina administrativa. A saída administrativa usa referência ao SG do banco. O parâmetro `rds.force_ssl=1` exige TLS; o bootstrap usa `verify-full` e o bundle regional oficial da AWS.

| Banco | Usuário da aplicação |
| --- | --- |
| fiapx_identity | fiapx_identity |
| fiapx_video | fiapx_video |
| fiapx_processing | fiapx_processing |

`fiapx_admin` é o administrador de manutenção e bootstrap. Cada aplicação recebe apenas sua própria credencial; a implantação futura não deve montar o secret agregado inteiro nos Pods. Liquibase continua responsável pelas tabelas de cada serviço.

Um único secret, `fiapx/runtime`, contém `version=1`, `database.master`, `database.fiapx_identity`, `database.fiapx_video`, `database.fiapx_processing` (pares `username`/`password`), `jwt.private_key`, `jwt.public_key` e `identity_service_key`. As chaves JWT são RSA de 2048 bits em PEM. As credenciais são definidas pelo operador no console do Secrets Manager.

O bootstrap lê o secret existente em memória, confere propriedade e credenciais dos bancos e preserva seus valores. A criação do secret é manual; não há gerador de credenciais no repositório. Terraform importa os metadados por ARN e lê a senha mestre por recurso efêmero, consumido exclusivamente por `password_wo`. Não adicionar um data source convencional de secret version, outputs com valores ou `password` ao RDS. Não habilitar logs de debug do SDK/Terraform ao manipular credenciais. Ver [valores efêmeros](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/ephemeral).

## Preparação antes de abrir o PR

As senhas e a chave interna podem ser definidas pelo operador no console. O bootstrap exige strings não vazias, sem política própria de tamanho ou caracteres. A senha mestre continua sujeita às restrições do serviço RDS. O bootstrap utiliza libpq para gerar SCRAM com normalização compatível com PostgreSQL, incluindo Unicode; reexecuções preservam as credenciais escolhidas.

O workflow aplica durante o PR. Executar os passos abaixo antes da publicação:

1. Instalar dependências locais: Python 3.9 ou superior, OpenSSL, AWS CLI, Terraform e GNU Make. Criar um venv em `.local/database-venv` e instalar `scripts/database/requirements.txt`.
2. No console Secrets Manager em us-east-1, criar fiapx/runtime como Outro tipo de segredo, usando JSON em Texto simples com a estrutura descrita acima. Usar a chave aws/secretsmanager, descrição FIAP X database and application credentials e tags Project=fiapx e ManagedBy=terraform. Manter rotação automática desativada. Esse passo já foi realizado pelo operador neste ambiente.
3. Substituir `ACCOUNT_ID` em uma cópia local de [database-pipeline-policy.json](database-pipeline-policy.json). Validar com IAM Access Analyzer e instalar como `fiapx-database-provisioning`, anexada à role `fiapx-infra-github-actions`, preservando as políticas existentes. Conferir a quota de anexos. A política foi validada sem findings e instalada antes da publicação, totalizando oito políticas gerenciadas anexadas.
4. A política complementa criação/tagging/consulta de SG nas políticas EKS/rede, regras de SG e PutRolePolicy na role administrativa já concedidos. Adiciona RDS limitado aos nomes próprios, leitura/manutenção do secret próprio, documento SSM próprio e SendCommand apenas em instâncias administrativas tagueadas. `UpdateSecret` também permite atualizar valores pela API; o pipeline é uma identidade confiável e o código não usa essa capacidade para rotação. Exclusão de RDS e secret não é concedida.
5. Fazer um plan com backend remoto e confirmar somente os recursos novos esperados, import do secret e ausência de destruição. Não anexar planos/estado ao PR. Só então publicar e acompanhar apply, drift e bootstrap SSM.

O primeiro plan exige o secret existente. Não há valor padrão fictício nem criação de um segundo secret para contornar esse pré-requisito. A service-linked role do RDS pode ser criada pela permissão restrita a `rds.amazonaws.com`.

A leitura `DescribeDBInstances` do pipeline abrange `db:*` somente na conta e região us-east-1: o provider também consulta instâncias sem restringir a autorização ao ARN do nome fiapx-postgres. Criação e alteração continuam limitadas ao banco próprio. Essa permissão de consulta não concede conexão SQL ou acesso aos dados.

## Execução e validação

```bash
python3 -m venv .local/database-venv
.local/database-venv/bin/pip install -r scripts/database/requirements.txt
make verify PYTHON=.local/database-venv/bin/python

```

No Windows, usar `.local/database-venv/Scripts/python.exe` no parâmetro `PYTHON` e para executar o pip com `-m pip`. `make verify` executa fmt/init sem backend/validate e verificação de sintaxe Bash/Python. O repositório mantém apenas scripts operacionais; não contém suíte de testes auxiliares ou testes Terraform com mocks.

Depois do apply, `make bootstrap-database` lê do estado apenas instância/nome/versão do documento e executa `fiapx-database-bootstrap` via SSM. O documento instala dependências em `/opt/fiapx-database`, obtém o secret em memória com a role EC2 e valida conexão TLS, DDL e isolamento. O pipeline aguarda o resultado; uma falha impede o check de passar. Não imprime SQL, secret ou saída bruta do comando. Para diagnóstico, consultar o CommandId no SSM; corrigir IAM/rede/proprietário/schema conforme necessário, sem registrar valores.

O lock PostgreSQL serializa bootstraps. Não há DROP de banco, reset de dados ou ALTER PASSWORD em reexecuções. Roles elevadas, memberships inesperadas e proprietário diferente fazem o script falhar. Se um operador alterar a senha fora do fluxo, corrigir a divergência explicitamente; não excluir o secret para regenerá-lo. Uma rotação futura exige procedimento coordenado, atualização explícita de `password_wo_version` para o mestre e das senhas dos usuários, antes do rollout das aplicações.

A checagem de memberships cobre os dois sentidos: a role de aplicação não pode participar de outra role, e somente fiapx_admin pode ser membro dela. Grants para outros logins ou roles de grupo impedem o sucesso do bootstrap, inclusive quando o acesso seria obtido por SET ROLE. O script não revoga automaticamente concessões inesperadas; o operador deve revisar a origem delas.

Após provisionar, validar também acesso TLS a partir de um Pod na origem autorizada e bloqueio de uma origem sem SG permitido. Conferir private/encrypted, backups, ausência de valores no plano/estado e drift final. Essas evidências ainda estão pendentes.

## DBeaver por túnel SSM

Com AWS CLI e Session Manager plugin, obter o endpoint em `terraform -chdir=terraform output -json database` e a instância em `output -json administration`. Abrir no PowerShell, substituindo os identificadores:

```powershell
aws ssm start-session --profile rafael-admin --region us-east-1 --target INSTANCE_ID --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters 'host=["RDS_ENDPOINT"],portNumber=["5432"],localPortNumber=["15432"]'
```

Para preservar `sslmode=verify-full`, adicionar temporariamente no arquivo hosts local o mapeamento `127.0.0.1 RDS_ENDPOINT`. No DBeaver usar **RDS_ENDPOINT**, porta **15432**, banco escolhido, usuário **fiapx_admin** e senha obtida privadamente do Secrets Manager. Na configuração SSL usar `verify-full` e o certificado raiz [us-east-1-bundle.pem](https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem). O nome do certificado continua correspondendo ao endpoint; o host remoto é resolvido pela máquina SSM.

Encerrar o túnel e remover o mapeamento hosts após o uso. SSM port forwarding não registra o conteúdo SQL. Quem pode abrir sessão/comando na máquina pode acessar as credenciais administrativas; restringir esse acesso a operadores confiáveis. Interrupção Spot encerra sessões/túneis, mas não recria o RDS.

## Encerramento do ambiente

Sem destruição automática. RDS tem `deletion_protection` e `prevent_destroy`; secret tem `prevent_destroy` e janela de recuperação de sete dias. Após a demonstração, decidir retenção/exportação, interromper workloads, revisar um plano separado de encerramento e remover as proteções apenas nesse procedimento. A exclusão deve criar snapshot final; se `fiapx-postgres-final` já existir, definir um nome novo antes de executar. Snapshot e secret retidos continuam existindo após desligar computação.
