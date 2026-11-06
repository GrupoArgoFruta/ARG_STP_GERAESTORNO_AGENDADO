/*
 * ARG_STP_DESMARCARPROV - botao "DESPROVISIONAR CONTABILIDADE (TIPMOV PEDIDO)"
 *
 * Regras inalteradas: nota ja contabilizada continua dando erro e desfazendo o lote.
 * Novidade: pedido que nao foi desmarcado agora aparece na mensagem com o MOTIVO
 * (antes a mensagem so dizia "0 desmarcada(s)").
 *
 * ATENCAO ao compilar no DBeaver: NAO formatar. O formatador quebra "END LOOP;" em
 * "END" / "LOOP;" e o bloco fica INVALID. Abrir o arquivo sem formatar e rodar com Alt+X.
 */
CREATE OR REPLACE PROCEDURE         "ARG_STP_DESMARCARPROV" (
       P_CODUSU NUMBER,
       P_IDSESSAO VARCHAR2,
       P_QTDLINHAS NUMBER,
       P_MENSAGEM OUT VARCHAR2
) AS
       C_MAX_MSG    CONSTANT NUMBER := 3500;

       FIELD_NUNOTA NUMBER;
       V_QTDATU     NUMBER := 0;
       V_LIN        NUMBER;
       V_CONTAB     NUMBER := 0;
       V_TIPMOV     TGFCAB.TIPMOV%TYPE;
       V_PROV       TGFCAB.AD_PROVISIONA%TYPE;
       V_MOTIVO     VARCHAR2(500);
       V_RECUSADAS  NUMBER := 0;
       V_LISTA      VARCHAR2(32000);
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

           V_LIN := SQL%ROWCOUNT;
           V_QTDATU := V_QTDATU + V_LIN;

           -- Nao desmarcou: descobre o motivo para avisar o usuario
           IF V_LIN = 0 THEN
               BEGIN
                   SELECT TIPMOV, AD_PROVISIONA INTO V_TIPMOV, V_PROV
                     FROM TGFCAB
                    WHERE NUNOTA = FIELD_NUNOTA;
                   IF V_TIPMOV <> 'O' THEN
                       V_MOTIVO := 'nao e pedido de compra (TIPMOV ' || V_TIPMOV || ').';
                   ELSIF NVL(V_PROV, 'N') <> 'S' THEN
                       V_MOTIVO := 'nao esta provisionado.';
                   ELSE
                       V_MOTIVO := 'nao foi possivel desmarcar (confirmar com o TI).';
                   END IF;
               EXCEPTION
                   WHEN NO_DATA_FOUND THEN
                       V_MOTIVO := 'nota nao encontrada.';
               END;

               V_RECUSADAS := V_RECUSADAS + 1;
               IF LENGTH(V_LISTA) IS NULL OR LENGTH(V_LISTA) < C_MAX_MSG THEN
                   V_LISTA := V_LISTA || '<br>Nota ' || FIELD_NUNOTA || ': ' || V_MOTIVO;
               END IF;
           END IF;

       END LOOP;

       P_MENSAGEM := V_QTDATU || ' Pedido(s) desmarcada(s) como provisionada(s). (TIPMOV=O - PEDIDO DE COMPRAS)';
       IF V_RECUSADAS > 0 THEN
           P_MENSAGEM := P_MENSAGEM || '<br><br>Nao desmarcado(s): ' || V_RECUSADAS || V_LISTA;
           IF LENGTH(V_LISTA) >= C_MAX_MSG THEN
               P_MENSAGEM := P_MENSAGEM || '<br>... (lista cortada; ha mais notas nao desmarcadas)';
           END IF;
       END IF;

END;
/
