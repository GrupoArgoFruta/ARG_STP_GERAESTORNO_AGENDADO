-- ============================================================================
-- Refazer estornos do botão 320 gerados com a regra da CORREÇÃO 8
-- (05/11/2026)
--
-- Entre 03/11 e a compilação da CORREÇÃO 9, o botão 320 (ARG_STP_ESTORNO_MANUAL)
-- datava o estorno na 1ª NF ou, sem NF, no dia do clique. Exemplo: pedido
-- 865665, provisão 09/2026, estorno em 04/11/2026. A regra certa para o
-- botão é o dia 1 do mês seguinte ao da provisão (01/10/2026 nesse caso).
--
-- Passo a passo:
--   1) Compilar a CORREÇÃO 9 (ARG_STP_GERAESTORNO_MANUAL.sql).
--   2) Rodar a PARTE 1 e conferir os pedidos (devem ser os 3 feitos pelo
--      botão). Estorno com DTMOV = DT_NF pode ter vindo do job, que segue
--      a regra da NF e não deve ser mexido.
--   3) Pôr os NUNOTA na PARTE 2, rodar, conferir o ROWCOUNT (2 linhas por
--      pedido na provisão simples) e dar COMMIT.
--   4) Selecionar os pedidos no dash 384 e clicar de novo no botão 320.
--      A idempotência olha só se existe estorno (INDESTORNADO='S'), então
--      depois do DELETE o botão gera de novo, já em 01/<mês seguinte>.
--      Se esse mês estiver fechado (AD_FECHAMOD), o botão lista o pedido
--      com erro.
-- ============================================================================

-- PARTE 1: estornos fora da regra "mês seguinte à provisão"
SELECT E.AD_NUNOTAORIG                         AS PEDIDO,
       TO_CHAR(O.REFERENCIA, 'MM/YYYY')        AS REF_PROVISAO,
       TO_CHAR(O.DTMOV, 'DD/MM/YYYY')          AS DTMOV_PROVISAO,
       TO_CHAR(E.REFERENCIA, 'MM/YYYY')        AS REF_ESTORNO,
       TO_CHAR(E.DTMOV, 'DD/MM/YYYY')          AS DTMOV_ESTORNO,
       TO_CHAR(ADD_MONTHS(TRUNC(O.REFERENCIA, 'MM'), 1), 'DD/MM/YYYY') AS DATA_CERTA,
       (SELECT TO_CHAR(MIN(NVL(D.DTENTSAI, D.DTNEG)), 'DD/MM/YYYY')
          FROM TGFVAR V
          JOIN TGFCAB D ON D.NUNOTA = V.NUNOTA
         WHERE V.NUNOTAORIG = E.AD_NUNOTAORIG
           AND D.TIPMOV = 'C')                 AS DT_NF,
       E.NUMLOTE, E.NUMLANC,
       COUNT(*)                                AS LINHAS,
       SUM(CASE WHEN E.TIPLANC = 'D' THEN E.VLRLANC END) AS VALOR
  FROM SANKHYA.TCBLAN E
  JOIN TCBINT TCI
    ON TCI.NUNICO = E.AD_NUNOTAORIG
   AND TCI.ORIGEM = 'E'
   AND TCI.CODEMP = E.CODEMP
  JOIN SANKHYA.TCBLAN O
    ON O.CODEMP     = TCI.CODEMP
   AND O.REFERENCIA = TCI.REFERENCIA
   AND O.NUMLOTE    = TCI.NUMLOTE
   AND O.NUMLANC    = TCI.NUMLANC
   AND O.SEQUENCIA  = 1
 WHERE E.INDESTORNADO = 'S'
   AND E.DTMOV >= DATE '2026-11-01'
   AND TRUNC(E.REFERENCIA, 'MM') <> ADD_MONTHS(TRUNC(O.REFERENCIA, 'MM'), 1)
 GROUP BY E.AD_NUNOTAORIG, O.REFERENCIA, O.DTMOV, E.REFERENCIA, E.DTMOV, E.NUMLOTE, E.NUMLANC
 ORDER BY E.DTMOV, E.AD_NUNOTAORIG;


-- PARTE 2: apaga o estorno dos pedidos conferidos na PARTE 1.
-- Trocar a lista abaixo pelos 3 pedidos. Sem COMMIT automático.
DELETE FROM SANKHYA.TCBLAN E
 WHERE E.INDESTORNADO = 'S'
   AND E.AD_NUNOTAORIG IN (865665 /* , <pedido 2>, <pedido 3> */)
   AND E.DTMOV >= DATE '2026-11-01';

-- COMMIT;   -- << só depois de conferir o ROWCOUNT
-- ROLLBACK; -- << se algo parecer errado
