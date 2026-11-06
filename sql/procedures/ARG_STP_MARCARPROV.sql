/*
 * ARG_STP_MARCARPROV - botao "PROVISIONAR CONTABILIDADE (TIPMOV PEDIDO)"
 *
 * Regras inalteradas: a trava de data continua dando erro e desfazendo o lote.
 * Novidade: pedido que nao foi marcado agora aparece na mensagem com o MOTIVO
 * (antes a mensagem so dizia "0 marcada(s)").
 *
 * ATENCAO ao compilar no DBeaver: NAO formatar. O formatador quebra "END LOOP;" em
 * "END" / "LOOP;" e o bloco fica INVALID. Abrir o arquivo sem formatar e rodar com Alt+X.
 */
CREATE OR REPLACE PROCEDURE         "ARG_STP_MARCARPROV" (
       P_CODUSU NUMBER,
       P_IDSESSAO VARCHAR2,
       P_QTDLINHAS NUMBER,
       P_MENSAGEM OUT VARCHAR2
) AS
       -- Prazo de carência para provisionar notas do mês anterior:
       -- até o N-ésimo dia útil (segunda a sexta) do mês corrente.
       -- Feriados não entram na conta.
       C_DIAS_UTEIS CONSTANT NUMBER := 5;
       C_MAX_MSG    CONSTANT NUMBER := 3500;

       FIELD_NUNOTA NUMBER;
       V_QTDATU     NUMBER := 0;
       V_LIN        NUMBER;
       V_DTREF      DATE;
       V_LIMITE     DATE;      -- último dia do prazo de carência (N-ésimo dia útil do mês corrente)
       V_CONT       NUMBER := 0;
       V_MESNOTA    DATE;
       V_MESATU     DATE;
       V_MESANT     DATE;

       V_TIPMOV     TGFCAB.TIPMOV%TYPE;
       V_PENDENTE   TGFCAB.PENDENTE%TYPE;
       V_PROV       TGFCAB.AD_PROVISIONA%TYPE;
       V_CODTIPOPER TGFCAB.CODTIPOPER%TYPE;
       V_QTD        NUMBER;
       V_NFDEST     NUMBER;
       V_NUMNF      NUMBER;
       V_MOTIVO     VARCHAR2(500);
       V_RECUSADAS  NUMBER := 0;
       V_LISTA      VARCHAR2(32000);
