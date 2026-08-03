CREATE OR REPLACE PROCEDURE         "ARG_STP_DESMARCARPROV" (
       P_CODUSU NUMBER,
       P_IDSESSAO VARCHAR2,
       P_QTDLINHAS NUMBER,
       P_MENSAGEM OUT VARCHAR2
) AS
       FIELD_NUNOTA NUMBER;
       V_QTDATU     NUMBER := 0;
       V_CONTAB     NUMBER := 0;
BEGIN
       FOR I IN 1..P_QTDLINHAS
       LOOP
           FIELD_NUNOTA := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNOTA');

           -- Verifica se o lançamento já está contabilizado na TCBINT
           SELECT COUNT(*)
             INTO V_CONTAB
             FROM TCBINT
            WHERE ORIGEM = 'E'
              AND NUNICO = FIELD_NUNOTA;

           IF V_CONTAB > 0 THEN
               RAISE_APPLICATION_ERROR(
                   -20001,
                   'A nota ' || FIELD_NUNOTA || ' já está contabilizada. ' ||
                   'Não é possível desmarcar a provisão. ' ||
                   'Entre em contato com a Contabilidade.'
               );
           END IF;

           -- Se TIPMOV = 'O' e ainda provisionado, desmarca
           UPDATE TGFCAB
              SET AD_PROVISIONA = 'N'
            WHERE NUNOTA = FIELD_NUNOTA
              AND TIPMOV = 'O'
              AND NVL(AD_PROVISIONA,'N') = 'S';

           V_QTDATU := V_QTDATU + SQL%ROWCOUNT;

       END LOOP;

       P_MENSAGEM := V_QTDATU || ' Pedido(s) desmarcada(s) como provisionada(s). (TIPMOV=O - PEDIDO DE COMPRAS)';

END;
/