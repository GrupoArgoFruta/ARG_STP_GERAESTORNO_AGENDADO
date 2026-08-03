-- ============================================================================
-- Botão de ação: Provisão mensal das NFs — SETOR FISCAL
-- Tela de origem: Protocolo Fiscal (grid baseado na consulta "Protocolo-fiscal"
-- já existente nesta pasta). O usuário seleciona os protocolos pendentes e
-- roda o botão; a procedure gera as linhas de PROVISÃO (último dia do mês) e
-- de ESTORNO (D+1, contas invertidas) direto em SANKHYA.TCBLAN.
--
-- HISTÓRICO DE DECISÃO (29/07/2026): a primeira versão desta procedure escrevia
-- em AD_TCBLANMAN (clone/staging usada pelo Importador de Dados manual da
-- Iranilde). Testamos em Homologação e confirmamos que NADA liga essa tabela
-- à tela real de "Lançamentos Contábeis" (nenhum trigger, nenhum job — só um
-- trigger bobo de STATUS). O usuário confirmou que o objetivo agora é tirar o
-- Importador de Dados do processo: o botão do Protocolo grava direto na
-- TCBLAN nativa. Pesquisamos as ~21 procedures STP_ARG_* já existentes que
-- mexem em TCBLAN/TCBLOT em busca de algo reaproveitável; a mais parecida
-- (STP_ARG_LCTO_CUTOFF) resolve um problema diferente (desloca a competência
-- de um lançamento QUE JÁ EXISTE, lido de TCBINT) — não serve pra nota nunca
-- lançada, que é o nosso caso. Ainda assim, seu padrão de INSERT (colunas,
-- uso de AD_NUNOTAORIG para rastreio) foi reaproveitado aqui.
--
-- Regra de negócio (fluxograma "Provisão a partir do Protocolo - Setor
-- Fiscal.docx" + reunião de 28/07/2026):
--   1. Só entra item que NÃO gera estoque.
--   2. Considera todas as NFs pendentes desde o fechamento anterior até o
--      último dia do mês corrente.
--   3. Se o Pedido de origem tem rateio, usa Natureza+CR+valor de cada linha
--      de rateio; senão usa Natureza+CR padrão do próprio Pedido.
--   4. Provisão:  Débito = conta variável pela Natureza
--                 Crédito = fixa (PROVISÃO DE PAGAMENTO)
--   5. Estorno D+1: mesmas contas invertidas.
--
-- Existe um botão irmão para o SETOR DE COMPRAS (fonte: Pedido, não
-- protocolado ainda) que reaproveita a mesma lógica de geração de linhas,
-- mas com critério de elegibilidade diferente (pedidos NÃO protocolados,
-- pra não duplicar com o que este botão já provisionou). Ainda não
-- desenvolvido — desenvolver depois que este for validado em Treinamento.
--
-- PENDÊNCIAS DE NEGÓCIO CONHECIDAS (ata de 28/07/2026 + decisões de 29/07/2026):
--   a) RESOLVIDO (29/07/2026): o de-para Natureza -> Conta Contábil NÃO
--      precisa de tabela própria. A Iranilde mostrou que a regra real é
--      CR + Natureza -> Conta (vínculo um-para-um, ela confirmou que nunca
--      existe o mesmo CR+Natureza apontando pra duas contas diferentes) e
--      que isso já é mantido nativamente na tabela TGFNCC ("Natureza Centro
--      de Custo", 53k+ linhas na base real, um "de-para" que a contabilidade
--      já atualiza no processo normal deles). Conferido: TGFNCC tem CODNAT,
--      CODCENCUS, CODCTACTB (+ AD_CODUSU/AD_DHALTER de auditoria) e ZERO
--      violações do vínculo um-para-um numa extração de 53.351 combinações.
--      A tabela AD_TPRVNATCTA (que a gente tinha criado como staging pra um
--      de-para manual) foi abandonada - a procedure agora lê TGFNCC direto,
--      por CR+Natureza da própria linha (rateio ou padrão do pedido). Não
--      precisa de cadastro manual nunca: se a combinação já existe no uso
--      normal da contabilidade, funciona sozinho; se não existir ainda,
--      a procedure erra com mensagem clara (mesma filosofia de antes).
--   b) Alisson mandou a lista de Tipos de Operação (TOP) do setor fiscal
--      (29/07/2026): 101, 102, 105, 116, 1702, 2102, 2136. Populada a tabela
--      AD_TPRVTOPFISCAL (DDL abaixo) como whitelist; protocolo cujo TOP não
--      estiver na lista é ignorado (não é erro, só não gera provisão). Essa
--      tabela SIM precisa de manutenção manual quando surgir um TOP novo -
--      mas TOP é cadastro estrutural (não muda com frequência), diferente
--      de Natureza x Conta que já resolvemos via TGFNCC.
--   c) Conta contábil reduzida de "2.1.3.01.004 - PROVISÃO DE PAGAMENTO"
--      ainda não confirmada. Fica como parâmetro do botão (P_CODCTA_PROVISAO)
--      pra não precisar recompilar quando a Iranilde confirmar o valor.
--      IMPORTANTE: NÃO usar a conta 422 vista na STP_ARG_LCTO_CUTOFF — aquela
--      é de um processo de "cutoff de custo" completamente diferente, sem
--      relação confirmada com "Provisão de Pagamento".
--   d) NUMLOTE e CODHISTCTB também como parâmetros do botão — a Iranilde
--      ainda vai definir o lote específico definitivo (hoje testando com
--      um lote de teste em Homologação). Diferente da AD_TCBLANMAN, a TCBLAN
--      real EXIGE que o lote já exista na TCBLOT — por isso a procedure
--      agora cria automaticamente o cabeçalho do lote (TCBLOT) quando não
--      existir, tanto pra referência da provisão quanto pra do estorno.
--   e) ATENÇÃO: a consulta "Protocolo-fiscal" já existente detecta rateio
--      com `TGFRAT.NUFIN = TGFCAB.NUNOTA`. Ainda assim, mesmo usando
--      V_NUNOTA_PROTOCOLO direto (ver correção do item g abaixo) isso
--      compara um NUFIN com um NUNOTA — domínios diferentes. Precisa ser
--      validado com o Alisson antes de confiar de olhos fechados — se for
--      coincidência de sequence e não regra real, o rateio pode estar
--      sendo ignorado silenciosamente (cairia sempre no caminho "sem
--      rateio", que é o comportamento mais conservador, mas não
--      necessariamente o correto).
--   f) TCBLAN tem 17 triggers (nativos + ARG_TRG_* customizados). Não lemos
--      todos ainda — se o teste em Homologação estourar erro vindo de algum
--      desses triggers, é esperado que a gente precise ajustar esta
--      procedure (ou os dados) e não os triggers nativos.
--   g) CORREÇÃO (29/07/2026): a primeira versão buscava "o pedido" via
--      `TGFVAR WHERE NUNOTA = V_NUNOTA_PROTOCOLO` antes de olhar o rateio -
--      só que V_NUNOTA_PROTOCOLO JÁ é o pedido (a tela de origem já filtra
--      TIPMOV='O'), então essa busca voltava um documento ANTERIOR ao
--      pedido (ex.: Solicitação de Compra), não o rateio nem a nota fiscal.
--      Testado com o protocolo 548465: a query antiga devolvia NUNOTAORIG=
--      547310 (não relacionado a rateio). Corrigido para usar
--      V_NUNOTA_PROTOCOLO diretamente na consulta de rateio. Também
--      adicionado busca da nota fiscal vinculada (via TGFVAR.NUNOTAORIG =
--      V_NUNOTA_PROTOCOLO, direção correta) só para preencher NUMDOC com o
--      número impresso da NF (ex.: 9066) - não interfere na regra de
--      rateio/valor, é só pra rastreabilidade visual na tela nativa.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- DDL de apoio (rodar uma vez só).
-- ----------------------------------------------------------------------------

