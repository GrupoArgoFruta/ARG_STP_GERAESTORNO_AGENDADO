-- ============================================================================
-- ARG_STP_ESTORNO_MANUAL
-- Botão de ação 320 "Gerar estorno manual" (instância CabecalhoNota), usado
-- no dash 384 "STATUS DA PROVISÃO DE UM PEDIDO DE COMPRA".
--
-- Gera o ESTORNO (2ª perna) da provisão dos pedidos selecionados. É a versão
-- manual da ARG_STP_GERAESTORNO_AGENDADO, mas com regra de data própria
-- (CORREÇÃO 9).
--
-- CORREÇÃO 9 (05/11/2026), substitui a regra de data da CORREÇÃO 8:
--   Problema: pedido 865665 (provisão 09/2026, DTMOV 16/09, sem NF ligada)
--   foi estornado pelo botão em 04/11/2026 17:27 e ficou com REFERENCIA
--   11/2026 e DTMOV 04/11/2026, a data do clique. O estorno tem que ficar
--   no mês seguinte ao da provisão.
--   Agora: REFERENCIA = DTMOV = dia 1 do mês seguinte ao da provisão
--   (provisão 09/2026 -> 01/10/2026), com ou sem NF e qualquer que seja o
--   dia do clique. Não olha mais a data da NF (TGFVAR).
--   A agendada NÃO mudou: continua estornando na data da 1ª NF (CORREÇÃO 7),
--   decisão do TI em 05/11/2026 (regra nova só para o botão).
--   Se o mês seguinte estiver fechado (AD_FECHAMOD), o pedido falha e
--   aparece na mensagem, como antes.
--
-- CORREÇÃO 8 (03/11/2026, regra de data SUPERADA pela CORREÇÃO 9; o resto
-- continua valendo), mesma regra de data da CORREÇÃO 7 da agendada:
--   Antes: REFERENCIA = mês seguinte ao da provisão e DTMOV = dia do clique.
--   A trigger TRG_TCBLAN_VALIDA_REF_DTMOV recusa REFERENCIA e DTMOV em meses
--   diferentes (ORA-20001), então o botão só funcionava no mês seguinte ao
--   da provisão. Exemplo: pedido 890441 (provisão 09/2026, NF 09/10/2026),
--   botão usado em 11/2026 -> REFERENCIA 10/2026 x DTMOV 11/2026 -> erro.
--   Agora:
--   - DTMOV = entrada da 1ª NF de compra do pedido (TGFVAR,
--     MIN(NVL(DTENTSAI, DTNEG))). Sem NF, usa a data do clique (o botão
--     continua permitindo estornar pedido não faturado, decisão do usuário).
--     Nunca antes do mês da provisão.
--   - REFERENCIA = dia 1 do mês do DTMOV.
--   - Idempotência só por AD_NUNOTAORIG + INDESTORNADO = 'S', igual à
--     agendada. A versão anterior também exigia COMPLHIST com a data de
--     hoje, então só barrava estorno repetido no mesmo dia.
--   - Não olha AD_GERAESTORNO: a marca é copiada quando o pedido é
--     duplicado (caso do 890441, cópia do 819592) e não prova que existe
--     estorno. Quem decide é a existência do lançamento.
--   - Erro por pedido: SAVEPOINT por provisão. Um pedido com erro (ex:
--     período contábil fechado) não desfaz os outros. A mensagem final
--     lista quantos foram gerados, os erros e os pedidos sem nada a estornar.
--
-- Período fechado (AD_FECHAMOD): se o mês seguinte à provisão estiver
-- fechado, o pedido falha e aparece na mensagem. A data não é empurrada para
-- o 1º dia aberto (mesma decisão da agendada, 02/10/2026).
--
-- COMPILAR NO DBEAVER SEM FORMATAR: o formatador (Ctrl+Shift+F) quebra
-- "END LOOP;" em "END" + "LOOP;", o DBeaver entende o "END" como fim da
-- procedure, compila só até ali (INVALID, PLS-00103) e manda o resto como
-- SQL solto (ORA-00933). Aconteceu em 03/11/2026. Abrir o arquivo como está
-- e rodar com Alt+X (Executar script).
-- ============================================================================

CREATE OR REPLACE PROCEDURE SANKHYA.ARG_STP_ESTORNO_MANUAL (
       P_CODUSU    NUMBER,
       P_IDSESSAO  VARCHAR2,
       P_QTDLINHAS NUMBER,
       P_MENSAGEM  OUT VARCHAR2
) AS
       FIELD_NUNOTA       NUMBER;
       V_NUMLOTE_ESTORNO  NUMBER;
       V_REF_ESTORNO      DATE;   -- REFERENCIA: dia 1 do mês seguinte ao da provisão (CORREÇÃO 9)
       V_DTMOV_ESTORNO    DATE;   -- DTMOV: igual à REFERENCIA (CORREÇÃO 9)
       V_NUMLANC_ESTORNO  NUMBER;
       V_SEQ              NUMBER;
       V_QTD_LOTE         NUMBER;
       V_QTD_PEDIDO       NUMBER;
       V_QTD_GERADOS      NUMBER := 0;
       V_QTD_ERROS        NUMBER := 0;
       V_ERROS            VARCHAR2(4000);
       V_SEM_ESTORNO      VARCHAR2(4000);
