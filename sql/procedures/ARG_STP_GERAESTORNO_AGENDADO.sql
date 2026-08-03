-- ============================================================================
-- Rotina AGENDADA (Configurações > Cadastros > Ações Agendadas): gera o
-- ESTORNO (segunda perna) de lançamentos cuja ORIGEM foi gerada pelo motor
-- NATIVO de contabilização do Sankhya (fórmula em TGFCTB que dispara quando
-- CAB.AD_PROVISIONA = 'S' - ver botão ARG_STP_MARCARPROV).
--
-- MUDANÇA (31/07/2026): antes esta rotina descobria a ORIGEM via
-- TCBLAN.AD_NUNOTAORIG + TGFCAB.AD_GERAESTORNO='S' (fluxo em que a
-- contabilidade lançava a origem manualmente na tela nativa). Agora a
-- ORIGEM já é gerada automaticamente pelo motor nativo (mesmo mecanismo do
-- dashboard "STATUS DA PROVISÃO DE UM PEDIDO DE COMPRA", gadget 383) -
-- então a descoberta passa a ser: TCBINT (ORIGEM='E', NUNICO=NUNOTA do
-- pedido) -> TGFCAB.AD_PROVISIONA='S' -> TCBLAN (join por
-- CODEMP+REFERENCIA+NUMLOTE+NUMLANC). AD_GERAESTORNO deixa de ser gatilho
-- de entrada; agora é atualizado automaticamente pela própria rotina como
-- flag de status pra contabilidade acompanhar (evita a contabilidade ter
-- que abrir a Central de Notas e ligar o campo manualmente).
--
-- DIFERENÇA para a ARG_STP_PROVISAONF_FISCAL: aquele botão cria a ORIGEM e o
-- ESTORNO juntos, calculando a conta pela Natureza (TGFNCC) porque ele é quem
-- decide os valores. Aqui a ORIGEM já existe (gerada pelo motor nativo) -
-- então não recalculamos nada: para cada linha da origem, geramos uma linha
-- espelho no D+1 com CODCTACTB/CODCONPAR/CODCENCUS/VLRLANC IDÊNTICOS e só o
-- TIPLANC invertido (D vira R, R vira D).
--
-- PENDÊNCIAS / ASSUNÇÕES A CONFIRMAR antes de agendar em produção:
--   a) Estamos assumindo que o ESTORNO vai pro MESMO NUMLOTE da ORIGEM
--      (V_NUMLOTE_ESTORNO := CAB_LANC.NUMLOTE).
--   b) O estorno vai sempre pro PRIMEIRO DIA DO MÊS SEGUINTE ao da origem
--      (regra de competência confirmada pelo usuário em 31/07/2026: se a
--      provisão foi em 01/07, o estorno tem que cair em 01/08 - não é
--      "dia da origem + 1 dia corrido", é sempre dia 1 do mês seguinte,
--      independente de que dia do mês a origem caiu).
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
--   Config. expressão    = intervalo de 5 em 5 minutos, só para teste -
--                          espaçar mais depois de validado
-- ============================================================================

CREATE OR REPLACE PROCEDURE "ARG_STP_GERAESTORNO_AGENDADO" AS

    V_NUMLOTE_ESTORNO   NUMBER;
    V_REF_ESTORNO       DATE;
    V_NUMLANC_ESTORNO   NUMBER;
    V_SEQ               NUMBER;
    V_QTD_LOTE          NUMBER;
    V_QTD_GERADOS       NUMBER := 0;

BEGIN

    -- -------------------------------------------------------------------
    -- Cabeçalhos de lançamento de ORIGEM (gerados pelo motor nativo via
    -- TCBINT) ainda sem estorno: um registro por (CODEMP, REFERENCIA,
    -- NUMLOTE, NUMLANC) cujo Pedido (achado via TCBINT.NUNICO) está com
    -- AD_PROVISIONA = 'S'.
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
           AND L.INDESTORNADO = 'N'
           AND NOT EXISTS (
                 -- Idempotência por NUMLANC de origem (não só pedido+dia).
                 SELECT 1 FROM SANKHYA.TCBLAN E
                  WHERE E.AD_NUNOTAORIG = CAB.NUNOTA
                    AND E.CODEMP = L.CODEMP
                    AND E.INDESTORNADO = 'S'
                    AND E.COMPLHIST = 'ESTORNO AUTOMATICO - LANC ORIGEM ' || L.NUMLANC || ' - PEDIDO ' || CAB.NUNOTA
               )
    )
    LOOP
        V_NUMLOTE_ESTORNO := CAB_LANC.NUMLOTE;         -- assunção (a)
        V_REF_ESTORNO     := TRUNC(ADD_MONTHS(CAB_LANC.REFERENCIA, 1), 'MM');  -- assunção (b): dia 1 do mês seguinte

        -- Garante o lote (CODEMP, REFERENCIA, NUMLOTE) na TCBLOT pro dia do
        -- estorno - mesma lógica de auto-criação da ARG_STP_PROVISAONF_FISCAL.
        SELECT COUNT(*) INTO V_QTD_LOTE
          FROM SANKHYA.TCBLOT
         WHERE CODEMP = CAB_LANC.CODEMP
           AND REFERENCIA = V_REF_ESTORNO
           AND NUMLOTE = V_NUMLOTE_ESTORNO;

        IF V_QTD_LOTE = 0 THEN
            INSERT INTO SANKHYA.TCBLOT (CODEMP, REFERENCIA, NUMLOTE, DTMOV, SITUACAO, ULTLANC, CODUSU)
            VALUES (CAB_LANC.CODEMP, V_REF_ESTORNO, V_NUMLOTE_ESTORNO, V_REF_ESTORNO, 'A', 0, 0);
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
                L.CODCTACTB, L.CODCONPAR, L.CODCENCUS, V_REF_ESTORNO, L.VLRLANC,
                L.CODHISTCTB,
                'ESTORNO AUTOMATICO - LANC ORIGEM ' || L.NUMLANC || ' - PEDIDO ' || CAB_LANC.NUNOTA,
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
