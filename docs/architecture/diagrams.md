# Diagramas de arquitetura

Desenho de referência, ainda não implantado integralmente. Os diagramas complementam a [visão integrada](consolidated.md) e os [contratos](integration.md). Região: us-east-1. Domínio/certificado, dimensionamento e parâmetros operacionais ainda precisam de definição. O alvo é três microsserviços no EKS e uma Lambda de e-mail. Notificação e exclusão distribuída são fluxos planejados, não implementados.

## Componentes e infraestrutura

A arquitetura aparece em duas visões complementares: **acesso à aplicação e dados**, seguida de **implantação e operação**. Isso separa as requisições do usuário das atividades administrativas. Elementos repetidos nas duas visões representam os mesmos recursos.

**Legenda:**
* roxo = acesso e frontend
* azul = microsserviços e execução
* verde = armazenamento
* amarelo = mensageria
* laranja = configuração e implantação
* cinza = operação e rede.

- As setas têm seu propósito indicado no rótulo.
- Ligações ao bloco EKS representam dependências do conjunto de serviços, não acesso de todos os Pods a todos os recursos.

### 1. Acesso à aplicação e dados

Leitura da esquerda para a direita: usuário, entrada HTTPS, aplicações e persistência. O S3 do frontend serve arquivos estáticos, enquanto o S3 de mídia guarda originais e ZIPs privados.

```mermaid
flowchart LR
    USER["Navegador<br/>HTML e JavaScript"] -->|HTTPS| CF["CloudFront"]
    CF -->|"Frontend privado via OAC"| WEB[("S3<br/>Frontend")]
    CF -->|"/api/* sem cache"| ALB["ALB<br/>Origem HTTPS"]

    subgraph EKS["Amazon EKS - três microsserviços"]
        direction TB
        ID["Identidade<br/>Usuários, JWT e permissões"]
        VID["Vídeos<br/>Upload, status e download"]
        PROC["Processamento<br/>FFmpeg e ZIP<br/>Sem API pública de negócio"]
    end

    ALB -->|"APIs de identidade e vídeos"| EKS
    EKS -->|"Cada serviço acessa seu banco"| DB[("RDS PostgreSQL privado<br/>Uma instância, três bancos<br/>Identidade · Vídeos · Processamento")]
    EKS <-->|"Vídeos e processamento: objetos"| MEDIA[("S3 privado<br/>Originais e ZIPs")]
    EKS <-->|"Publicação e consumo por serviço"| QUEUES["SQS<br/>5 filas funcionais + 5 DLQs"]
    QUEUES -->|"Falha definitiva"| NOTIF["Lambda de e-mail"]
    NOTIF -->|"Solicita envio"| SES["SES"]
    SES -->|"E-mail de erro"| OWNER["Dono do vídeo"]

    classDef access fill:#F3E8FF,stroke:#7E22CE,color:#3B0764,stroke-width:2px
    classDef service fill:#DBEAFE,stroke:#1D4ED8,color:#172554,stroke-width:2px
    classDef storage fill:#DCFCE7,stroke:#15803D,color:#14532D,stroke-width:2px
    classDef queue fill:#FEF3C7,stroke:#B45309,color:#451A03,stroke-width:2px
    class USER,CF,ALB,OWNER access
    class ID,VID,NOTIF,PROC,SES service
    class WEB,DB,MEDIA storage
    class QUEUES queue
    style EKS fill:#EFF6FF,stroke:#1D4ED8,stroke-width:2px,color:#172554
```

**Conexões internas omitidas para legibilidade:** vídeos e processamento consultam identidade conforme seus contratos. A obtenção segura do destinatário da Lambda ainda será definida. ALB encaminha rotas aos serviços HTTP, sem expor o worker ou criar uma API de notificações. O detalhamento das filas aparece abaixo; apenas trabalho e resultados estão provisionados no estado atual.

**Limites de rede:** ALB fica na camada de entrada da VPC, workloads e RDS na camada privada. CloudFront, S3 e SQS são serviços AWS representados fora do bloco EKS, não Pods. O desenho é lógico e não representa subnets ou AZs em escala. A origem HTTPS do ALB requer domínio/certificado válido.

### 2. Implantação e operação

Cada linha mostra uma responsabilidade operacional. As referências ao EKS e ao RDS apontam para os mesmos recursos da visão anterior. As setas de Terraform indicam gestão de infraestrutura, não requisições de negócio.

