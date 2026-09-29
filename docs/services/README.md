# Serviços e repositórios

| Projeto | Responsabilidade | Situação |
| --- | --- | --- |
| [fiapx-video-service](https://github.com/afarms/fiapx-video-service) | Upload, metadados, status, download e limpeza | Implementados e integrados; validação integrada na cloud pendente |
| [fiapx-identity-service](https://github.com/afarms/fiapx-identity-service) | Contas, JWT e autorização atual | Cadastro, login, perfil, credenciais, administração, testes e CI implementados; exclusão distribuída pendente |
| [fiapx-processing-service](https://github.com/afarms/fiapx-processing-service) | Validação da mídia, extração e ZIP | Implementado e integrado; validação integrada na cloud pendente |
| Lambda de notificações (repositório a definir) | E-mail de falha definitiva via SQS/SES | Planejada para depois do fluxo principal na AWS; substitui o serviço Java de avisos |
| [fiapx-infra](https://github.com/afarms/fiapx-infra) | Terraform e documentação integrada | Backend, mídia, filas trabalho/resultados, DLQs e roles locais provisionados; rede/ECR/EKS/RDS e deploy dos três serviços concluídos; acesso público pendente |
| fiapx-web | HTML/JavaScript estático | Planejado |

Três microsserviços no EKS, uma função de e-mail, um projeto de infraestrutura e um frontend. Serviços existentes em repositórios separados, sem build agregador. A função não terá banco de avisos nem endpoint HTTP. Nomes sem links não pressupõem repositórios publicados.

Contratos executáveis ficam nos serviços proprietários. Este catálogo descreve a integração sem duplicar schemas editáveis. Infraestrutura cloud é responsabilidade deste projeto; build, migrations e deployment de cada aplicação pertencem ao serviço correspondente. Os três deployments estão no EKS; a validação ponta a ponta será realizada pela entrada pública.
