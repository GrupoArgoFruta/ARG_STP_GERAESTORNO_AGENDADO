-- ============================================================================
-- Limpeza (PARTE 2, 05/08/2026): apaga os estornos gerados pela versão
-- ANTIGA (errada) de ARG_STP_GERAESTORNO_AGENDADO. Ver
-- ARG_QRY_ESTORNOS_REVISAO.sql (rode e revise ANTES de rodar isto) e o
-- cabeçalho de ARG_STP_GERAESTORNO_AGENDADO.sql pra entender a correção
-- (gatilho errado - não checava PENDENTE - e data errada - dia 1 do mês
-- seguinte em vez do dia do faturamento).
--
-- ATENÇÃO:
--   - Rode ARG_QRY_ESTORNOS_REVISAO.sql primeiro e confira o resultado
--     (quantidade de linhas/pedidos) antes de rodar isto.
--   - Este script NÃO tem COMMIT automático. Rode os dois comandos, confira
--     o ROWCOUNT de cada um (deve bater com QTD_LINHAS/QTD_PEDIDOS do
--     resumo da query de revisão), e só então dê COMMIT manualmente. Se algo
--     parecer errado, ROLLBACK.
--   - Escopo: só toca pedidos de compra (TIPMOV='O') com AD_PROVISIONA='S'
--     E AD_GERAESTORNO='S' (só quem passou pela ARG_STP_GERAESTORNO_AGENDADO)
--     cujo estorno tem COMPLHIST começando com 'ESTORNO AUTOMATICO -' - essa
--     é a marca da versão antiga; a versão corrigida grava sem "AUTOMATICO"
--     (ver linha ~145 da procedure), então este script nunca apaga estorno
--     gerado pela versão nova.
--   - AMBIENTE: confirmar antes de rodar (Treinamento e/ou Homologação) -
--     ainda não determinado onde a ação agendada uid 204 rodou de fato.
-- ============================================================================

-- 1) Apaga as linhas de estorno geradas pela versão antiga
DELETE FROM SANKHYA.TCBLAN E
 WHERE E.INDESTORNADO = 'S'
   AND E.COMPLHIST LIKE 'ESTORNO AUTOMATICO - LANC ORIGEM %'
   AND EXISTS (
         SELECT 1 FROM TGFCAB CAB
          WHERE CAB.NUNOTA        = E.AD_NUNOTAORIG
            AND CAB.TIPMOV        = 'O'
            AND CAB.AD_PROVISIONA = 'S'
            AND CAB.AD_GERAESTORNO = 'S'
       );

-- Confira aqui: o ROWCOUNT (ou o retorno do seu client) deve bater com
-- QTD_LINHAS do resumo da ARG_QRY_ESTORNOS_REVISAO.sql.

-- 2) Reseta a flag de status nos pedidos afetados, pra procedure corrigida
--    poder gerar o estorno certo na próxima execução do job
UPDATE TGFCAB CAB
   SET AD_GERAESTORNO = 'N'
 WHERE CAB.TIPMOV         = 'O'
   AND CAB.AD_PROVISIONA  = 'S'
   AND CAB.AD_GERAESTORNO = 'S'
   AND NOT EXISTS (
         -- só reseta quem NÃO tem mais nenhum estorno pendurado (o DELETE
         -- acima já rodou) - proteção extra caso exista algum estorno
         -- legítimo (gerado pela versão nova) que não deva ser mexido
         SELECT 1 FROM SANKHYA.TCBLAN E2
          WHERE E2.AD_NUNOTAORIG = CAB.NUNOTA
            AND E2.INDESTORNADO  = 'S'
       );

-- COMMIT;   -- << só depois de conferir os ROWCOUNTs acima
-- ROLLBACK; -- << se algo parecer errado