```mermaid
flowchart LR
    subgraph PROVISION["A. Provisionamento"]
        direction LR
        TF["Terraform<br/>fiapx-infra"] -->|"State e lock"| STATE[("S3 preexistente<br/>tfstate")]
        TF -->|"Provisiona recursos declarados"| AWSRES["Infraestrutura AWS<br/>Rede, EKS, RDS, SQS, S3<br/>CloudFront, ECR, secret, IAM<br/>Lambda e SES ao final"]
    end

    subgraph RELEASE["B. Implantação dos serviços"]
        direction LR
        ECR["ECR<br/>Imagens por serviço"] -->|"Imagem por digest"| DEPLOY["Etapa restrita<br/>de implantação"]
        SECRET["Secrets Manager<br/>UM único secret"] -->|"Configuração por serviço"| DEPLOY
        DEPLOY -->|"Deployments e configuração dos Pods"| RUNTIME["EKS<br/>Serviços em execução"]
    end

    subgraph MAINTENANCE["C. Manutenção do banco"]
        direction LR
        DBA["DBeaver local"] -->|"Túnel SSM"| JUMP["EC2 gerenciada<br/>por Systems Manager"]
        JUMP -->|"Conexão SQL de manutenção"| DBREF[("RDS privado<br/>Credencial de manutenção")]
    end

    subgraph MONITOR["D. Observabilidade"]
        direction LR
        SOURCES["EKS e SQS"] -->|"Logs e métricas"| CW["CloudWatch<br/>Dashboards e alarmes"]
    end

    subgraph NETWORK["E. Saída de rede"]
        direction LR
        PRIVATE["Workloads privados"] -->|"Saída da VPC"| NAT["NAT<br/>Referência inicial"]
        NAT -->|"HTTPS"| APIS["APIs dos serviços AWS"]
    end

    classDef service fill:#DBEAFE,stroke:#1D4ED8,color:#172554,stroke-width:2px
    classDef storage fill:#DCFCE7,stroke:#15803D,color:#14532D,stroke-width:2px
    classDef deployment fill:#FFEDD5,stroke:#C2410C,color:#431407,stroke-width:2px
    classDef operation fill:#F1F5F9,stroke:#475569,color:#0F172A,stroke-width:2px
    class TF,AWSRES,ECR,SECRET,DEPLOY deployment
    class RUNTIME,PRIVATE service
    class STATE,DBREF storage
    class DBA,JUMP,SOURCES,CW,NAT,APIS operation
    style PROVISION fill:#FFF7ED,stroke:#FDBA74,color:#431407
    style RELEASE fill:#FFF7ED,stroke:#FDBA74,color:#431407
    style MAINTENANCE fill:#F8FAFC,stroke:#CBD5E1,color:#0F172A
    style MONITOR fill:#F8FAFC,stroke:#CBD5E1,color:#0F172A
    style NETWORK fill:#F8FAFC,stroke:#CBD5E1,color:#0F172A
```

O bucket de estado já existe e fica fora do ciclo de destruição da aplicação. Recursos criados por controllers Kubernetes, como o ALB, mantêm sua propriedade definida na infraestrutura, sem gerenciamento concorrente pelo Terraform.

As configurações entregues aos Pods não criam novos secrets no AWS Secrets Manager. Cada serviço recebe sua configuração, enquanto a credencial de manutenção fica separada. A referência inicial de NAT único e RDS Single-AZ não demonstra alta disponibilidade. Rotas, endpoints e dimensionamento serão detalhados na implantação.

## Mensageria por fluxo

Os três diagramas abaixo mostram os fluxos separadamente. Nomes de fila repetidos representam a mesma fila física, não filas adicionais. Etapas repetidas do serviço de vídeos ou identidade também representam o mesmo microsserviço em momentos diferentes.

**Legenda:**
* azul = ação de um microsserviço
* amarelo = fila SQS
* verde = resultado do fluxo
* roxo = interface.

- Setas contínuas mostram publicação, consumo ou progressão interna conforme o rótulo.
- Seta pontilhada representa consulta HTTP, não mensagem SQS.
- Os textos identificam o papel dos elementos mesmo sem as cores.

**DLQs:** cada uma das cinco filas funcionais possui sua própria DLQ. Elas foram omitidas das setas para destacar os fluxos de negócio. Mensagens que excedem a política de recebimentos seguem para a DLQ correspondente, com alarme, análise e reprocessamento controlado. Ir para a DLQ não atualiza automaticamente o status do vídeo nem conclui uma exclusão.

### 1. Processamento do vídeo

