# Acesso público às APIs — planejamento

Estado: não implantado. Próxima entrega após o deploy dos três serviços. O acesso público deve permitir login, upload, consulta e download sem port-forward; administração do EKS e RDS continua via SSM.

## Restrições confirmadas

- Upload multipart de até 100.000.000 bytes de vídeo, mais envelope HTTP; download do ZIP em streaming pela API.
- Autenticação JWT e verificação atual da conta permanecem nos serviços.
- Expor apenas Identity e Video. Não publicar Processing, /internal/* ou Actuator.
- Swagger dos dois serviços precisa de rotas distintas, incluindo assets e OpenAPI, com Try it out apontando para a API correta.
- Sem cache de respostas autenticadas. Preservar Authorization, Content-Type, Idempotency-Key e Content-Disposition.
- Timeout, tamanho do corpo, redirects e cancelamento precisam de validação pela entrada real.
- Infraestrutura em Terraform; roteamento e bindings Kubernetes em manifests versionados, com proprietário único de cada recurso.

## Escolha da entrada

API Gateway HTTP API tem payload máximo de 10 MB, não ajustável. Portanto não atende o contrato atual de upload de 100 MB como entrada única. Aumentar o limite não é uma solução; migrar upload para URL pré-assinada mudaria o contrato e não está autorizado neste incremento.

Proposta com domínio disponível: ALB HTTPS com certificado ACM e DNS, encaminhando aos dois serviços. A escolha de controller/binding e permissões deve ser fechada antes do plan.

Alternativa sem domínio próprio: CloudFront com endereço HTTPS fornecido pela AWS e ALB privado como VPC origin. Validar suporte no provider fixado, políticas de métodos/headers/cache, timeouts e encaminhamento das rotas. Se o trecho privado CloudFront→ALB usar HTTP, documentar explicitamente; HTTPS no navegador não significa TLS em todos os saltos.

O responsável confirmou que não possui domínio próprio. A alternativa a detalhar na próxima etapa é CloudFront com endereço AWS e ALB privado; a implementação ainda não começou. Nenhum ALB, certificado ou distribuição foi criado nesta revisão.

## Aceite

URL HTTPS válida; cadastro/login e Swagger funcionais; acesso anônimo protegido e isolamento por dono; upload permitido até o limite e recusa acima dele; download íntegro; rotas internas bloqueadas; worker e banco privados. Registro de deploy não substitui ensaio funcional.

## Fontes

- [Quotas de HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html).
- [CloudFront VPC origins](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html).
