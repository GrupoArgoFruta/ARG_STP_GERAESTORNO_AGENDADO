-- ============================================================================
-- Consulta de acompanhamento: status da provisão de um Pedido de Compra
-- (TIPMOV = 'O') após o fluxo dos botões ARG_STP_MARCARPROV / ARG_STP_DESMARCARPROV.
--
-- Contexto: o botão só grava a flag AD_PROVISIONA em TGFCAB. Quem efetivamente
-- gera os lançamentos contábeis é o mecanismo NATIVO de contabilização do
-- Sankhya (agendador), disparado pela fórmula em TGFCTB que referencia
-- CAB.AD_PROVISIONA (mesma fórmula usada no WHERE do ARG_STP_MARCARPROV).
-- Cada lançamento gerado pelo agendador fica rastreado em TCBINT
-- (ORIGEM='E', NUNICO=NUNOTA do pedido) - é exatamente essa tabela que o
-- ARG_STP_DESMARCARPROV já consulta para bloquear a desmarcação de pedido
-- contabilizado.
--
-- Esta consulta junta TGFCAB -> TCBINT -> TCBLAN para mostrar, por pedido:
--   - se a PROVISÃO (1ª perna, INDESTORNADO IN ('N','F')) já foi lançada;
--   - se o ESTORNO (2ª perna, INDESTORNADO = 'S') já foi lançado.
--
-- ATENÇÃO: a junção TCBINT -> TCBLAN por CODEMP+REFERENCIA+NUMLOTE+NUMLANC é
-- a chave natural da TCBLAN (mesma usada no ARG_STP_GERAESTORNO_AGENDADO),
-- mas ainda NÃO foi validada com dados reais de um pedido já processado pelo
-- agendador nativo - rodar contra o pedido 812851 em Treinamento (depois que
-- o agendador tiver processado a marcação) para confirmar que retorna as
-- linhas esperadas antes de usar isso em qualquer tela/dashboard.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) DETALHE: uma linha por lançamento vinculado ao pedido
-- ---------------------------------------------------------------------------
SELECT
    CAB.NUNOTA,
    CAB.NUMNOTA,
    CAB.DTNEG,
    PAR.NOMEPARC,
    CAB.AD_PROVISIONA,
    LAN.NUMLANC,
    LAN.NUMLOTE,
    LAN.REFERENCIA          AS DT_LANCAMENTO,
    LAN.TIPLANC,             -- D=Débito / R=Crédito
    LAN.VLRLANC,
    LAN.CODCTACTB,
    LAN.CODCENCUS,
    LAN.INDESTORNADO,        -- N=não é estorno / F=foi estornado / S=é o estorno / A=estorno já estornado
    LAN.COMPLHIST
FROM TGFCAB CAB
JOIN TGFPAR PAR
  ON PAR.CODPARC = CAB.CODPARC
LEFT JOIN TCBINT TCI
  ON TCI.ORIGEM = 'E'
 AND TCI.NUNICO = CAB.NUNOTA
LEFT JOIN TCBLAN LAN
  ON LAN.CODEMP     = TCI.CODEMP
 AND LAN.REFERENCIA = TCI.REFERENCIA
 AND LAN.NUMLOTE    = TCI.NUMLOTE
 AND LAN.NUMLANC    = TCI.NUMLANC
WHERE CAB.TIPMOV = 'O'
  AND CAB.NUNOTA = 812851   -- << trocar pelo pedido de teste
ORDER BY LAN.REFERENCIA, LAN.SEQUENCIA;


-- ---------------------------------------------------------------------------
-- 2) RESUMO: uma linha por pedido, com flags PROVISAO_LANCADA / ESTORNO_LANCADO
--    (use esta para monitorar vários pedidos AD_PROVISIONA = 'S' de uma vez)
-- ---------------------------------------------------------------------------
SELECT
    CAB.NUNOTA,
    CAB.NUMNOTA,
    CAB.DTNEG,
    PAR.NOMEPARC,
    CAB.AD_PROVISIONA,
    CASE WHEN MAX(CASE WHEN LAN.INDESTORNADO IN ('N','F') THEN 1 END) = 1
         THEN 'S' ELSE 'N' END                                   AS PROVISAO_LANCADA,
    MIN(CASE WHEN LAN.INDESTORNADO IN ('N','F') THEN LAN.REFERENCIA END) AS DT_PROVISAO,
    CASE WHEN MAX(CASE WHEN LAN.INDESTORNADO = 'S' THEN 1 END) = 1
         THEN 'S' ELSE 'N' END                                   AS ESTORNO_LANCADO,
    MIN(CASE WHEN LAN.INDESTORNADO = 'S' THEN LAN.REFERENCIA END)       AS DT_ESTORNO
FROM TGFCAB CAB
JOIN TGFPAR PAR
  ON PAR.CODPARC = CAB.CODPARC
LEFT JOIN TCBINT TCI
  ON TCI.ORIGEM = 'E'
 AND TCI.NUNICO = CAB.NUNOTA
LEFT JOIN TCBLAN LAN
  ON LAN.CODEMP     = TCI.CODEMP
 AND LAN.REFERENCIA = TCI.REFERENCIA
 AND LAN.NUMLOTE    = TCI.NUMLOTE
 AND LAN.NUMLANC    = TCI.NUMLANC
WHERE CAB.TIPMOV = 'O'
  AND (CAB.AD_PROVISIONA = 'S' OR CAB.NUNOTA = 812851)  -- << ajustar filtro
GROUP BY CAB.NUNOTA, CAB.NUMNOTA, CAB.DTNEG, PAR.NOMEPARC, CAB.AD_PROVISIONA
ORDER BY CAB.NUNOTA;
