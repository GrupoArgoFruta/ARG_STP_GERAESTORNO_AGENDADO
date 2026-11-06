/*
 * ARG_STP_PROVISAO_PEDIDO - botao unico "Provisionar / Desprovisionar pedido de compra"
 *
 * Junta ARG_STP_MARCARPROV e ARG_STP_DESMARCARPROV (que continuam como estao ate a
 * validacao). O usuario escolhe a acao no parametro ACAO do botao:
 *     P = Provisionar      D = Desprovisionar
 *
 * Diferenca para as procedures antigas: cada nota e avaliada sozinha e a mensagem de retorno
 * diz o MOTIVO de cada nota recusada. Nota recusada nao desfaz o lote: as validas sao
 * processadas e as recusadas aparecem na lista.
 *
 * Regras de PROVISIONAR (mesmas de ARG_STP_MARCARPROV):
 *   - TIPMOV = 'O' (pedido de compra);
 *   - AD_PROVISIONA ainda nao e 'S';
 *   - PENDENTE = 'S' (pedido ainda sem NF);
 *   - CODTIPOPER existe em TGFCTB com FORMULA LIKE '%CAB.AD_PROVISIONA%';
 *   - data de entrada (DTENTSAI, senao DTNEG) no mes corrente, ou no mes anterior ate o
 *     5o dia util do mes corrente (C_DIAS_UTEIS, feriado nao entra na conta).
 * Regras de DESPROVISIONAR (mesmas de ARG_STP_DESMARCARPROV):
 *   - TIPMOV = 'O' e AD_PROVISIONA = 'S';
 *   - lancamento nao contabilizado (TCBINT ORIGEM 'E' e NUNICO = NUNOTA).
 *
 * Configuracao do botao (TSIBTA): tipo Procedure, instancia CabecalhoNota, parametro
 *   ACAO  tipo Lista de opcoes  P=Provisionar;D=Desprovisionar  (obrigatorio).
 *
 * ATENCAO ao compilar no DBeaver: NAO formatar. O formatador quebra "END LOOP;" em
 * "END" / "LOOP;" e o bloco fica INVALID. Abrir o arquivo sem formatar e rodar com Alt+X.
 */
CREATE OR REPLACE PROCEDURE "ARG_STP_PROVISAO_PEDIDO" (
       P_CODUSU    NUMBER,
       P_IDSESSAO  VARCHAR2,
       P_QTDLINHAS NUMBER,
       P_MENSAGEM  OUT VARCHAR2
) AS
       C_DIAS_UTEIS CONSTANT NUMBER := 5;
       C_MAX_MSG    CONSTANT NUMBER := 3500;

       V_ACAO       VARCHAR2(1);
       V_NUNOTA     NUMBER;
       V_TIPMOV     TGFCAB.TIPMOV%TYPE;
       V_PENDENTE   TGFCAB.PENDENTE%TYPE;
       V_PROV       TGFCAB.AD_PROVISIONA%TYPE;
       V_CODTIPOPER TGFCAB.CODTIPOPER%TYPE;
       V_DTREF      DATE;
       V_LIMITE     DATE;
       V_CONT       NUMBER := 0;
       V_MESATU     DATE;
       V_MESANT     DATE;
       V_MESNOTA    DATE;
       V_QTD        NUMBER;
       V_NFDEST     NUMBER;
       V_NUMNF      NUMBER;
       V_MOTIVO     VARCHAR2(500);

       V_OK         NUMBER := 0;
       V_RECUSADAS  NUMBER := 0;
       V_LISTA      VARCHAR2(32000);
