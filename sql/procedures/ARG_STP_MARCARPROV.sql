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

       FIELD_NUNOTA NUMBER;
       V_QTDATU     NUMBER := 0;
       V_DTREF      DATE;
       V_LIMITE     DATE;      -- último dia do prazo de carência (N-ésimo dia útil do mês corrente)
       V_CONT       NUMBER := 0;
       V_MESNOTA    DATE;
       V_MESATU     DATE;
       V_MESANT     DATE;
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
           SELECT NVL(DTENTSAI, DTNEG)
             INTO V_DTREF
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

           V_QTDATU := V_QTDATU + SQL%ROWCOUNT;

       END LOOP;

       P_MENSAGEM := V_QTDATU || ' Pedido(s) marcada(s) como provisionada(s). (TIPMOV=O - PEDIDO DE COMPRAS)';

END;
/