BEGIN
       FOR I IN 1..P_QTDLINHAS LOOP

           FIELD_NUNOTA := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNOTA');
           V_QTD_PEDIDO := 0;

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
                  AND CAB.NUNOTA = FIELD_NUNOTA
                  AND L.INDESTORNADO = 'N'
                  AND NOT EXISTS (
                      SELECT 1 FROM SANKHYA.TCBLAN E
                       WHERE E.AD_NUNOTAORIG = CAB.NUNOTA
                         AND E.CODEMP = L.CODEMP
                         AND E.INDESTORNADO = 'S'
                  )
           )
           LOOP
               V_QTD_PEDIDO := V_QTD_PEDIDO + 1;
               SAVEPOINT SP_ESTORNO_MANUAL;

               BEGIN
                   V_NUMLOTE_ESTORNO := CAB_LANC.NUMLOTE;
                   -- CORREÇÃO 9: dia 1 do mês seguinte ao da provisão,
                   -- REFERENCIA e DTMOV iguais (TRG_TCBLAN_VALIDA_REF_DTMOV).
                   V_REF_ESTORNO     := ADD_MONTHS(TRUNC(CAB_LANC.REFERENCIA, 'MM'), 1);
                   V_DTMOV_ESTORNO   := V_REF_ESTORNO;

                   SELECT COUNT(*) INTO V_QTD_LOTE
                     FROM SANKHYA.TCBLOT
                    WHERE CODEMP     = CAB_LANC.CODEMP
                      AND REFERENCIA = V_REF_ESTORNO
                      AND NUMLOTE    = V_NUMLOTE_ESTORNO;

                   IF V_QTD_LOTE = 0 THEN
                       INSERT INTO SANKHYA.TCBLOT (CODEMP, REFERENCIA, NUMLOTE, DTMOV, SITUACAO, ULTLANC, CODUSU)
                       VALUES (CAB_LANC.CODEMP, V_REF_ESTORNO, V_NUMLOTE_ESTORNO, V_DTMOV_ESTORNO, 'A', 0, NVL(P_CODUSU, 0));
                   END IF;

                   SELECT NVL(MAX(NUMLANC), 0) + 1 INTO V_NUMLANC_ESTORNO
                     FROM SANKHYA.TCBLAN
                    WHERE CODEMP = CAB_LANC.CODEMP AND REFERENCIA = V_REF_ESTORNO AND NUMLOTE = V_NUMLOTE_ESTORNO;

                   V_SEQ := 0;

                   FOR L IN (
                       SELECT * FROM SANKHYA.TCBLAN
                        WHERE CODEMP     = CAB_LANC.CODEMP
                          AND REFERENCIA = CAB_LANC.REFERENCIA
                          AND NUMLOTE    = CAB_LANC.NUMLOTE
                          AND NUMLANC    = CAB_LANC.NUMLANC
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

                   UPDATE TGFCAB
                      SET AD_GERAESTORNO = 'S'
                    WHERE NUNOTA = CAB_LANC.NUNOTA
                      AND NVL(AD_GERAESTORNO, 'N') <> 'S';

                   V_QTD_GERADOS := V_QTD_GERADOS + 1;

               EXCEPTION
                   WHEN OTHERS THEN
                       ROLLBACK TO SP_ESTORNO_MANUAL;
                       V_QTD_ERROS := V_QTD_ERROS + 1;
                       IF NVL(LENGTH(V_ERROS), 0) < 1500 THEN
                           V_ERROS := V_ERROS || ' | ' || CAB_LANC.NUNOTA || ': '
                                   || SUBSTR(REGEXP_SUBSTR(SQLERRM, '[^' || CHR(10) || ']+'), 1, 150);
                       END IF;
               END;
           END LOOP;

           IF V_QTD_PEDIDO = 0 AND NVL(LENGTH(V_SEM_ESTORNO), 0) < 500 THEN
               IF V_SEM_ESTORNO IS NOT NULL THEN
                   V_SEM_ESTORNO := V_SEM_ESTORNO || ', ';
               END IF;
               V_SEM_ESTORNO := V_SEM_ESTORNO || FIELD_NUNOTA;
           END IF;

       END LOOP;

       P_MENSAGEM := V_QTD_GERADOS || ' estorno(s) gerado(s).';

       IF V_QTD_ERROS > 0 THEN
           P_MENSAGEM := P_MENSAGEM || '<br>Com erro (' || V_QTD_ERROS || '): ' || SUBSTR(V_ERROS, 4);
       END IF;

       IF V_SEM_ESTORNO IS NOT NULL THEN
           P_MENSAGEM := P_MENSAGEM || '<br>Sem provisão pendente (já estornado ou sem provisão): ' || V_SEM_ESTORNO;
       END IF;
END;
/