BEGIN
       V_ACAO := UPPER(TRIM(ACT_TXT_PARAM(P_IDSESSAO, 'ACAO')));
       IF V_ACAO IS NULL OR V_ACAO NOT IN ('P', 'D') THEN
           RAISE_APPLICATION_ERROR(-20001,
               'Escolha a acao: Provisionar ou Desprovisionar.');
       END IF;

       -- Limite do prazo de carencia: N-esimo dia util do mes corrente (TRUNC 'IW' = segunda: 0=Seg ... 4=Sex)
       V_MESATU := TRUNC(SYSDATE, 'MM');
       V_MESANT := ADD_MONTHS(V_MESATU, -1);
       V_LIMITE := V_MESATU - 1;
       WHILE V_CONT < C_DIAS_UTEIS LOOP
           V_LIMITE := V_LIMITE + 1;
           IF V_LIMITE - TRUNC(V_LIMITE, 'IW') < 5 THEN
               V_CONT := V_CONT + 1;
           END IF;
       END LOOP;

       FOR I IN 1..P_QTDLINHAS
       LOOP
           V_NUNOTA := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNOTA');
           V_MOTIVO := NULL;

           BEGIN
               SELECT TIPMOV, PENDENTE, AD_PROVISIONA, CODTIPOPER, NVL(DTENTSAI, DTNEG)
                 INTO V_TIPMOV, V_PENDENTE, V_PROV, V_CODTIPOPER, V_DTREF
                 FROM TGFCAB
                WHERE NUNOTA = V_NUNOTA;
           EXCEPTION
               WHEN NO_DATA_FOUND THEN
                   V_MOTIVO := 'nota nao encontrada.';
           END;

           IF V_MOTIVO IS NULL THEN
               IF V_TIPMOV <> 'O' THEN
                   V_MOTIVO := 'nao e pedido de compra (TIPMOV ' || V_TIPMOV || ').';

               ELSIF V_ACAO = 'P' THEN
                   -- ---------- PROVISIONAR ----------
                   IF NVL(V_PROV, 'N') = 'S' THEN
                       V_MOTIVO := 'ja esta provisionado.';
                   ELSIF V_PENDENTE <> 'S' THEN
                       SELECT MIN(NUNOTA) INTO V_NFDEST FROM TGFVAR WHERE NUNOTAORIG = V_NUNOTA;
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
                           V_MESNOTA := TRUNC(V_DTREF, 'MM');
                           IF NOT (V_MESNOTA = V_MESATU
                                   OR (V_MESNOTA = V_MESANT AND TRUNC(SYSDATE) <= V_LIMITE)) THEN
                               V_MOTIVO := 'data de entrada ' || TO_CHAR(V_DTREF, 'DD/MM/YYYY') ||
                                           ' fora do periodo (mes corrente; mes anterior so ate ' ||
                                           TO_CHAR(V_LIMITE, 'DD/MM/YYYY') || ').';
                           END IF;
                       END IF;
                   END IF;

                   IF V_MOTIVO IS NULL THEN
                       UPDATE TGFCAB SET AD_PROVISIONA = 'S' WHERE NUNOTA = V_NUNOTA;
                   END IF;

               ELSE
                   -- ---------- DESPROVISIONAR ----------
                   IF NVL(V_PROV, 'N') <> 'S' THEN
                       V_MOTIVO := 'nao esta provisionado.';
                   ELSE
                       SELECT COUNT(*) INTO V_QTD
                         FROM TCBINT
                        WHERE ORIGEM = 'E'
                          AND NUNICO = V_NUNOTA;
                       IF V_QTD > 0 THEN
                           V_MOTIVO := 'ja esta contabilizado; falar com a Contabilidade.';
                       END IF;
                   END IF;

                   IF V_MOTIVO IS NULL THEN
                       UPDATE TGFCAB SET AD_PROVISIONA = 'N' WHERE NUNOTA = V_NUNOTA;
                   END IF;
               END IF;
           END IF;

           IF V_MOTIVO IS NULL THEN
               V_OK := V_OK + 1;
           ELSE
               V_RECUSADAS := V_RECUSADAS + 1;
               IF LENGTH(V_LISTA) IS NULL OR LENGTH(V_LISTA) < C_MAX_MSG THEN
                   V_LISTA := V_LISTA || '<br>Nota ' || V_NUNOTA || ': ' || V_MOTIVO;
               END IF;
           END IF;
       END LOOP;

       P_MENSAGEM := '<b>' || CASE V_ACAO WHEN 'P' THEN 'Provisionar' ELSE 'Desprovisionar' END ||
                     ': ' || V_OK || ' de ' || P_QTDLINHAS || ' pedido(s) processado(s).</b>';
       IF V_RECUSADAS > 0 THEN
           P_MENSAGEM := P_MENSAGEM || '<br><br>Nao processado(s): ' || V_RECUSADAS || V_LISTA;
           IF LENGTH(V_LISTA) >= C_MAX_MSG THEN
               P_MENSAGEM := P_MENSAGEM || '<br>... (lista cortada; ha mais notas recusadas)';
           END IF;
       END IF;
END;
/