-- AD_TPRVNATCTA foi abandonada (ver pendência (a) acima) - o de-para
-- Natureza->Conta vem direto da tabela nativa TGFNCC (CR+Natureza->Conta).

-- CREATE TABLE AD_TPRVTOPFISCAL (
--     CODTIPOPER  NUMBER(10)   NOT NULL,
--     CONSTRAINT PK_AD_TPRVTOPFISCAL PRIMARY KEY (CODTIPOPER)
-- );
-- COMMENT ON TABLE AD_TPRVTOPFISCAL IS 'Whitelist de Tipos de Operação elegíveis à Provisão mensal das NFs - setor Fiscal (pendência Alisson)';


CREATE OR REPLACE PROCEDURE "ARG_STP_PROVISAONF_FISCAL" (
       P_CODUSU NUMBER,         -- Código do usuário logado
       P_IDSESSAO VARCHAR2,     -- Identificador da execução (parâmetros/campos)
       P_QTDLINHAS NUMBER,      -- Quantidade de protocolos selecionados na grid
       P_MENSAGEM OUT VARCHAR2  -- Mensagem final exibida ao usuário
) AS
       -- Parâmetros do formulário do botão (ver pendências c/d acima) --
       P_CODCTA_PROVISAO   NUMBER;  -- Conta contábil reduzida de "PROVISÃO DE PAGAMENTO"
       P_NUMLOTE           NUMBER;  -- Número do lote (Iranilde define o definitivo)
       P_CODHISTCTB        NUMBER;  -- Código do histórico contábil padrão

       -- Campo lido da linha selecionada --
       V_NUNOTA_PROTOCOLO  TGFCAB.NUNOTA%TYPE;

       -- Dados do protocolo/pedido --
       V_CODEMP            TGFCAB.CODEMP%TYPE;
       V_CODNAT_PADRAO     TGFCAB.CODNAT%TYPE;
       V_CODCENCUS_PADRAO  TGFCAB.CODCENCUS%TYPE;
       V_CODTIPOPER        TGFCAB.CODTIPOPER%TYPE;
       V_DHTIPOPER         TGFCAB.DHTIPOPER%TYPE;
       V_CODPARC           TGFCAB.CODPARC%TYPE;
       V_NUMNOTA_PROTOCOLO TGFCAB.NUMNOTA%TYPE;
       V_NUMDOC            TGFCAB.NUMNOTA%TYPE;  -- vai pro NUMDOC da TCBLAN: nº impresso da NF vinculada (fallback: nº do próprio protocolo)
       V_CODPROJ           TGFCAB.CODPROJ%TYPE;  -- vai pro CODPROJ da TCBLAN (NULL se o pedido não tiver projeto - CODPROJ=0 vira NULL, ver NULLIF abaixo)
       V_VLRTOT_NF         TGFITE.VLRTOT%TYPE;

       V_QTD_ITENS_ESTOQUE NUMBER;
       V_QTD_TOP           NUMBER;
       V_QTD_JA_PROVISIONADO NUMBER;
       V_QTD_LOTE          NUMBER;
       V_CODCTACTB         NUMBER;

       -- Competências (referência) da provisão e do estorno --
       V_REF_PROV          DATE := LAST_DAY(TRUNC(SYSDATE));      -- último dia do mês corrente
       V_REF_EST           DATE := LAST_DAY(TRUNC(SYSDATE)) + 1;  -- primeiro dia do mês seguinte

       -- Numeração dentro da TCBLAN (escopada por CODEMP+REFERENCIA+NUMLOTE,
       -- que é a chave composta da TCBLOT/parte da PK da TCBLAN) --
       V_NUMLANC_PROV      NUMBER;
       V_NUMLANC_EST       NUMBER;

       V_QTD_GERADOS       NUMBER := 0;
       V_QTD_IGNORADOS     NUMBER := 0;

