# Serviços e repositórios

| Projeto | Responsabilidade | Situação |
| --- | --- | --- |
| [fiapx-video-service](https://github.com/afarms/fiapx-video-service) | Upload, metadados, status e download | Modelo, Liquibase/JPA, consultas HTTP autenticadas, Swagger, testes e CI implementados; upload/download pendentes |
| [fiapx-identity-service](https://github.com/afarms/fiapx-identity-service) | Contas, JWT e autorização atual | Cadastro, login, perfil, credenciais, administração, testes e CI implementados; exclusão distribuída pendente |
| fiapx-processing-service | Validação da mídia, extração e ZIP | Planejado |
| fiapx-notification-service | Avisos persistidos na interface | Planejado |
| [fiapx-infra](https://github.com/afarms/fiapx-infra) | Terraform e documentação integrada | Backend configurado, CI e workflows manuais; OIDC validado, teste remoto do backend pendente |
| fiapx-web | HTML/JavaScript estático | Planejado |

Quatro microsserviços, um projeto de infraestrutura e um frontend. Um domínio por repositório, sem build agregador. Nomes sem links correspondem a projetos ainda planejados; não pressupõem repositórios publicados.

Contratos executáveis ficam nos serviços proprietários. Este catálogo descreve a integração sem duplicar schemas editáveis. Infraestrutura cloud é responsabilidade deste projeto; build, migrations e deployment de cada aplicação pertencem ao serviço correspondente. Ainda não há deployment das aplicações no EKS.