BEGIN
       V_MESATU := TRUNC(SYSDATE,'MM');
       V_MESANT := ADD_MONTHS(V_MESATU,-1);

       -- Conta os dias úteis a partir do dia 1 (TRUNC 'IW' = segunda-feira: 0=Seg ... 4=Sex)
       V_LIMITE := V_MESATU - 1;
       WHILE V_CONT < C_DIAS_UTEIS LOOP
           V_LIMITE := V_LIMITE + 1;
           IF V_LIMITE - TRUNC(V_LIMITE,'IW') < 5 THEN
               V_CONT := V_CONT + 1;
           END IF;
       END LOOP;

       FOR I IN 1..P_QTDLINHAS
       LOOP
           FIELD_NUNOTA := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNOTA');

           -- Data de entrada da nota; sem ela, usa a data de negociação
           SELECT NVL(DTENTSAI, DTNEG), TIPMOV, PENDENTE, AD_PROVISIONA, CODTIPOPER
             INTO V_DTREF, V_TIPMOV, V_PENDENTE, V_PROV, V_CODTIPOPER
             FROM TGFCAB
            WHERE NUNOTA = FIELD_NUNOTA;

           V_MESNOTA := TRUNC(V_DTREF,'MM');

           -- Válido se: nota é do mês corrente
           --         OU nota é do mês anterior E ainda estamos dentro do prazo de carência
           IF NOT ( V_MESNOTA = V_MESATU
                    OR ( V_MESNOTA = V_MESANT AND TRUNC(SYSDATE) <= V_LIMITE ) )
           THEN
               RAISE_APPLICATION_ERROR(
                   -20002,
                   'A nota ' || FIELD_NUNOTA || ' tem data de entrada (' ||
                   TO_CHAR(V_DTREF,'DD/MM/YYYY') || ') fora do período permitido. ' ||
                   'Só é permitido provisionar notas do mês corrente (notas do mês ' ||
                   'anterior somente até ' || TO_CHAR(V_LIMITE,'DD/MM/YYYY') || ').'
               );
           END IF;

           -- Se TIPMOV = 'O', atualiza AD_PROVISIONA = 'S'
           UPDATE TGFCAB
              SET AD_PROVISIONA = 'S'
            WHERE NUNOTA = FIELD_NUNOTA
              AND TIPMOV = 'O'
              AND PENDENTE = 'S'
              AND NVL(AD_PROVISIONA,'N') = 'N'
              AND CODTIPOPER IN (SELECT CODTIPOPER FROM TGFCTB WHERE FORMULA LIKE '%CAB.AD_PROVISIONA%');

           V_LIN := SQL%ROWCOUNT;
           V_QTDATU := V_QTDATU + V_LIN;

           -- Nao marcou: descobre o motivo para avisar o usuario
           IF V_LIN = 0 THEN
               IF V_TIPMOV <> 'O' THEN
                   V_MOTIVO := 'nao e pedido de compra (TIPMOV ' || V_TIPMOV || ').';
               ELSIF NVL(V_PROV, 'N') = 'S' THEN
                   V_MOTIVO := 'ja esta provisionado.';
               ELSIF V_PENDENTE <> 'S' THEN
                   SELECT MIN(NUNOTA) INTO V_NFDEST FROM TGFVAR WHERE NUNOTAORIG = FIELD_NUNOTA;
                   IF V_NFDEST IS NOT NULL THEN
                       SELECT MAX(NUMNOTA) INTO V_NUMNF FROM TGFCAB WHERE NUNOTA = V_NFDEST;
                       V_MOTIVO := 'pedido ja faturado pela NF ' || V_NUMNF ||
                                   ' (nro unico ' || V_NFDEST || '); so pedido pendente, sem NF, pode ser provisionado.';
                   ELSE
                       V_MOTIVO := 'pedido nao esta pendente (sem NF ligada; cancelado ou encerrado).';
                   END IF;
               ELSE
                   SELECT COUNT(*) INTO V_QTD
                     FROM TGFCTB
                    WHERE CODTIPOPER = V_CODTIPOPER
                      AND FORMULA LIKE '%CAB.AD_PROVISIONA%';
                   IF V_QTD = 0 THEN
                       V_MOTIVO := 'a TOP ' || V_CODTIPOPER ||
                                   ' nao esta na regra de provisao (avisar o TI/Contabilidade).';
                   ELSE
                       V_MOTIVO := 'nao foi possivel marcar (confirmar com o TI).';
                   END IF;
               END IF;

               V_RECUSADAS := V_RECUSADAS + 1;
               IF LENGTH(V_LISTA) IS NULL OR LENGTH(V_LISTA) < C_MAX_MSG THEN
                   V_LISTA := V_LISTA || '<br>Nota ' || FIELD_NUNOTA || ': ' || V_MOTIVO;
               END IF;
           END IF;

       END LOOP;

       P_MENSAGEM := V_QTDATU || ' Pedido(s) marcada(s) como provisionada(s). (TIPMOV=O - PEDIDO DE COMPRAS)';
       IF V_RECUSADAS > 0 THEN
           P_MENSAGEM := P_MENSAGEM || '<br><br>Nao marcado(s): ' || V_RECUSADAS || V_LISTA;
           IF LENGTH(V_LISTA) >= C_MAX_MSG THEN
               P_MENSAGEM := P_MENSAGEM || '<br>... (lista cortada; ha mais notas nao marcadas)';
           END IF;
       END IF;

END;
/