Começa após o aceite durável do vídeo. O processamento informa início, conclusão ou falha e o serviço de vídeos atualiza o estado público do trabalho.

```mermaid
flowchart LR
    V1["Vídeos<br/>Solicita processamento"] -->|VideoProcessingRequested| QW["SQS<br/>processing-work"]
    QW -->|Consome trabalho| P["Processamento<br/>Valida mídia e gera ZIP"]
    P -->|ProcessingStarted / ProcessingCompleted / ProcessingFailed| QV["SQS<br/>videos-events"]
    QV -->|Consome evento| V2["Vídeos<br/>Atualiza status do trabalho"]

    classDef service fill:#DBEAFE,stroke:#1D4ED8,color:#172554,stroke-width:2px
    classDef queue fill:#FEF3C7,stroke:#B45309,color:#451A03,stroke-width:2px
    classDef result fill:#DCFCE7,stroke:#15803D,color:#14532D,stroke-width:2px
    class V1,P service
    class QW,QV queue
    class V2 result
```

DLQs deste fluxo: `processing-work` e `videos-events` possuem destinos de falha próprios. O verde indica o resultado do fluxo de mensagens, não necessariamente sucesso do processamento: o status também pode ser FAILED.

### 2. Notificação de falha

Planejado para depois do fluxo principal na cloud. Começa quando vídeos registra uma falha definitiva e outbox; a Lambda envia e-mail ao dono. Contrato, destinatário e política de duplicatas ainda serão detalhados.

```mermaid
flowchart LR
    V["Vídeos<br/>Registra FAILED e outbox de aviso"] -->|VideoFailed| QN["SQS<br/>notifications-events"]
    QN -->|Consome evento| N["Lambda<br/>Envia e-mail de erro"]
    N -->|Solicita envio| SES["SES"]
    SES -->|E-mail| OWNER["Dono do vídeo"]

    classDef service fill:#DBEAFE,stroke:#1D4ED8,color:#172554,stroke-width:2px
    classDef queue fill:#FEF3C7,stroke:#B45309,color:#451A03,stroke-width:2px
    classDef result fill:#DCFCE7,stroke:#15803D,color:#14532D,stroke-width:2px
    classDef ui fill:#F3E8FF,stroke:#7E22CE,color:#3B0764,stroke-width:2px
    class V service
    class QN queue
    class N,SES result
    class OWNER ui
```

A fila `notifications-events` terá DLQ própria e retentativas limitadas. Sem consulta de avisos pelo navegador ou banco de notificações. Falha no envio não reinicia o vídeo. Envio externo e confirmação do consumo não são uma transação única; não se promete exatamente um e-mail.

### 3. Exclusão definitiva de usuário

Identidade bloqueia a conta e solicita limpeza a vídeos e processamento. A exclusão só termina após as confirmações dos proprietários. A antiga limpeza do banco de avisos foi removida; a política de e-mails pendentes após exclusão ainda precisa de definição antes de implementar este fluxo.

```mermaid
flowchart TB
    I["Identidade<br/>Bloqueia conta e solicita exclusão"] -->|UserDeletionRequested| QC["SQS<br/>processing-control"]
    I -->|UserDeletionRequested| QV["SQS<br/>videos-events"]

    QC -->|Consome solicitação| P["Processamento<br/>Encerra execuções e limpa dados"]
    QV -->|Consome solicitação| V["Vídeos<br/>Remove arquivos e registros"]

    P -->|UserDataDeleted: processamento| QI["SQS<br/>identity-events"]
    V -->|UserDataDeleted: vídeos| QI

    QI -->|Consome confirmações| WAIT["Identidade<br/>Aguarda vídeos e processamento"]
    WAIT -->|Somente após todas as confirmações| DONE["Identidade<br/>Remove perfil e credenciais<br/>Conclui exclusão"]

    classDef service fill:#DBEAFE,stroke:#1D4ED8,color:#172554,stroke-width:2px
    classDef queue fill:#FEF3C7,stroke:#B45309,color:#451A03,stroke-width:2px
    classDef result fill:#DCFCE7,stroke:#15803D,color:#14532D,stroke-width:2px
    class I,P,V,WAIT service
    class QC,QV,QI queue
    class DONE result
```

Cada fila representada possui DLQ própria. Se uma solicitação ou confirmação falhar, a exclusão permanece pendente e a conta continua bloqueada. Cada serviço confirma somente após reconciliar escritas e execuções concorrentes, evitando que um trabalho atrasado recrie dados já removidos.

