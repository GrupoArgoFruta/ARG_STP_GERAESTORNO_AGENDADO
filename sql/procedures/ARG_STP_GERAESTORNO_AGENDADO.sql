-- ============================================================================
-- Rotina AGENDADA (Configurações > Cadastros > Ações Agendadas): gera o
-- ESTORNO (segunda perna) de lançamentos cuja ORIGEM foi gerada pelo motor
-- NATIVO de contabilização do Sankhya (fórmula em TGFCTB que dispara quando
-- CAB.AD_PROVISIONA = 'S' - ver botão ARG_STP_MARCARPROV).
--
-- REGRA DE DISPARO (CORRIGIDA em 05/08/2026, conforme
-- Documentacao_Provisao_Pedidos_Compra.docx, seção 6 "Estorno automático
-- (rotina JOB)"): o estorno só é gerado quando o pedido DEIXA DE ESTAR
-- PENDENTE - ou seja, quando faturou/virou nota. Rodando diariamente, o job
-- funciona como uma verificação contínua: "esse pedido provisionado já foi
-- faturado?" - assim que a resposta é sim, gera o estorno NAQUELE DIA (data
-- de execução do job, não mês seguinte).
--
-- CORREÇÃO 2 (05/08/2026, mesmo dia): PENDENTE='N' sozinho não é confiável -
-- é uma flag que o pessoal da área pode marcar/desmarcar manualmente (ex.
-- durante o agendamento), não é prova de que o pedido realmente gerou nota.
-- Por decisão do usuário, o gatilho passou a exigir as DUAS condições ao
-- mesmo tempo (AND, não OR) pra não deixar brecha:
--   1) TGFCAB.PENDENTE = 'N' (flag nativa de "não pendente"); E
--   2) existe em TGFVAR (tabela nativa "Documentos relacionados à Nota" -
--      Documento de Origem/Destino) um documento de DESTINO gerado a partir
--      deste pedido com TIPMOV = 'C' (Compra, nota fiscal de entrada real).
--      TGFVAR.NUNOTAORIG = pedido de origem, TGFVAR.NUNOTA = nota gerada.
-- Se só a flag mudar (sem nota real) ou só existir alguma nota vinculada
-- estranha (sem a flag), o job não dispara - as duas têm que bater.
-- (SUPERADA pela CORREÇÃO 5 abaixo - a exigência de PENDENTE='N' foi
-- removida. Texto mantido só como histórico do racional da época.)
--
-- CORREÇÃO 5 (17/08/2026): decisão de negócio (repassada ao usuário por
-- quem definiu a regra) mudou o critério de disparo. Motivo: em pedidos
-- recebidos PARCIALMENTE (nota de compra veio com valor menor que o
-- pedido), TGFCAB.PENDENTE continua 'S' enquanto sobrar saldo a receber -
-- então a condição 1 da CORREÇÃO 2 nunca batia, e a provisão desses
-- pedidos ficava pendurada indefinidamente (30 pedidos identificados nesse
-- estado em 17/08/2026, ex. pedido 794837/KABUM S.A.). Time de Compras
-- decidiu: NÃO vamos controlar saldo parcial de pedido - se o pedido
-- recebeu QUALQUER saldo (ou seja, existe qualquer nota de destino
-- TIPMOV='C' vinculada, mesmo que o pedido ainda tenha saldo em aberto),
-- estorna a provisão INTEIRA, do mesmo jeito que já é feito hoje para
-- pedido 100% recebido (o estorno continua "tudo ou nada", só a condição
-- de disparo mudou). Por isso a condição TGFCAB.PENDENTE = 'N' foi REMOVIDA
-- do WHERE abaixo - o gatilho agora é só a EXISTS em TGFVAR (item 2 da
-- CORREÇÃO 2), sem mais exigir PENDENTE='N' junto.
-- VALIDADO em produção (17/08/2026) via DbExplorer contra os 31 pedidos da
-- lista "Pedidos_com_Provisao_(Sim)_072026.xlsx": dos 31, 25 não têm
-- nenhuma nota de destino vinculada (continuam em aberto do mesmo jeito com
-- a regra nova ou antiga - correto, nada foi recebido ainda) e só 3 dependiam
-- especificamente dessa correção (794837, 812457, 813010 - tinham nota
-- vinculada mas PENDENTE continuava 'S'). Os outros 3 com nota vinculada
-- (804299, 813076, 816073) já tinham PENDENTE='N' e deveriam ter sido
-- estornados mesmo pela regra ANTIGA - não foram, o que sugere que a Ação
-- Agendada pode não estar ativa/rodando em produção (investigar separado,
-- não é problema desta correção).
--
-- CONFIRMADO em reunião com Waleska (18/08/2026): pedido levou pra reunião a
-- dúvida se a CORREÇÃO 5 devia ficar como está ou ser ajustada pro caso de
-- pedido parcelado (várias notas de destino até fechar 100%). Decisão do
-- time: regra fica EXATAMENTE como já implementada. Formalizaram como "duas
-- verificações" - 1) pedido normal: AD_PROVISIONA='S' + PENDENTE='N' +
-- EXISTS nota faturada; 2) pedido parcial: AD_PROVISIONA='S' + PENDENTE='S'
-- + EXISTS nota faturada - mas como PENDENTE só assume 'S' ou 'N', a UNIÃO
-- dos dois casos é matematicamente idêntica à condição única já no WHERE
-- abaixo (EXISTS nota, sem checar PENDENTE). Nenhuma mudança de código
-- necessária - só fechando a pendência que estava em aberto.
--
-- CORREÇÃO IMPORTANTE (05/08/2026): a versão anterior deste arquivo NÃO
-- checava PENDENTE - disparava assim que a origem existia, independente do
-- pedido ainda estar em aberto, e datava o estorno sempre no dia 1 do mês
-- seguinte ao da origem. Essa regra estava ERRADA (vinha de uma confirmação
-- verbal em reunião de 03/08/2026 que conflitava com o doc oficial). Todos
-- os estornos gerados pela versão antiga precisam ser revisados/apagados e
-- regerados por esta versão corrigida (ver ARG_QRY_ESTORNOS_REVISAO.sql).
--
-- DIFERENÇA para a ARG_STP_PROVISAONF_FISCAL: aquele botão cria a ORIGEM e o
-- ESTORNO juntos, calculando a conta pela Natureza (TGFNCC) porque ele é quem
-- decide os valores. Aqui a ORIGEM já existe (gerada pelo motor nativo) -
-- então não recalculamos nada: para cada linha da origem, geramos uma linha
-- espelho datada hoje com CODCTACTB/CODCONPAR/CODCENCUS/VLRLANC IDÊNTICOS e
-- só o TIPLANC invertido (D vira R, R vira D).
--
-- CORREÇÃO 3 (14/08/2026): a correção acima ("Data do estorno = SYSDATE")
-- falava do disparo do job, mas o REFERENCIA (competência/lote) do estorno
-- NÃO é SYSDATE - é o dia 1 do mês SEGUINTE ao mês de competência do
-- lançamento de ORIGEM (CAB_LANC.REFERENCIA), igual à regra antiga, só que
-- agora calculado a partir da competência da ORIGEM, não do mês corrente.
-- Já o DTMOV (data de movimentação real da linha contábil) continua sendo
-- SYSDATE - o dia em que o job detecta o faturamento e gera o estorno.
-- Ou seja: REFERENCIA e DTMOV são datas DIFERENTES agora (antes usavam a
-- mesma variável V_REF_ESTORNO para os dois).
--
-- CORREÇÃO 4 (14/08/2026): o COMPLHIST do estorno usava
-- 'ESTORNO  - LANC ORIGEM <numlanc> - PEDIDO <nunota>' - texto técnico,
-- inconsistente com o padrão nativo do histórico "REF" (código 31) que a
-- TOP usa pra gerar o COMPLHIST da ORIGEM via fórmula 'PROVISÃO |RS| - |DM|'
-- (razão social do parceiro - data de movimentação). Por pedido do usuário,
-- o estorno passou a seguir o MESMO padrão: 'ESTORNO - <razão social ou
-- nome do parceiro> - <data de movimentação>'. Isso troca a chave de
-- idempotência: antes o COMPLHIST embutia NUMLANC+NUNOTA da origem (único
-- por lançamento); agora embute parceiro+data do ESTORNO, que já é
-- suficiente na prática porque a checagem continua combinada (AND, mesma
-- subquery) com AD_NUNOTAORIG=pedido + CODEMP + INDESTORNADO='S'. RISCO
-- RESIDUAL aceito: se o MESMO pedido for reprovisionado (DESMARCARPROV ->
-- MARCARPROV) e os DOIS estornos (do lançamento antigo e do novo) forem
-- gerados no MESMO dia, o texto ficaria idêntico e o job pularia o segundo
-- por engano - cenário raro (exigiria dois ciclos completos de
-- provisão/estorno do mesmo pedido no mesmo dia), não coberto hoje.
-- (SUPERADA pela CORREÇÃO 6 abaixo - o risco real era muito maior que esse
-- cenário raro. Texto mantido só como histórico.)
--
-- CORREÇÃO 6 (18/08/2026) - BUG CRÍTICO, estorno duplicado todo dia: a
-- CORREÇÃO 4 trocou a chave de idempotência de algo PERMANENTE
-- (NUMLANC+NUNOTA da origem) para um texto que embute TRUNC(SYSDATE) - a
-- data de HOJE. Isso faz o NOT EXISTS só reconhecer "já estornei esse
-- pedido" NO MESMO DIA em que o estorno original foi gerado. No dia
-- seguinte (ou próxima execução do job, seja diária ou mensal), o texto
-- comparado muda de data e não bate mais com o que já foi gravado -
-- NOT EXISTS avalia verdadeiro de novo - e a rotina gera OUTRO estorno pro
-- MESMO lançamento de origem. Nada mais impede isso: L.INDESTORNADO da
-- linha de origem nunca é tocado pelo motor nativo (permanece 'N' pra
-- sempre - ver [[provisao-nfs-marcarprov-flow]]), e AD_GERAESTORNO é
-- setado mas NUNCA foi checado no WHERE (só "flag de saída", conforme o
-- README já registrava). Resultado real observado em produção: o mesmo
-- lançamento de origem (ex. R$24.007,50) sendo estornado repetidamente a
-- cada execução, inflando o total de estornos muito além do total
-- provisionado. CORREÇÃO: (1) AD_GERAESTORNO volta a ser trava de ENTRADA
-- (WHERE abaixo); (2) o NOT EXISTS de idempotência não compara mais
-- COMPLHIST/data - passa a checar só "existe ALGUM estorno pra esse pedido"
-- (AD_NUNOTAORIG + CODEMP + INDESTORNADO='S'), sem depender de quando foi
-- gerado. O texto do COMPLHIST (padrão RS-DM da CORREÇÃO 4) continua sendo
-- gravado igual, só deixou de ser usado como chave de comparação.
--
-- PENDÊNCIAS / ASSUNÇÕES A CONFIRMAR antes de agendar em produção:
--   a) Estamos assumindo que o ESTORNO vai pro MESMO NUMLOTE da ORIGEM
--      (V_NUMLOTE_ESTORNO := CAB_LANC.NUMLOTE).
--   b) REFERENCIA do estorno = dia 1 do mês seguinte ao mês de
--      CAB_LANC.REFERENCIA (competência da origem); DTMOV do estorno =
--      SYSDATE (dia em que o job roda e detecta o faturamento) - ver
--      CORREÇÃO 3. Assume que o job roda 1x por dia.
--   c) CODUSU do estorno = mesmo usuário do lançamento de origem (L.CODUSU).
--   d) Idempotência por AD_GERAESTORNO<>'S' (trava de entrada) + NOT EXISTS
--      de "algum estorno já existe pra este pedido" (AD_NUNOTAORIG+CODEMP+
--      INDESTORNADO='S', SEM comparar COMPLHIST/data - ver CORREÇÃO 6) -
--      sem tabela de controle dedicada, por decisão do usuário. O texto do
--      COMPLHIST (padrão RS-DM, CORREÇÃO 4) é só exibição, não é mais chave
--      de comparação.
--   e) AD_NUNOTAORIG/AD_CODPARC do estorno são preenchidos com o NUNOTA do
--      pedido (achado via TCBINT) e o AD_CODPARC da linha de origem - o
--      lançamento nativo não necessariamente preenche AD_NUNOTAORIG sozinho,
--      então gravamos explicitamente pra manter rastreabilidade.
--
-- CADASTRO NO SANKHYA (ver doc oficial:
-- https://ajuda.sankhya.com.br/hc/pt-br/articles/360045110653-A%C3%A7%C3%B5es-Agendadas):
--   Tipo de ação        = Proc. Banco de dados
--   Ação                = ARG_STP_GERAESTORNO_AGENDADO
--   Transação automática = DESMARCADA (por isso o COMMIT explícito no final -
--                          sem essa marcação o Sankhya não comita sozinho)
--   Usuário Logado      = não precisa (SQL puro, sem chamada de API/entidade)
--   Config. expressão    = diária (ex.: 0 0 6 * * ?) - roda 1x por dia,
--                          checando quais pedidos provisionados já faturaram
-- ============================================================================

CREATE OR REPLACE PROCEDURE "ARG_STP_GERAESTORNO_AGENDADO" AS

    V_NUMLOTE_ESTORNO   NUMBER;
    V_REF_ESTORNO       DATE;   -- REFERENCIA: dia 1 do mês seguinte ao da competência da origem
    V_DTMOV_ESTORNO     DATE;   -- DTMOV: data real em que o estorno é gerado (hoje)
    V_NUMLANC_ESTORNO   NUMBER;
    V_SEQ               NUMBER;
    V_QTD_LOTE          NUMBER;
    V_QTD_GERADOS       NUMBER := 0;

BEGIN

    -- -------------------------------------------------------------------
    -- Cabeçalhos de lançamento de ORIGEM (gerados pelo motor nativo via
    -- TCBINT) ainda sem estorno: um registro por (CODEMP, REFERENCIA,
    -- NUMLOTE, NUMLANC) cujo Pedido (achado via TCBINT.NUNICO) está com
    -- AD_PROVISIONA = 'S' E já recebeu QUALQUER saldo - existe nota de
    -- destino em TGFVAR com TIPMOV='C' (ver CORREÇÃO 5 no cabeçalho: não
    -- exige mais PENDENTE='N', pedido recebido parcialmente também dispara
    -- o estorno TOTAL da provisão). Pedido sem nenhuma nota de destino
    -- ainda NÃO entra aqui - o job espera a próxima execução diária e
    -- checa de novo.
    -- -------------------------------------------------------------------
    FOR CAB_LANC IN (
        SELECT DISTINCT L.CODEMP, L.REFERENCIA, L.NUMLOTE, L.NUMLANC, CAB.NUNOTA,
               NVL(PAR.RAZAOSOCIAL, PAR.NOMEPARC) AS NOMEPARC
          FROM TCBINT TCI
          JOIN TGFCAB CAB ON CAB.NUNOTA = TCI.NUNICO
          JOIN SANKHYA.TCBLAN L
            ON L.CODEMP     = TCI.CODEMP
           AND L.REFERENCIA = TCI.REFERENCIA
           AND L.NUMLOTE    = TCI.NUMLOTE
           AND L.NUMLANC    = TCI.NUMLANC
          JOIN TGFPAR PAR ON PAR.CODPARC = CAB.CODPARC
         WHERE TCI.ORIGEM = 'E'
           AND CAB.TIPMOV = 'O'
           AND CAB.AD_PROVISIONA = 'S'
           AND NVL(CAB.AD_GERAESTORNO, 'N') <> 'S'   -- CORREÇÃO 6: trava de entrada, evita reprocessar pedido já estornado
           AND (
                 -- Duas verificações formalizadas na reunião com Waleska
                 -- (18/08/2026, ver CORREÇÃO 5 no cabeçalho): Caso 1 = pedido
                 -- normal (recebimento total, PENDENTE='N'); Caso 2 = pedido
                 -- parcial (PENDENTE='S'). As duas exigem a MESMA condição de
                 -- fundo (existe nota de destino TIPMOV='C' vinculada) - por
                 -- isso, mesmo escritas como dois blocos separados aqui pra
                 -- espelhar a decisão de negócio 1:1, o resultado é idêntico
                 -- a um único EXISTS sem checar PENDENTE (união de S/N cobre
                 -- todo o domínio do campo).
                 (
                   CAB.PENDENTE = 'N'   -- Caso 1: pedido normal
                   AND EXISTS (
                         SELECT 1
                           FROM TGFVAR VAR
                           JOIN TGFCAB DEST ON DEST.NUNOTA = VAR.NUNOTA
                          WHERE VAR.NUNOTAORIG = CAB.NUNOTA
                            AND DEST.TIPMOV = 'C'
                       )
                 )
                 OR
                 (
                   CAB.PENDENTE = 'S'   -- Caso 2: pedido parcial
                   AND EXISTS (
                         SELECT 1
                           FROM TGFVAR VAR
                           JOIN TGFCAB DEST ON DEST.NUNOTA = VAR.NUNOTA
                          WHERE VAR.NUNOTAORIG = CAB.NUNOTA
                            AND DEST.TIPMOV = 'C'
                       )
                 )
               )
           AND L.INDESTORNADO = 'N'
           AND NOT EXISTS (
                 -- Idempotência (CORREÇÃO 6): existe ALGUM estorno pra este
                 -- pedido, independente de quando foi gerado - não compara
                 -- mais COMPLHIST/data (isso é o que causava a duplicação
                 -- diária, ver CORREÇÃO 6 no cabeçalho).
                 SELECT 1 FROM SANKHYA.TCBLAN E
                  WHERE E.AD_NUNOTAORIG = CAB.NUNOTA
                    AND E.CODEMP = L.CODEMP
                    AND E.INDESTORNADO = 'S'
               )
    )
    LOOP
        V_NUMLOTE_ESTORNO := CAB_LANC.NUMLOTE;                                   -- assunção (a)
        V_REF_ESTORNO     := ADD_MONTHS(TRUNC(CAB_LANC.REFERENCIA, 'MM'), 1);   -- assunção (b): dia 1 do mês seguinte à competência da origem
        V_DTMOV_ESTORNO   := TRUNC(SYSDATE);                                    -- assunção (b): dia da execução do job (pedido faturou hoje)

        -- Garante o lote (CODEMP, REFERENCIA, NUMLOTE) na TCBLOT pro dia do
        -- estorno - mesma lógica de auto-criação da ARG_STP_PROVISAONF_FISCAL.
        SELECT COUNT(*) INTO V_QTD_LOTE
          FROM SANKHYA.TCBLOT
         WHERE CODEMP = CAB_LANC.CODEMP
           AND REFERENCIA = V_REF_ESTORNO
           AND NUMLOTE = V_NUMLOTE_ESTORNO;

        IF V_QTD_LOTE = 0 THEN
            INSERT INTO SANKHYA.TCBLOT (CODEMP, REFERENCIA, NUMLOTE, DTMOV, SITUACAO, ULTLANC, CODUSU)
            VALUES (CAB_LANC.CODEMP, V_REF_ESTORNO, V_NUMLOTE_ESTORNO, V_DTMOV_ESTORNO, 'A', 0, 0);
        END IF;

        SELECT NVL(MAX(NUMLANC), 0) + 1 INTO V_NUMLANC_ESTORNO
          FROM SANKHYA.TCBLAN
         WHERE CODEMP = CAB_LANC.CODEMP AND REFERENCIA = V_REF_ESTORNO AND NUMLOTE = V_NUMLOTE_ESTORNO;

        V_SEQ := 0;

        -- Espelha cada linha da origem, invertendo só o TIPLANC (D<->R) -
        -- ver explicação no cabeçalho do arquivo.
        FOR L IN (
            SELECT * FROM SANKHYA.TCBLAN
             WHERE CODEMP = CAB_LANC.CODEMP
               AND REFERENCIA = CAB_LANC.REFERENCIA
               AND NUMLOTE = CAB_LANC.NUMLOTE
               AND NUMLANC = CAB_LANC.NUMLANC
             ORDER BY SEQUENCIA
        )
        LOOP
            V_SEQ := V_SEQ + 1;

            INSERT INTO SANKHYA.TCBLAN (
                CODEMP, REFERENCIA, NUMLOTE, NUMLANC, TIPLANC, SEQUENCIA,
                CODCTACTB, CODCONPAR, CODCENCUS, DTMOV, VLRLANC,
                CODHISTCTB, COMPLHIST, LIBERADO, CODUSU, INDESTORNADO,
                AD_NUNOTAORIG, AD_CODPARC, NUMDOC, CODPROJ
            ) VALUES (
                L.CODEMP, V_REF_ESTORNO, V_NUMLOTE_ESTORNO, V_NUMLANC_ESTORNO,
                CASE L.TIPLANC WHEN 'D' THEN 'R' ELSE 'D' END, V_SEQ,
                L.CODCTACTB, L.CODCONPAR, L.CODCENCUS, V_DTMOV_ESTORNO, L.VLRLANC,
                L.CODHISTCTB,
                'ESTORNO - ' || CAB_LANC.NOMEPARC || ' - ' || TO_CHAR(V_DTMOV_ESTORNO, 'DD/MM/YYYY'),
                'S', NVL(L.CODUSU, 0), 'S',
                CAB_LANC.NUNOTA, L.AD_CODPARC, L.NUMDOC, L.CODPROJ
            );
        END LOOP;

        -- Marca o pedido como "estorno gerado" pra contabilidade acompanhar
        -- sem precisar ligar o campo manualmente pela Central de Notas.
        UPDATE TGFCAB
           SET AD_GERAESTORNO = 'S'
         WHERE NUNOTA = CAB_LANC.NUNOTA
           AND NVL(AD_GERAESTORNO,'N') <> 'S';

        V_QTD_GERADOS := V_QTD_GERADOS + 1;
    END LOOP;

    COMMIT;

END;
/
