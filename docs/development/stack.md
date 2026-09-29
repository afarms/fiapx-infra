# Stack e política de versões

Estado: identidade, upload, processamento, consultas, download e limpeza implementados e integrados. Backend, mídia, filas trabalho/resultados, DLQs e roles locais provisionados. Deploy dos três serviços no EKS concluído; acesso público e validação integrada na cloud pendentes; notificação por e-mail será implementada ao final.

| Item | Decisão / estado |
| --- | --- |
| Java | 21 |
| Spring Boot | 4.1.1, utilizada nos builds dos serviços |
| Maven | Wrapper 3.9.16; scripts executados pelo Makefile com Git Bash no Windows |
| PostgreSQL | 17; Compose usa postgres:17.11-alpine3.24; RDS privado PostgreSQL17.11 provisionado em us-east-1 |
| Persistência | Liquibase SQL; JPA/Hibernate na infraestrutura; ddl-auto=validate, open-in-view=false |
| Arquitetura | Clean Architecture, core sem Spring/JPA; gateways no core; beans próprios centralizados em BeanConfig |
| Testes | JUnit/Mockito; JaCoCo com gate de 90% em linhas e branches; core compilado isoladamente |
| OpenAPI | springdoc 3.1.1; Swagger e documentação HTTP validados localmente |
| Containers | Rancher Desktop/Moby; imagens multi-stage JDK → JRE Alpine 21.0.12_8, usuário não-root |
| Terraform | 1.14.7; provider AWS 6.14.1 fixado; backend S3 com locking nativo, mídia configurada e validação estática |
| GitHub Actions | Serviços com CI própria; infraestrutura com workflow único de validação/plan/apply no PR; OIDC sem chaves permanentes |
| AWS | us-east-1; EKS com dois nós Spot Ready, RDS privado e acesso SSM provisionados; TLS EKS → RDS validado |
| Secrets Manager | fiapx/runtime criado; credenciais SQL distintas; deploy projeta somente os campos próprios em Secrets Kubernetes; rotação explícita |
| Mensageria | Trabalho/DLQ Standard definidos em Terraform: retenção 4/14 dias, maxReceiveCount 5, visibilidade 120 s; fila de resultados/DLQ também provisionada; notificações e controle de exclusão planejados |
| Arquivos | S3 privado de mídia provisionado; upload, download e limpeza implementados |
| Autenticação | Serviço próprio, BCrypt, JWT RS256 de 30 minutos, verificação de conta/versão a cada consulta protegida; sem renovação automática |
| Processamento | FFmpeg empacotado no worker; implementação e testes locais concluídos, validação integrada AWS pendente |
| Frontend | HTML/JavaScript em S3 + CloudFront planejado; JWT em memória |
| Notificações | SQS → Lambda → SES, somente e-mail de falha definitiva; runtime/contrato a definir; sem serviço Java, API ou banco de avisos |
| Observabilidade | Probes HTTP disponíveis; ferramentas e arquitetura de observabilidade cloud a definir |

## Persistência e composição

Migrations de cada serviço ficam em src/main/resources/db/changelog/changes/*.sql, listadas por changelog raiz. Changesets aplicados são imutáveis. Hibernate valida o schema; a aplicação não cria tabelas via ddl-auto=update.

Domain/gateways/use cases permanecem no core. Entity, mapper, adapter e repository pertencem à infraestrutura. Spring Data fornece os repositórios; BeanConfig compõe os adapters e demais beans próprios. Não há acesso cruzado aos bancos dos serviços.

## Build e testes

Executar `make verify` no repositório correspondente. Nos serviços Java, compila, testa, empacota e verifica cobertura; na infraestrutura, verifica formatação e configuração Terraform sem inicializar o backend remoto. `make install` dos serviços também instala o artefato no cache Maven local.

CI dos serviços executa unit-tests e, após sucesso, container-build e validação de manifests k8s/. Push/main publica ECR com SHA completo e aplica os YAMLs por kubectl no runner GitHub, usando digest e túnel SSM para a API privada. HPA usa CPU via Metrics Server; Deployment não declara replicas. Ativação e rollout real concluídos nos três serviços; ensaios integrados ainda pendentes. Dockerfile usa package -DskipTests; a imagem final contém JRE e aplicação. Actions de infraestrutura são fixadas por SHA.

Integração local de banco, migrations e identidade/vídeos foi exercitada, mas não constitui suíte E2E automatizada na CI. Mensageria, FFmpeg e fluxo completo com S3 ainda precisam de validação. Mocks não comprovam esses contratos reais.

## Referências

- [Spring Boot](https://docs.spring.io/spring-boot/system-requirements.html).
- [Dependências gerenciadas](https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html).
- [Springdoc](https://springdoc.org/).
- [Backend S3 Terraform](https://developer.hashicorp.com/terraform/language/backend/s3).
