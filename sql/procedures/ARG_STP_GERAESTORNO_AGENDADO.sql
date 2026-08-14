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
-- Por decisão do usuário, o gatilho agora exige as DUAS condições ao mesmo
-- tempo (AND, não OR) pra não deixar brecha:
--   1) TGFCAB.PENDENTE = 'N' (flag nativa de "não pendente"); E
--   2) existe em TGFVAR (tabela nativa "Documentos relacionados à Nota" -
--      Documento de Origem/Destino) um documento de DESTINO gerado a partir
--      deste pedido com TIPMOV = 'C' (Compra, nota fiscal de entrada real).
--      TGFVAR.NUNOTAORIG = pedido de origem, TGFVAR.NUNOTA = nota gerada.
-- Se só a flag mudar (sem nota real) ou só existir alguma nota vinculada
-- estranha (sem a flag), o job não dispara - as duas têm que bater.
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
-- PENDÊNCIAS / ASSUNÇÕES A CONFIRMAR antes de agendar em produção:
--   a) Estamos assumindo que o ESTORNO vai pro MESMO NUMLOTE da ORIGEM
--      (V_NUMLOTE_ESTORNO := CAB_LANC.NUMLOTE).
--   b) REFERENCIA do estorno = dia 1 do mês seguinte ao mês de
--      CAB_LANC.REFERENCIA (competência da origem); DTMOV do estorno =
--      SYSDATE (dia em que o job roda e detecta o faturamento) - ver
--      CORREÇÃO 3. Assume que o job roda 1x por dia.
--   c) CODUSU do estorno = mesmo usuário do lançamento de origem (L.CODUSU).
--   d) Idempotência por COMPLHIST exato do estorno (embute NUMLANC + NUNOTA
--      de origem) - sem tabela de controle dedicada, por decisão do usuário.
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
    -- AD_PROVISIONA = 'S' E passa nas DUAS checagens de "realmente faturou"
    -- (PENDENTE='N' + nota de destino em TGFVAR com TIPMOV='C' - ver
    -- correção 2 no cabeçalho). Pedido que falhar em qualquer uma das duas
    -- NÃO entra aqui - o job espera a próxima execução diária e checa de novo.
    -- -------------------------------------------------------------------
    FOR CAB_LANC IN (
        SELECT DISTINCT L.CODEMP, L.REFERENCIA, L.NUMLOTE, L.NUMLANC, CAB.NUNOTA
          FROM TCBINT TCI
          JOIN TGFCAB CAB ON CAB.NUNOTA = TCI.NUNICO
          JOIN SANKHYA.TCBLAN L
            ON L.CODEMP     = TCI.CODEMP
           AND L.REFERENCIA = TCI.REFERENCIA
           AND L.NUMLOTE    = TCI.NUMLOTE
           AND L.NUMLANC    = TCI.NUMLANC
         WHERE TCI.ORIGEM = 'E'
           AND CAB.TIPMOV = 'O'
           AND CAB.AD_PROVISIONA = 'S'
           AND CAB.PENDENTE = 'N'
           AND EXISTS (
                 SELECT 1
                   FROM TGFVAR VAR
                   JOIN TGFCAB DEST ON DEST.NUNOTA = VAR.NUNOTA
                  WHERE VAR.NUNOTAORIG = CAB.NUNOTA
                    AND DEST.TIPMOV = 'C'
               )
           AND L.INDESTORNADO = 'N'
           AND NOT EXISTS (
                 -- Idempotência por NUMLANC de origem (não só pedido+dia).
                 SELECT 1 FROM SANKHYA.TCBLAN E
                  WHERE E.AD_NUNOTAORIG = CAB.NUNOTA
                    AND E.CODEMP = L.CODEMP
                    AND E.INDESTORNADO = 'S'
                    AND E.COMPLHIST = 'ESTORNO  - LANC ORIGEM ' || L.NUMLANC || ' - PEDIDO ' || CAB.NUNOTA
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
                'ESTORNO  - LANC ORIGEM ' || L.NUMLANC || ' - PEDIDO ' || CAB_LANC.NUNOTA,
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
