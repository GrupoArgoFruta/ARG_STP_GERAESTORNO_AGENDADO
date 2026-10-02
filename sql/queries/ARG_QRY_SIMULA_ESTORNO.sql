-- ============================================================================
-- SIMULAÇÃO (só leitura) do que a ARG_STP_GERAESTORNO_AGENDADO vai gerar na
-- próxima execução: um registro por lançamento de ORIGEM elegível, com a
-- REFERENCIA/DTMOV que o estorno vai receber pela regra da CORREÇÃO 7
-- (estorno no mês de entrada da NF).
--
-- Mesmo filtro do cursor principal da procedure. Rodar antes de recompilar
-- para a contabilidade conferir, e de novo depois de executar (deve voltar
-- vazio, exceto os pedidos que falharam).
--
-- Colunas:
--   DT_NF          entrada da 1ª NF de compra vinculada ao pedido (TGFVAR)
--   REF_ESTORNO    competência do estorno (mês de DTMOV_ESTORNO)
--   DTMOV_ESTORNO  data do estorno = DT_NF, nunca antes do mês da provisão
--   REF_REGRA_ANT  competência que a versão anterior usaria (mês seguinte à
--                  provisão) - só para comparação
--   PREVISAO       'FALHA: PERIODO FECHADO' quando o DTMOV do estorno cai em
--                  período contábil fechado (AD_FECHAMOD); esses pedidos vão
--                  aparecer no erro do job e não são estornados
-- ============================================================================
SELECT X.NUNOTA,
       X.NOMEPARC,
       X.CODEMP,
       X.NUMLOTE,
       X.NUMLANC,
       TO_CHAR(X.REFERENCIA, 'MM/YYYY')                         AS REF_PROVISAO,
       X.VLR_PROVISAO,
       X.DT_NF,
       TO_CHAR(TRUNC(X.DTMOV_ESTORNO, 'MM'), 'MM/YYYY')         AS REF_ESTORNO,
       X.DTMOV_ESTORNO,
       TO_CHAR(ADD_MONTHS(TRUNC(X.REFERENCIA, 'MM'), 1), 'MM/YYYY') AS REF_REGRA_ANT,
       -- Mesma regra da trigger ARG_INC_UPD_DEL_TCBLAN (fechamento em AD_FECHAMOD)
       CASE WHEN X.DTMOV_ESTORNO <= (SELECT LAST_DAY(TRUNC(MAX(F.PERFECHA), 'MM'))
                                       FROM AD_FECHAMOD F WHERE F.CONTABIL = 'S')
            THEN 'FALHA: PERIODO FECHADO'
            ELSE 'OK'
       END                                                      AS PREVISAO
  FROM (
        SELECT O.*,
               GREATEST(O.DT_NF, TRUNC(O.REFERENCIA, 'MM')) AS DTMOV_ESTORNO
          FROM (
                SELECT DISTINCT L.CODEMP, L.REFERENCIA, L.NUMLOTE, L.NUMLANC, CAB.NUNOTA,
                       NVL(PAR.RAZAOSOCIAL, PAR.NOMEPARC) AS NOMEPARC,
                       (SELECT SUM(L2.VLRLANC) FROM TCBLAN L2
                         WHERE L2.CODEMP = L.CODEMP AND L2.REFERENCIA = L.REFERENCIA
                           AND L2.NUMLOTE = L.NUMLOTE AND L2.NUMLANC = L.NUMLANC
                           AND L2.TIPLANC = 'D') AS VLR_PROVISAO,
                       (SELECT TRUNC(MIN(NVL(DEST.DTENTSAI, DEST.DTNEG)))
                          FROM TGFVAR VAR
                          JOIN TGFCAB DEST ON DEST.NUNOTA = VAR.NUNOTA
                         WHERE VAR.NUNOTAORIG = CAB.NUNOTA
                           AND DEST.TIPMOV = 'C') AS DT_NF
                  FROM TCBINT TCI
                  JOIN TGFCAB CAB ON CAB.NUNOTA = TCI.NUNICO
                  JOIN TCBLAN L
                    ON L.CODEMP     = TCI.CODEMP
                   AND L.REFERENCIA = TCI.REFERENCIA
                   AND L.NUMLOTE    = TCI.NUMLOTE
                   AND L.NUMLANC    = TCI.NUMLANC
                  JOIN TGFPAR PAR ON PAR.CODPARC = CAB.CODPARC
                 WHERE TCI.ORIGEM = 'E'
                   AND CAB.TIPMOV = 'O'
                   AND CAB.AD_PROVISIONA = 'S'
                   AND NVL(CAB.AD_GERAESTORNO, 'N') <> 'S'
                   AND EXISTS (
                         SELECT 1
                           FROM TGFVAR VAR
                           JOIN TGFCAB DEST ON DEST.NUNOTA = VAR.NUNOTA
                          WHERE VAR.NUNOTAORIG = CAB.NUNOTA
                            AND DEST.TIPMOV = 'C'
                       )
                   AND L.INDESTORNADO = 'N'
                   AND NOT EXISTS (
                         SELECT 1 FROM TCBLAN E
                          WHERE E.AD_NUNOTAORIG = CAB.NUNOTA
                            AND E.CODEMP = L.CODEMP
                            AND E.INDESTORNADO = 'S'
                       )
               ) O
       ) X
 ORDER BY X.DTMOV_ESTORNO, X.NUNOTA;
