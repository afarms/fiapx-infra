# Requisitos e rastreabilidade

Fonte: [enunciado original](../reference/enunciado.pdf), transcrição em [enunciado.md](../reference/enunciado.md).
Seção indicada na tabela; IDs abaixo são nossos, não IDs fornecidos pela FIAP.
Estado: entrega parcial. Identidade, upload, processamento, consultas, download e limpeza assíncrona implementados e integrados. Os três serviços foram implantados no EKS por CI/CD. Acesso público HTTPS, validação integrada na cloud, notificações, interface e exclusão distribuída permanecem pendentes.

| ID | Fonte | Necessidade | Área responsável | Evidência esperada |
| --- | --- | --- | --- | --- |
| RF-01 | Introdução | Enviar vídeo e baixar ZIP de imagens | Vídeos e processamento | Upload autenticado e ZIP com PNGs válidos |
| RF-02 | Funcionalidades essenciais | Processar mais de um vídeo simultaneamente | Processamento | Dois jobs sobrepostos e saídas independentes |
| RF-03 | Funcionalidades essenciais | Não perder requisição em picos | Vídeos e processamento | Aceite durável, recuperação e teste de pico/falha |
| RF-04 | Funcionalidades essenciais | Proteção por usuário e senha | Identidade | Login válido/inválido, acesso anônimo bloqueado |
| RF-05 | Funcionalidades essenciais | Listar status dos vídeos de um usuário | Vídeos | Listagem por dono, isolamento entre dois usuários |
| RF-06 | Funcionalidades essenciais | Possibilidade de notificação em erro | Lambda de notificações | Falha terminal gera e-mail para o dono do vídeo; envio, retentativas e DLQ demonstrados |
| RT-01 | Arquitetura e infraestrutura | Persistir dados | Persistência | Reinício preserva registros e arquivos duráveis |
| RT-02 | Arquitetura e infraestrutura | Arquitetura escalável | Processamento e infraestrutura | Replicar workers sem colisão de arquivos/jobs |
| RT-03 | Arquitetura e infraestrutura | Versionamento no GitHub | Entrega | URL real do repositório e histórico |
| RT-04 | Arquitetura e infraestrutura | Testes de qualidade | Todos os serviços | Relatórios de testes e cenários de falha |
| RT-05 | Arquitetura e infraestrutura | CI/CD | Entrega | Pipeline executado e entrega/deploy no alvo definido |
| AR-01 | Desafio | Desenho de arquitetura e microsserviços | Arquitetura e infraestrutura | Limites, responsabilidades, comunicação e diagramas |
| AR-02 | Desafio | Mensageria | Mensageria | Contrato de eventos e demonstração de consumo/recuperação |
| EN-01 | Entregáveis / documentação | Documentação da arquitetura | Entrega | Diagramas e ADRs coerentes com implementação |
| EN-02 | Entregáveis / documentação | Scripts de banco ou outros recursos | Arquitetura e infraestrutura | Liquibase SQL e infraestrutura reproduzível |
| EN-03 | Entregáveis / código | Link GitHub do(s) projeto(s) | Entrega | Link acessível conforme exigência da entrega |
| EN-04 | Apresentação | Vídeo de até 10 minutos: docs, arquitetura e sistema funcionando | Entrega | Roteiro, gravação e duração conferida |

## Interpretação e limites

RF-06 usa "pode ser notificado": planejar a capacidade de notificação de erro, sem afirmar que e-mail
é o único canal obrigatório. Decisão de 2026-09-28: e-mail por Lambda + SES, acionada por SQS; substitui a escolha anterior de avisos persistidos na interface. Implementar depois do fluxo principal na cloud. O enunciado não exige serviço Java dedicado, histórico de leitura ou aviso de sucesso.
"Mais de um vídeo" exige concorrência, mas o PDF não fornece volume, tamanho máximo, SLA ou retenção.
Esses valores serão decisões explícitas. "Não perder" precisa de contrato de aceite e testes de recuperação;
não significa aceitar carga infinita sem limite.

## Recomendações do PDF, não imposições de produto

Docker + Kubernetes **ou** Docker Compose; RabbitMQ/Kafka ou similar; PostgreSQL + Redis ou alternativa;
Prometheus + Grafana/ELK ou alternativa; GitHub Actions ou alternativa.
Redis, Kubernetes, Kafka e provedor cloud específico não são obrigatórios individualmente.
Java, Spring Boot, Mockito, Swagger e Liquibase são escolhas de implementação, não exigências do PDF.

