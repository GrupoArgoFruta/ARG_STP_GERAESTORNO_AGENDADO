-- ============================================================================
-- Botão de ação MANUAL: gera o ESTORNO (segunda perna) da provisão do(s)
-- pedido(s) selecionado(s) na tela/dashboard "STATUS DA PROVISÃO DE UM
-- PEDIDO DE COMPRA". Contraparte manual da ARG_STP_GERAESTORNO_AGENDADO
-- (rotina agendada, roda sozinha 1x/dia em TODOS os pedidos elegíveis) -
-- usa a MESMA lógica de espelhar a origem (busca via TCBINT, inverte
-- TIPLANC), mas dispara só nos pedidos que o usuário selecionar e confirmar
-- na tela.
--
-- DECISÃO DE DESIGN: este botão NÃO repete a checagem automática de
-- PENDENTE + TGFVAR ("realmente faturou") que a rotina agendada exige -
-- aqui é o usuário, olhando as colunas do dashboard (Provisão Lançada /
-- Estorno Lançado), quem decide manualmente que quer forçar a geração
-- (ex.: casos como pedido não confirmado que a checagem automática bloqueia
-- sem querer). Se quiser reativar essa trava aqui também, é só copiar o
-- mesmo EXISTS de ARG_STP_GERAESTORNO_AGENDADO.
--
-- IMPORTANTE - CONSISTÊNCIA COM A ROTINA AGENDADA: o texto gravado em
-- COMPLHIST é EXATAMENTE o mesmo que ARG_STP_GERAESTORNO_AGENDADO usa
-- ('ESTORNO  - LANC ORIGEM ...'). Isso é proposital - é o que a idempotência
-- (NOT EXISTS por COMPLHIST) usa pra reconhecer "já tem estorno" nas DUAS
-- procedures. Se esse botão gerar o estorno primeiro, a rotina agendada
-- reconhece e não duplica (e vice-versa). NÃO mudar esse texto sem também
-- mudar no outro arquivo.
--
-- Regras aplicadas por pedido selecionado:
--   1) Precisa ter a ORIGEM já lançada (AD_PROVISIONA='S' + achar via
--      TCBINT+TCBLAN) - senão, ignora (não tem o que estornar).
--   2) Precisa NÃO ter estorno já gerado (mesma idempotência por
--      AD_NUNOTAORIG+COMPLHIST da rotina agendada) - senão, ignora (evita
--      duplicar, seja o estorno anterior manual ou automático).
-- ============================================================================

CREATE OR REPLACE PROCEDURE SANKHYA.ARG_STP_ESTORNO_MANUAL (
       P_CODUSU NUMBER,
       P_IDSESSAO VARCHAR2,
       P_QTDLINHAS NUMBER,
       P_MENSAGEM OUT VARCHAR2
) AS
       FIELD_NUNOTA        NUMBER;
       V_NUMLOTE_ESTORNO   NUMBER;
       V_REF_ESTORNO       DATE := TRUNC(SYSDATE);
       V_NUMLANC_ESTORNO   NUMBER;
       V_SEQ               NUMBER;
       V_QTD_LOTE          NUMBER;
       V_QTD_GERADOS       NUMBER := 0;
BEGIN
       FOR I IN 1..P_QTDLINHAS LOOP

           FIELD_NUNOTA := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNOTA');

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
                  AND CAB.NUNOTA = FIELD_NUNOTA
                  AND L.INDESTORNADO = 'N'
                  AND NOT EXISTS (
                        SELECT 1 FROM SANKHYA.TCBLAN E
                         WHERE E.AD_NUNOTAORIG = CAB.NUNOTA
                           AND E.CODEMP = L.CODEMP
                           AND E.INDESTORNADO = 'S'
                           AND E.COMPLHIST = 'ESTORNO  - LANC ORIGEM ' || L.NUMLANC || ' - PEDIDO ' || CAB.NUNOTA
                      )
           )
           LOOP
               V_NUMLOTE_ESTORNO := CAB_LANC.NUMLOTE;

               SELECT COUNT(*) INTO V_QTD_LOTE
                 FROM SANKHYA.TCBLOT
                WHERE CODEMP = CAB_LANC.CODEMP
                  AND REFERENCIA = V_REF_ESTORNO
                  AND NUMLOTE = V_NUMLOTE_ESTORNO;

               IF V_QTD_LOTE = 0 THEN
                   INSERT INTO SANKHYA.TCBLOT (CODEMP, REFERENCIA, NUMLOTE, DTMOV, SITUACAO, ULTLANC, CODUSU)
                   VALUES (CAB_LANC.CODEMP, V_REF_ESTORNO, V_NUMLOTE_ESTORNO, V_REF_ESTORNO, 'A', 0, NVL(P_CODUSU, 0));
               END IF;

               SELECT NVL(MAX(NUMLANC), 0) + 1 INTO V_NUMLANC_ESTORNO
                 FROM SANKHYA.TCBLAN
                WHERE CODEMP = CAB_LANC.CODEMP AND REFERENCIA = V_REF_ESTORNO AND NUMLOTE = V_NUMLOTE_ESTORNO;

               V_SEQ := 0;

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
                       'ESTORNO  - LANC ORIGEM ' || L.NUMLANC || ' - PEDIDO ' || CAB_LANC.NUNOTA,
                       'S', NVL(L.CODUSU, 0), 'S',
                       CAB_LANC.NUNOTA, L.AD_CODPARC, L.NUMDOC, L.CODPROJ
                   );
               END LOOP;

               UPDATE TGFCAB
                  SET AD_GERAESTORNO = 'S'
                WHERE NUNOTA = CAB_LANC.NUNOTA
                  AND NVL(AD_GERAESTORNO, 'N') <> 'S';

               V_QTD_GERADOS := V_QTD_GERADOS + 1;
           END LOOP;

       END LOOP;

       P_MENSAGEM := V_QTD_GERADOS || ' estorno(s) gerado(s).';

END;
/