Publicações usam outbox por destino, consumo de domínio usa inbox e efeito transacional idempotente. Réplicas compartilham sua fila. SQS Standard pode duplicar e reordenar mensagens, tentativa e versão impedem regressão do estado. O alvo mantém cinco filas funcionais e cinco DLQs, com notificações dedicada somente a e-mail; isso não representa cinco filas já provisionadas.

## Upload, processamento e download

```mermaid
sequenceDiagram
    actor U as Usuario
    participant V as API Videos
    participant I as Identidade
    participant S as S3 privado
    participant D as Banco Videos
    participant Q as SQS
    participant P as Processamento
    participant DP as Banco Processamento
    participant N as Lambda Email
    participant SES as SES
    U->>I: Cadastro ou login
    I-->>U: JWT de 30 minutos
    U->>V: Upload autenticado + Idempotency-Key
    V->>I: Verificar conta e permissoes atuais
    I-->>V: Conta ativa
    V->>S: Streaming do original, limite 100 MB
    S-->>V: Objeto persistido
    V->>D: Transacao QUEUED + outbox
    D-->>V: Commit
    V-->>U: 202 com videoId
    V->>Q: Outbox publica trabalho
    Q->>P: Entrega pelo menos uma vez
    P->>I: Verificar autorizacao da execucao
    P->>DP: Assumir tentativa com lease
    P->>S: Ler original
    Note over P,Q: Renovar lease e visibilidade enquanto executa
    P->>P: Validar midia e duracao, extrair PNGs
    alt Processamento concluido
        P->>S: Persistir ZIP
        P->>DP: Resultado + outbox em transacao
    else Falha terminal ou midia invalida
        P->>DP: Falha + outbox em transacao
    end
    P->>Q: Excluir mensagem apos commit duravel
    P->>Q: Publicar resultado pela outbox
    Q->>V: Resultado na videos-events
    V->>D: Inbox + estado + eventual outbox de aviso
    opt Resultado FAILED
        V->>Q: Publicar VideoFailed
        Q->>N: Entregar aviso
        N->>SES: Solicitar envio de email ao dono
        Note over N,SES: Contrato e duplicatas ainda a detalhar
    end
    U->>V: Consultar status ou baixar ZIP
    V->>I: Revalidar conta e permissoes
    Note over V: Conferir dono, COMPLETED e expiresAt
    V->>S: Ler ZIP autorizado
    V-->>U: Streaming do download
```

O caminho final de download aplica-se apenas a resultado concluído e não expirado, demais estados produzem resposta de erro apropriada. Duração e conteúdo são verificados após aceite durável: 202 não garante mídia válida. Consultas protegidas falham se a situação da conta não puder ser verificada. Início do processamento também é publicado com tentativa/versão, esse evento foi omitido da sequência para legibilidade.

## Exclusão definitiva de usuário

```mermaid
sequenceDiagram
    actor A as Admin
    participant I as Identidade
    participant DI as Banco Identidade
    participant Q as SQS
    participant P as Processamento
    participant V as Videos
    A->>I: DELETE usuario
    I->>I: Validar ADMIN e proteger ultimo ADMIN
    I->>DI: Bloqueio + operacao + outbox por destino
    DI-->>I: Commit
    I-->>A: 202 com deletionId
    Note over I: Novas chamadas protegidas sao negadas
    I->>Q: Publicar exclusao para videos e processamento
    par Encerrar processamento
        Q->>P: UserDeletionRequested
        P->>P: Bloquear owner, encerrar execucoes, limpar
        P->>Q: Confirmacao duravel por outbox
    and Limpar videos
        Q->>V: UserDeletionRequested
        V->>V: Bloquear owner, reconciliar produtores e objetos
        Note over V,P: Confirmar limpeza apenas apos encerrar produtores conhecidos
        V->>Q: Confirmacao duravel por outbox
    end
    Q->>I: Confirmacoes em identity-events
    I->>DI: Registrar participantes concluidos
    alt Todos confirmaram
        I->>DI: Remover perfil e credenciais, concluir operacao
    else Falha ou confirmacao ausente
        Note over I,Q: Operacao pendente, retry, DLQ e reconciliacao
    end
    A->>I: Consultar deletionId
    I-->>A: Estado da operacao
```

Marcadores técnicos mínimos impedem recriação por mensagens antigas, não conservam o perfil excluído. Confirmação de limpeza considera concorrência com uploads e workers. Backups expiram pela política operacional e restauração reaplica exclusões. A conta não volta a ter acesso se uma etapa falhar.
