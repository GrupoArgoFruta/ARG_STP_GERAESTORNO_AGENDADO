-- ============================================================================
-- Consulta de REVISÃO (05/08/2026, otimizada em 05/08/2026): lista todos os
-- estornos que a ARG_STP_GERAESTORNO_AGENDADO já gerou usando a regra ANTIGA
-- (errada) - disparava sem checar TGFCAB.PENDENTE e datava sempre no dia 1
-- do mês seguinte à origem, em vez de checar PENDENTE='N' (faturado/
-- encerrado) e datar no dia da execução do job. Ver
-- ARG_STP_GERAESTORNO_AGENDADO.sql para o detalhe da correção.
--
-- Objetivo: dar pra revisar manualmente ANTES de decidir apagar essas linhas
-- de TCBLAN. Este script é SOMENTE LEITURA - nenhum DELETE/UPDATE aqui.
--
-- PERFORMANCE (corrigido - versão anterior estava lenta demais pra rodar):
-- a primeira versão partia de TCBLAN inteiro com COMPLHIST LIKE '...%'
-- (texto livre, sem índice) - varria a tabela de lançamentos contábeis da
-- empresa toda. Esta versão parte de TGFCAB filtrado (TIPMOV='O' AND
-- AD_PROVISIONA='S' AND AD_GERAESTORNO='S' - conjunto pequeno, só pedidos
-- que passaram por este fluxo custom) e junta em TCBLAN por AD_NUNOTAORIG
-- (igualdade, chave de rastreio já usada pelo resto do projeto - ver
-- ARG_QRY_STATUSPROVISAO.sql) + INDESTORNADO='S'. Não precisa mais do LIKE
-- em COMPLHIST: AD_GERAESTORNO='S' já restringe exatamente aos pedidos que
-- passaram pela ARG_STP_GERAESTORNO_AGENDADO (é a própria procedure que seta
-- essa flag depois de gerar, linha ~155 do .sql).
-- ============================================================================

SELECT
    E.CODEMP,
    E.NUMLANC                              AS NUMLANC_ESTORNO,
    E.REFERENCIA                           AS DT_ESTORNO_GERADO,     -- data que a procedure usou (regra antiga = sempre dia 1 do mês)
    E.VLRLANC,
    E.CODCTACTB,
    CAB.NUNOTA                              AS NUNOTA_PEDIDO,
    CAB.NUMNOTA,
    CAB.DTNEG,
    CAB.PENDENTE                            AS PENDENTE_ATUAL,        -- 'N' = já faturou/encerrou hoje; 'S' = ainda pendente (esse estorno NUNCA deveria ter sido gerado)
    CAB.AD_PROVISIONA,
    CAB.AD_GERAESTORNO,
    E.COMPLHIST,
    CASE
        WHEN CAB.PENDENTE = 'S' THEN 'ERRADO - pedido ainda pendente, estorno não deveria existir'
        WHEN CAB.PENDENTE = 'N' THEN 'REVISAR DATA - trocar para a data real do faturamento, não dia 1 do mês'
    END                                      AS DIAGNOSTICO
FROM TGFCAB CAB
JOIN SANKHYA.TCBLAN E
  ON E.AD_NUNOTAORIG = CAB.NUNOTA
 AND E.INDESTORNADO  = 'S'
WHERE CAB.TIPMOV          = 'O'
  AND CAB.AD_PROVISIONA   = 'S'
  AND CAB.AD_GERAESTORNO  = 'S'
ORDER BY CAB.NUNOTA, E.REFERENCIA, E.SEQUENCIA;


-- ---------------------------------------------------------------------------
-- RESUMO: quantidade de linhas por diagnóstico, pra ter uma ideia do volume
-- antes de decidir o que fazer.
-- ---------------------------------------------------------------------------
SELECT
    CASE
        WHEN CAB.PENDENTE = 'S' THEN 'ERRADO - pedido ainda pendente'
        WHEN CAB.PENDENTE = 'N' THEN 'REVISAR DATA - pedido já faturado, mas data errada'
    END                              AS DIAGNOSTICO,
    COUNT(*)                         AS QTD_LINHAS,
    COUNT(DISTINCT CAB.NUNOTA)       AS QTD_PEDIDOS
FROM TGFCAB CAB
JOIN SANKHYA.TCBLAN E
  ON E.AD_NUNOTAORIG = CAB.NUNOTA
 AND E.INDESTORNADO  = 'S'
WHERE CAB.TIPMOV          = 'O'
  AND CAB.AD_PROVISIONA   = 'S'
  AND CAB.AD_GERAESTORNO  = 'S'
GROUP BY CASE
    WHEN CAB.PENDENTE = 'S' THEN 'ERRADO - pedido ainda pendente'
    WHEN CAB.PENDENTE = 'N' THEN 'REVISAR DATA - pedido já faturado, mas data errada'
END;
