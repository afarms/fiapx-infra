# Acesso público às APIs

Estado: implementação preparada, ainda sem apply/validação pública. A entrada usa um endereço HTTPS fornecido pelo CloudFront; não requer domínio próprio.

## Caminho da requisição

Navegador → CloudFront (HTTPS) → VPC origin → ALB interno (HTTP) → NodePort nos nós privados → Pods.

O trecho privado usa HTTP por decisão de arquitetura desta demonstração. EKS API e RDS permanecem privados; SSM continua necessário apenas para administração e CI/CD. O frontend HTML/JavaScript em S3 + CloudFront será entregue separadamente, com bucket próprio; este incremento prepara as APIs, não publica o site.

Terraform gerencia ALB, listener, regras, target groups e associação ao Auto Scaling Group dos nós. Auto Scaling registra/remove os nós Spot; Kubernetes, com externalTrafficPolicy Cluster, encaminha às réplicas Ready. Não há controller adicional, IP de Pod fixado ou lista manual de instâncias. Troca do próprio ASG exige novo apply para atualizar a associação.

Os manifests mantêm o Service interno na porta8080 e adicionam NodePort30081 (Identity) ou30082 (Video). O SG dos nós permite essas portas somente a partir do ALB, além da comunicação interna já existente. O SG do ALB aceita porta80 somente do SG gerenciado pelo CloudFront VPC origin. Processing permanece ClusterIP.

## Rotas e Swagger

Após o apply, consultar `terraform -chdir=terraform output public_api` para obter URLs reais:

| Destino | Caminho no endereço CloudFront |
| --- | --- |
| Identity | /api/identity/auth/register, /auth/login, /users/me e /admin/users sob o mesmo prefixo |
| Video | /api/video/videos e /api/video/videos/{id}/download |
| Swagger Identity | /api/identity/swagger-ui.html |
| Swagger Video | /api/video/swagger-ui.html |
| OpenAPI | /api/identity/v3/api-docs e /api/video/v3/api-docs |

Uma CloudFront Function remove o prefixo antes de encaminhar e substitui cabeçalhos de proxy fornecidos pelo cliente. Spring usa SERVER_FORWARD_HEADERS_STRATEGY=framework para reconstruir HTTPS/host/prefixo externos e os redirects do Swagger. Query strings, Authorization, Idempotency-Key e corpo são preservados.

A regra padrão do ALB devolve404; somente endpoints públicos conhecidos e documentos Swagger são encaminhados. /internal/*, /actuator/* e Processing não são publicados. Health checks do ALB usam readiness diretamente no NodePort, por rede privada. Administradores continuam sujeitos à autorização da API; nenhuma rota DELETE de conta foi adicionada.

## Upload, download e cache

Upload multipart continua pela API, até100.000.000 bytes de arquivo mais envelope. A aplicação mantém validação, dono, idempotência, confirmação durável e outbox. Download continua autenticado e em streaming, sem URL S3 pública/pré-assinada. API Gateway HTTP API não participa porque seu limite10MB conflita com o contrato.

Cache de APIs e cache de erros desabilitados; compressão de borda desabilitada. Todos os métodos necessários são encaminhados, mas apenas os implementados são aceitos pelas aplicações. CloudFront aguarda até60s pela resposta/entre pacotes de resposta; ALB idle timeout120s. Esses valores não são garantia de upload ilimitado em conexões lentas. Falha antes da resposta exige consultar/repetir com a mesma chave de idempotência. Ensaios de100MB, ZIP e interrupção pelo caminho real ainda são obrigatórios.

## Permissões e ordem de publicação

A role fiapx-infra-github-actions precisa de [public-api-policy.json](public-api-policy.json), além das políticas já existentes de rede/EKS. Substituir ACCOUNT_ID pela conta e EKS_CLUSTER_SECURITY_GROUP_ID pelo resultado de:

```bash
aws eks describe-cluster --name fiapx --region us-east-1 \
  --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text
```

Publicar como política gerenciada fiapx-public-api-provisioning e anexar à role antes de abrir o PR de infraestrutura (o workflow aplica no PR). O JSON contém permissões para ALB/TGs de nomes fiapx, associação ao ASG eks-fiapx-spot-*, função de borda de nome fixo, CloudFront com tags de propriedade e criação das service-linked roles. As regras de ingress do SG do cluster são limitadas ao ARN explicitamente preenchido. O Access Analyzer valida a sintaxe/ações; não substitui apply real.

1. Instalar a política revisada e verificar quota de políticas anexadas.
2. Publicar os manifests/configuração dos dois serviços e concluir o deploy; NodePorts não ficam públicos.
3. Publicar a infraestrutura. VPC origin/distribuição podem demorar vários minutos; targets precisam estar saudáveis.
4. Consultar o output, testar os dois Swaggers e isolamento de rotas, depois executar o fluxo funcional pelo endereço público.

Não imprimir Secrets ou valores de autenticação. Nenhum novo secret é necessário. Não existe URL final antes do apply.

## Validação e rollback

Validação local: make verify na infra inclui sintaxe JavaScript (Node.js necessário); kubeconform dos manifests; make verify nos serviços testa cabeçalhos reais do filtro Spring e redirects. Isso não comprova o comportamento do CloudFront/ALB implantados.

Depois do apply: conferir health dos target groups, HTTPS válido, redirects/assets/OpenAPI, Try it out, endpoints protegidos sem token, /internal e /actuator bloqueados, upload100MB e arquivo acima do limite, download íntegro e tentativa por outro dono.

Para rollback, primeiro retirar/desabilitar a entrada pública por Terraform, preservando o acesso privado. Retornar Services a ClusterIP somente após desvincular o tráfego do ALB. Remoção do VPC origin deve respeitar a desassociação da distribuição; não excluir manualmente o SG/ENI gerenciado pelo CloudFront. Não destruir cluster, banco, mídia ou backend como parte desse rollback.

## Referências

- [CloudFront VPC origins](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html).
- [Integração ALB e Auto Scaling](https://docs.aws.amazon.com/autoscaling/ec2/userguide/attach-load-balancer-asg.html).
- [Restrições de cabeçalhos nas funções de borda](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-function-restrictions-all.html).
- [Limite de HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html).