BEGIN
       P_MENSAGEM := NULL;

       -- ---------------------------------------------------------------
       -- 1) TRAVA DE DATA: só roda no último dia do mês (decisão da
       --    reunião de 28/07 - "implementar travas de data para garantir
       --    que a movimentação ocorra apenas no último dia do mês").
       --
       --    DESATIVADA TEMPORARIAMENTE (29/07/2026) para permitir os
       --    testes em Homologação antes do fechamento de julho (31/07).
       --    REATIVAR (descomentar) antes de considerar esta procedure
       --    pronta para Produção.
       -- ---------------------------------------------------------------
       -- IF TRUNC(SYSDATE) <> LAST_DAY(TRUNC(SYSDATE)) THEN
       --     RAISE_APPLICATION_ERROR(-20001,
       --         'A Provisão mensal das NFs só pode ser executada no último dia do mês.');
       -- END IF;

       -- ---------------------------------------------------------------
       -- 2) Parâmetros do formulário do botão
       -- ---------------------------------------------------------------
       P_CODCTA_PROVISAO := ACT_INT_PARAM(P_IDSESSAO, 'CODCTA_PROVISAO');
       P_NUMLOTE         := ACT_INT_PARAM(P_IDSESSAO, 'NUMLOTE');
       P_CODHISTCTB      := ACT_INT_PARAM(P_IDSESSAO, 'CODHISTCTB');

       IF P_CODCTA_PROVISAO IS NULL OR P_NUMLOTE IS NULL OR P_CODHISTCTB IS NULL THEN
           RAISE_APPLICATION_ERROR(-20002,
               'Informe Conta de Provisão, Número do Lote e Código do Histórico no formulário do botão.');
       END IF;

       -- ---------------------------------------------------------------
       -- 3) Loop pelos protocolos selecionados na grid
       -- ---------------------------------------------------------------
       FOR I IN 1..P_QTDLINHAS LOOP

           V_NUNOTA_PROTOCOLO := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNOTA');

           BEGIN
               SELECT CAB.CODEMP, CAB.CODNAT, CAB.CODCENCUS, CAB.CODTIPOPER, CAB.DHTIPOPER, CAB.CODPARC, CAB.NUMNOTA,
                      NULLIF(CAB.CODPROJ, 0)
                 INTO V_CODEMP, V_CODNAT_PADRAO, V_CODCENCUS_PADRAO, V_CODTIPOPER, V_DHTIPOPER, V_CODPARC, V_NUMNOTA_PROTOCOLO,
                      V_CODPROJ
                 FROM TGFCAB CAB
                WHERE CAB.NUNOTA = V_NUNOTA_PROTOCOLO;
           EXCEPTION
               WHEN NO_DATA_FOUND THEN
                   V_QTD_IGNORADOS := V_QTD_IGNORADOS + 1;
                   CONTINUE;
           END;

           -- Número do documento pra exibir na TCBLAN (NUMDOC): nº impresso
           -- da NF vinculada ao protocolo (ex.: 9066), buscado via
           -- TGFVAR.NUNOTAORIG = V_NUNOTA_PROTOCOLO (direção correta - ver
           -- pendência g no topo). Se não achar NF vinculada, cai pro nº do
           -- próprio protocolo.
           BEGIN
               SELECT NF.NUMNOTA INTO V_NUMDOC
                 FROM TGFVAR VAR
                 JOIN TGFCAB NF ON NF.NUNOTA = VAR.NUNOTA
                WHERE VAR.NUNOTAORIG = V_NUNOTA_PROTOCOLO
                  AND ROWNUM = 1;
           EXCEPTION
               WHEN NO_DATA_FOUND THEN
                   V_NUMDOC := V_NUMNOTA_PROTOCOLO;
           END;

           -- Filtro TOP fiscal (whitelist do Alisson - pendência b) --
           -- OBS: "IF NOT EXISTS(...)" direto não compila em PL/SQL puro
           -- (PLS-00204) - EXISTS só vale dentro de uma instrução SQL, por
           -- isso o COUNT(*) abaixo em vez de um IF NOT EXISTS.
           SELECT COUNT(*) INTO V_QTD_TOP
             FROM AD_TPRVTOPFISCAL
            WHERE CODTIPOPER = V_CODTIPOPER;

           IF V_QTD_TOP = 0 THEN
               V_QTD_IGNORADOS := V_QTD_IGNORADOS + 1;
               CONTINUE;
           END IF;

           -- Regra 1: item que gera estoque não entra na provisão.
           -- Checagem redundante à whitelist de TOP acima - serve de rede
           -- de segurança caso a lista do Alisson inclua por engano algum
           -- TOP que efetivamente movimenta estoque (ATUALEST <> 'N').
           SELECT COUNT(*)
             INTO V_QTD_ITENS_ESTOQUE
             FROM TGFITE ITE
             INNER JOIN TGFCAB C2 ON C2.NUNOTA = ITE.NUNOTA
             INNER JOIN TGFTOP T2 ON T2.CODTIPOPER = C2.CODTIPOPER AND T2.DHALTER = C2.DHTIPOPER
            WHERE ITE.NUNOTA = V_NUNOTA_PROTOCOLO
              AND T2.ATUALEST <> 'N';

           IF V_QTD_ITENS_ESTOQUE > 0 THEN
               V_QTD_IGNORADOS := V_QTD_IGNORADOS + 1;
               CONTINUE;
           END IF;

           -- Valor total da NF vinculada ao protocolo --
           SELECT NVL(SUM(ITE.VLRTOT), 0)
             INTO V_VLRTOT_NF
             FROM TGFITE ITE
            WHERE ITE.NUNOTA = V_NUNOTA_PROTOCOLO;

           IF V_VLRTOT_NF = 0 THEN
               V_QTD_IGNORADOS := V_QTD_IGNORADOS + 1;
               CONTINUE;
           END IF;

           -- Reentrância: se essa nota já foi provisionada nesta referência
           -- (AD_NUNOTAORIG), não duplica - protege contra clique duplo no
           -- botão ou seleção do mesmo protocolo em execuções diferentes.
           SELECT COUNT(*) INTO V_QTD_JA_PROVISIONADO
             FROM SANKHYA.TCBLAN
            WHERE AD_NUNOTAORIG = V_NUNOTA_PROTOCOLO
              AND CODEMP = V_CODEMP
              AND REFERENCIA = V_REF_PROV;

           IF V_QTD_JA_PROVISIONADO > 0 THEN
               V_QTD_IGNORADOS := V_QTD_IGNORADOS + 1;
               CONTINUE;
           END IF;

           -- ---------------------------------------------------------------
           -- Garante que o lote (CODEMP, REFERENCIA, NUMLOTE) existe na
           -- TCBLOT tanto pra referência da provisão quanto pra do estorno
           -- (TCBLAN tem FK real pra TCBLOT nessas 3 colunas - diferente da
           -- antiga AD_TCBLANMAN, aqui o lote precisa existir de verdade).
           -- ---------------------------------------------------------------
           FOR REG_REF IN (SELECT V_REF_PROV AS REF FROM DUAL UNION ALL SELECT V_REF_EST FROM DUAL)
           LOOP
               SELECT COUNT(*) INTO V_QTD_LOTE
                 FROM SANKHYA.TCBLOT
                WHERE CODEMP = V_CODEMP
                  AND REFERENCIA = REG_REF.REF
                  AND NUMLOTE = P_NUMLOTE;

               IF V_QTD_LOTE = 0 THEN
                   INSERT INTO SANKHYA.TCBLOT (CODEMP, REFERENCIA, NUMLOTE, DTMOV, SITUACAO, ULTLANC, CODUSU)
                   VALUES (V_CODEMP, REG_REF.REF, P_NUMLOTE, REG_REF.REF, 'A', 0, NVL(P_CODUSU, 0));
               END IF;
           END LOOP;

           -- ---------------------------------------------------------------
           -- Regra 3: rateio do pedido, se existir; senão, natureza/CR padrão.
           -- V_NUNOTA_PROTOCOLO JÁ É o pedido (tela de origem filtra
           -- TIPMOV='O') - usa direto, sem indireção via TGFVAR (ver
           -- correção do item g no topo). ATENÇÃO pendência (e): join
           -- replicado da consulta "Protocolo-fiscal" já existente
           -- (RAT.NUFIN = NUNOTA do pedido) - validar com o Alisson antes de
           -- confiar 100% (ver comentário no topo).
           -- ---------------------------------------------------------------
           FOR REG IN (
               SELECT RAT.CODNAT AS CODNAT, RAT.CODCENCUS AS CODCENCUS,
                      V_VLRTOT_NF * (RAT.PERCRATEIO / 100) AS VLRLINHA
                 FROM TGFRAT RAT
                WHERE RAT.NUFIN = V_NUNOTA_PROTOCOLO
               UNION ALL
               SELECT V_CODNAT_PADRAO, V_CODCENCUS_PADRAO, V_VLRTOT_NF
                 FROM DUAL
                WHERE NOT EXISTS (SELECT 1 FROM TGFRAT WHERE NUFIN = V_NUNOTA_PROTOCOLO)
           )
           LOOP
               -- De-para CR + Natureza -> Conta Contábil: vem direto da
               -- tabela nativa TGFNCC (mantida pela contabilidade no
               -- processo normal deles, sem cadastro manual nosso - ver
               -- pendência (a) no topo). Chave composta CODCENCUS+CODNAT.
               BEGIN
                   SELECT CODCTACTB INTO V_CODCTACTB
                     FROM TGFNCC
                    WHERE CODCENCUS = REG.CODCENCUS
                      AND CODNAT = REG.CODNAT;
               EXCEPTION
                   WHEN NO_DATA_FOUND THEN
                       RAISE_APPLICATION_ERROR(-20003,
                           'CR ' || REG.CODCENCUS || ' + Natureza ' || REG.CODNAT || ' (protocolo NUNOTA=' ||
                           V_NUNOTA_PROTOCOLO || ') sem conta contábil mapeada em TGFNCC. Cadastrar essa combinação em Natureza x Centro de Custo.');
               END;

               -- Número do lançamento novo, escopado por CODEMP+REFERENCIA+
               -- NUMLOTE (evita colidir com lançamentos de outros lotes/meses).
               SELECT NVL(MAX(NUMLANC), 0) + 1 INTO V_NUMLANC_PROV
                 FROM SANKHYA.TCBLAN
                WHERE CODEMP = V_CODEMP AND REFERENCIA = V_REF_PROV AND NUMLOTE = P_NUMLOTE;

               SELECT NVL(MAX(NUMLANC), 0) + 1 INTO V_NUMLANC_EST
                 FROM SANKHYA.TCBLAN
                WHERE CODEMP = V_CODEMP AND REFERENCIA = V_REF_EST AND NUMLOTE = P_NUMLOTE;

               -- Provisão - Débito (conta da Natureza) --
               INSERT INTO SANKHYA.TCBLAN (
                   CODEMP, REFERENCIA, NUMLOTE, NUMLANC, TIPLANC, SEQUENCIA,
                   CODCTACTB, CODCONPAR, CODCENCUS, DTMOV, VLRLANC,
                   CODHISTCTB, COMPLHIST, LIBERADO, CODUSU, INDESTORNADO,
                   AD_NUNOTAORIG, AD_CODPARC, NUMDOC, CODPROJ
               ) VALUES (
                   V_CODEMP, V_REF_PROV, P_NUMLOTE, V_NUMLANC_PROV, 'D', 1,
                   V_CODCTACTB, P_CODCTA_PROVISAO, REG.CODCENCUS, V_REF_PROV, REG.VLRLINHA,
                   P_CODHISTCTB, 'PROVISAO NF PROTOCOLO ' || V_NUNOTA_PROTOCOLO, 'S', NVL(P_CODUSU, 0), 'F',
                   V_NUNOTA_PROTOCOLO, V_CODPARC, V_NUMDOC, V_CODPROJ
               );

               -- Provisão - Crédito (fixa: Provisão de Pagamento) --
               INSERT INTO SANKHYA.TCBLAN (
                   CODEMP, REFERENCIA, NUMLOTE, NUMLANC, TIPLANC, SEQUENCIA,
                   CODCTACTB, CODCONPAR, CODCENCUS, DTMOV, VLRLANC,
                   CODHISTCTB, COMPLHIST, LIBERADO, CODUSU, INDESTORNADO,
                   AD_NUNOTAORIG, AD_CODPARC, NUMDOC, CODPROJ
               ) VALUES (
                   V_CODEMP, V_REF_PROV, P_NUMLOTE, V_NUMLANC_PROV, 'R', 2,
                   P_CODCTA_PROVISAO, V_CODCTACTB, REG.CODCENCUS, V_REF_PROV, REG.VLRLINHA,
                   P_CODHISTCTB, 'PROVISAO NF PROTOCOLO ' || V_NUNOTA_PROTOCOLO, 'S', NVL(P_CODUSU, 0), 'F',
                   V_NUNOTA_PROTOCOLO, V_CODPARC, V_NUMDOC, V_CODPROJ
               );

               -- Estorno D+1 - Débito (fixa: Provisão de Pagamento, invertida) --
               INSERT INTO SANKHYA.TCBLAN (
                   CODEMP, REFERENCIA, NUMLOTE, NUMLANC, TIPLANC, SEQUENCIA,
                   CODCTACTB, CODCONPAR, CODCENCUS, DTMOV, VLRLANC,
                   CODHISTCTB, COMPLHIST, LIBERADO, CODUSU, INDESTORNADO,
                   AD_NUNOTAORIG, AD_CODPARC, NUMDOC, CODPROJ
               ) VALUES (
                   V_CODEMP, V_REF_EST, P_NUMLOTE, V_NUMLANC_EST, 'D', 1,
                   P_CODCTA_PROVISAO, V_CODCTACTB, REG.CODCENCUS, V_REF_EST, REG.VLRLINHA,
                   P_CODHISTCTB, 'ESTORNO PROVISAO NF PROTOCOLO ' || V_NUNOTA_PROTOCOLO, 'S', NVL(P_CODUSU, 0), 'S',
                   V_NUNOTA_PROTOCOLO, V_CODPARC, V_NUMDOC, V_CODPROJ
               );

               -- Estorno D+1 - Crédito (conta da Natureza, invertida) --
               INSERT INTO SANKHYA.TCBLAN (
                   CODEMP, REFERENCIA, NUMLOTE, NUMLANC, TIPLANC, SEQUENCIA,
                   CODCTACTB, CODCONPAR, CODCENCUS, DTMOV, VLRLANC,
                   CODHISTCTB, COMPLHIST, LIBERADO, CODUSU, INDESTORNADO,
                   AD_NUNOTAORIG, AD_CODPARC, NUMDOC, CODPROJ
               ) VALUES (
                   V_CODEMP, V_REF_EST, P_NUMLOTE, V_NUMLANC_EST, 'R', 2,
                   V_CODCTACTB, P_CODCTA_PROVISAO, REG.CODCENCUS, V_REF_EST, REG.VLRLINHA,
                   P_CODHISTCTB, 'ESTORNO PROVISAO NF PROTOCOLO ' || V_NUNOTA_PROTOCOLO, 'S', NVL(P_CODUSU, 0), 'S',
                   V_NUNOTA_PROTOCOLO, V_CODPARC, V_NUMDOC, V_CODPROJ
               );

               V_QTD_GERADOS := V_QTD_GERADOS + 1;
           END LOOP;

       END LOOP;

       P_MENSAGEM := V_QTD_GERADOS || ' provisão(ões) gerada(s), ' || V_QTD_IGNORADOS || ' protocolo(s) ignorado(s).';

END;
/
