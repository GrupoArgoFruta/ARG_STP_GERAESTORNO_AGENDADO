CREATE OR REPLACE PROCEDURE         "ARG_STP_MARCARPROV" (
       P_CODUSU NUMBER,
       P_IDSESSAO VARCHAR2,
       P_QTDLINHAS NUMBER,
       P_MENSAGEM OUT VARCHAR2
) AS
       FIELD_NUNOTA NUMBER;
       V_QTDATU     NUMBER := 0;
       V_DTNEG      DATE;
BEGIN
       FOR I IN 1..P_QTDLINHAS
       LOOP
           FIELD_NUNOTA := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNOTA');

           -- Busca a data de negociação da nota
           SELECT DTNEG
             INTO V_DTNEG
             FROM TGFCAB
            WHERE NUNOTA = FIELD_NUNOTA;

           -- Se DTNEG estiver fora do mês corrente, aborta e avisa
           IF TRUNC(V_DTNEG,'MM') <> TRUNC(SYSDATE,'MM') THEN
               RAISE_APPLICATION_ERROR(
                   -20002,
                   'A nota ' || FIELD_NUNOTA || ' tem data de negociação (' ||
                   TO_CHAR(V_DTNEG,'DD/MM/YYYY') || ') fora do mês corrente. ' ||
                   'Só é permitido provisionar notas do mês atual.'
               );
           END IF;

           -- Se TIPMOV = 'O', atualiza AD_PROVISIONA = 'S'
           UPDATE TGFCAB
              SET AD_PROVISIONA = 'S'
            WHERE NUNOTA = FIELD_NUNOTA
              AND TIPMOV = 'O'
              AND NVL(AD_PROVISIONA,'N') = 'N'
              AND CODTIPOPER IN (SELECT CODTIPOPER FROM TGFCTB WHERE FORMULA LIKE '%CAB.AD_PROVISIONA%');

           V_QTDATU := V_QTDATU + SQL%ROWCOUNT;

       END LOOP;

       P_MENSAGEM := V_QTDATU || ' Pedido(s) marcada(s) como provisionada(s). (TIPMOV=O - PEDIDO DE COMPRAS)';

END;
/