## Evidência de implementação

RF-01, RF-04 e RF-05 possuem implementação nos serviços; RF-02/RF-03 possuem mecanismos de concorrência e recuperação, ainda sujeitos aos ensaios integrados na cloud. RT-01 e EN-02 possuem migrations Liquibase e persistência verificadas localmente. RT-04 possui testes unitários e de integração local; esses testes não comprovam o ambiente AWS completo. RT-03 e EN-03 possuem repositórios publicados para identidade, vídeos, processamento e infraestrutura. RT-05 possui CI, provisionamento Terraform e deploy real dos três serviços no EKS; os workflows concluíram publicação, túnel e rollout. Isso não comprova RF-01–03 ponta a ponta. Mídia, filas de trabalho/resultados, respectivas DLQs e permissões locais foram provisionadas pelo pipeline. RF-06 não está implementado. Relatórios são artefatos da CI; ver também o [runbook de validação de download](https://github.com/afarms/fiapx-video-service/blob/main/docs/download-validation.md).

Cada requisito deve ser validado com cenários verificáveis. Atualizar esta tabela com links a testes e evidências reais conforme entrega.
Não marcar um requisito como atendido só por existir um arquivo de documentação.

Mermaid é uma escolha de formato para os diagramas; o enunciado exige documentação da arquitetura, sem determinar essa ferramenta. PDF conferido por extração em 2026-09-19.


## Regras de produto (implementadas parcialmente)

- Cadastro público cria USER. USER consulta e altera somente seus dados; ADMIN gerencia usuários, promove papéis, inativa e exclui. Proteger o último ADMIN ativo. Administrador inicial criado por bootstrap idempotente com configuração secreta.
- Autenticação própria com JWT de 30 minutos, em memória, sem renovação automática. Reload exige login. APIs validam token e situação/permissões atuais da conta; verificação indisponível não autoriza acesso. Inativação e exclusão bloqueiam novas chamadas mesmo com token ainda válido.
- Inativação preserva cadastro; exclusão remove definitivamente conta e dados associados com cleanup assíncrono. A operação só termina após confirmação dos proprietários dos dados. Requisições já autorizadas e cópias baixadas não são revogadas retroativamente.
- Vídeos: MP4, AVI, MOV, MKV, WMV, FLV e WebM; até 100.000.000 bytes e 300 segundos. Validar mídia real, não apenas extensão. A base usa FFmpeg com fps=1 e produz PNGs em ZIP; essa é a referência de compatibilidade.
- Arquivos disponíveis por 24 horas após concluir o processamento. Expiração do download não transforma conclusão em falha. Exclusão de conta prevalece sobre a disponibilidade normal.
- Falha definitiva de processamento gera e-mail simples para o dono do vídeo, por SQS → Lambda → SES. Sem API de notificações, avisos de sucesso, preferências ou controle de leitura. Contrato, destinatário, tratamento de duplicatas e configuração do remetente serão detalhados antes da implementação; ver [decisão de simplificação](../architecture/adr/0002-email-notifications-cloud-first.md).

## Arquitetura alvo de infraestrutura

Três serviços em EKS (identidade, vídeos e processamento) e uma Lambda para e-mail. RDS PostgreSQL privado com bancos/credenciais distintos para os três serviços e acesso DBeaver via SSM; sem banco dedicado de avisos. Exatamente um secret AWS Secrets Manager para esta etapa. Terraform em repositório separado das aplicações, com backend em bucket S3 preexistente. Interface HTML/JavaScript em S3 + CloudFront; APIs autenticadas servem upload/download.

## Evidência da base

Na base fornecida, isValidVideoFile em main.go aceita sete extensões; o texto de erro menciona somente quatro. Não existe limite explícito de bytes ou duração nesse código. O enunciado não fixa esses limites; cinco minutos e 100 MB são regras do produto. Os dez minutos do enunciado referem-se ao vídeo de apresentação.

A inspeção da base foi documental; formatos, limites e cenários ainda precisam de teste na implementação. Retenção de metadados, arquivos de falhas e política de backup serão detalhadas na operação.
