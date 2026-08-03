WITH CTE_Agrupado_NF AS (
    SELECT 
        TGFVAR.NUNOTAORIG,
        CabecalhoNota.NUNOTA AS NUNOTA_NF,
        CabecalhoNota.NUMNOTA AS NUMNOTA_NF,
        CabecalhoNota.DTNEG AS DTNEG_NF,
        CabecalhoNota.DTENTSAI AS DTENTSAI_NF,
        CabecalhoNota.STATUSNOTA,
        SUM(ItemNota.VLRTOT) AS VLRTOT_NF
    FROM TGFVAR
    LEFT JOIN (
        SELECT 
            NUNOTA, VLRTOT, SEQUENCIA 
        FROM TGFITE
    ) ItemNota ON TGFVAR.NUNOTA = ItemNota.NUNOTA AND TGFVAR.SEQUENCIA = ItemNota.SEQUENCIA
    LEFT JOIN (
        SELECT 
            NUNOTA, DTNEG, NUMNOTA, TIPMOV, DTENTSAI, STATUSNOTA ,DHTIPOPER,CODTIPOPER
        FROM TGFCAB
    ) CabecalhoNota ON ItemNota.NUNOTA = CabecalhoNota.NUNOTA

    LEFT JOIN (
              SELECT GRUPO,DHALTER,CODTIPOPER  FROM   TGFTOP
    
    )top ON  top.CODTIPOPER = CabecalhoNota.CODTIPOPER AND CabecalhoNota.DHTIPOPER = top.DHALTER 
    WHERE NOT EXISTS (
    SELECT 1
    FROM TGFCAB T1
    INNER JOIN TGFTOP T2 ON T1.CODTIPOPER = T2.CODTIPOPER AND T1.DHTIPOPER = T2.DHALTER
    WHERE T1.NUNOTA = CabecalhoNota.NUNOTA AND T2.GRUPO = 'ADIANTAMENTO')
    GROUP BY 
        TGFVAR.NUNOTAORIG,
        CabecalhoNota.NUNOTA,
        CabecalhoNota.NUMNOTA,
        CabecalhoNota.DTNEG,
        CabecalhoNota.DTENTSAI,
        CabecalhoNota.STATUSNOTA,
        TOP.GRUPO
)


SELECT
-- -------------------PEDIDO --------------------
cab.nunota 
,CASE 
    WHEN CAB.AD_PROFISC_PENDENTE = 'S' THEN 'Sim'
    WHEN CAB.AD_PROFISC_PENDENTE = 'N' THEN 'Não'
    ELSE 'Não Informado'
END AS AD_PROFISC_PENDENTE
,cab.NUMNOTA
,cab.AD_PROTOCOLO
,COALESCE(
    (SELECT hist.AD_NUMANEXO
     FROM AD_TGFHISTPROTOCOLO hist 
     WHERE hist.NUNOTA = CAB.NUNOTA 
     AND TO_CHAR(CTE_Agrupado_NF.NUMNOTA_NF) = hist.AD_NUMANEXO
     AND ROWNUM = 1
    ), 
    (SELECT ATA.DESCRICAO
     FROM TSIATA ATA
WHERE 
    ATA.CODATA = CAB.NUNOTA
    AND ATA.DTINCLUSAO = (
        SELECT MIN(DTINCLUSAO) 
        FROM TSIATA 
        WHERE CODATA = CAB.NUNOTA)
AND ROWNUM = 1
    )
) AS NUMERODOCUMENTOANEXO
,COALESCE(
        (SELECT hist.AD_PROTOCOLO 
         FROM AD_TGFHISTPROTOCOLO hist 
         WHERE hist.NUNOTA = CAB.NUNOTA 
         AND TO_CHAR(CTE_Agrupado_NF.NUMNOTA_NF) = hist.AD_NUMANEXO
         AND ROWNUM = 1
         ),
        cab.AD_PROTOCOLO
    ) AS AD_PROTOCOLO
,COALESCE(
        (SELECT hist.AD_DTPROCOLO
         FROM AD_TGFHISTPROTOCOLO hist 
         WHERE hist.NUNOTA = CAB.NUNOTA 
         AND TO_CHAR(CTE_Agrupado_NF.NUMNOTA_NF) = hist.AD_NUMANEXO
         AND ROWNUM = 1
         ),
        cab.AD_DTPROCOLO
    ) AS DATA_RECEBIMENTO
,PAR.NOMEPARC
, cab.codemp
, emp.nomefantasia
, cr.descrcencus
, nat.descrnat as Natcab
,CASE 
           WHEN CAB.AD_PROTOCOLO IS NOT NULL  THEN 0
           ELSE 1
       END AS CONFIRMACAOPROTOCOLO
,(
    SELECT LISTAGG(DISTINCT TO_CHAR(FIN.DTVENC, 'DD/MM/YY'), ' - ' ON OVERFLOW TRUNCATE '...') 
    WITHIN GROUP (ORDER BY FIN.DTVENC) 
    FROM TGFFIN FIN 
    WHERE CAB.NUNOTA = FIN.NUNOTA
) AS DATAVENC
, CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM TGFRAT RAT 
            WHERE RAT.NUFIN = CAB.NUNOTA
        ) THEN 'Sim' 
        ELSE 'Não' 
    END AS RATEIO

,(
        SELECT SUM(ITE.VLRTOT)
        FROM TGFITE ITE
        WHERE CAB.NUNOTA = ITE.NUNOTA
    ) AS VLRTOT_ITENS

-- -------------------Campos da NF agrupados----------------
    ,CTE_Agrupado_NF.NUNOTA_NF
    ,CTE_Agrupado_NF.NUMNOTA_NF
    ,CTE_Agrupado_NF.DTNEG_NF
    ,CTE_Agrupado_NF.DTENTSAI_NF
    ,CTE_Agrupado_NF.VLRTOT_NF
   ,CASE 
        WHEN CTE_Agrupado_NF.STATUSNOTA = 'L' THEN 'Sim' 
        ELSE 'Não' 
    END AS STATUSNOTA_NF,
CAB.AD_OBS_PROTOCOLO
,(SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'Sim'
        ELSE 'Não'
    END AS ADIANTAMENTO
FROM TGFVAR
WHERE TGFVAR.NUNOTAORIG = CAB.NUNOTA
  AND EXISTS (
        SELECT 1
        FROM TGFTOP TOP
        INNER JOIN TGFCAB CabecalhoNota 
            ON TOP.CODTIPOPER = CabecalhoNota.CODTIPOPER 
            AND CabecalhoNota.DHTIPOPER = TOP.DHALTER
        WHERE TOP.GRUPO = 'ADIANTAMENTO'
          AND CabecalhoNota.NUNOTA = TGFVAR.NUNOTA
    )
) AS ADIANTAMENTO
FROM tgfcab CAB

INNER JOIN TSICUS CR ON cr.codcencus = cab.codcencus
INNER JOIN TGFNAT NAT ON nat.codnat = CAB.CODNAT
INNER JOIN TSIEMP EMP ON EMP.CODEMP = cab.codemp
INNER JOIN TGFPAR PAR ON CAB.CODPARC = PAR.CODPARC
INNER JOIN TGFTOP TOP ON TOP.CODTIPOPER = CAB.CODTIPOPER AND CAB.DHTIPOPER = TOP.DHALTER 
INNER JOIN TSIUSU USU ON cab.CODUSUINC = usu.CODUSU 
LEFT JOIN CTE_Agrupado_NF ON CAB.NUNOTA = CTE_Agrupado_NF.NUNOTAORIG
AND cab.tipmov <> 'F'

WHERE  
    -- Filtro para a data de negociação
    (
        (:PERIODO.INI IS NULL AND :PERIODO.FIN IS NULL) -- Se nenhuma data de negociação for fornecida, ignora o filtro
        OR
        (CAB.DTNEG BETWEEN :PERIODO.INI AND :PERIODO.FIN) -- Aplica o filtro apenas se as datas forem fornecidas
    )
    
    -- Filtro para a data de protocolo
    AND 
    (
        (:DTINICIAL IS NULL AND :DATAFIN IS NULL) -- Se nenhuma data de protocolo for fornecida, ignora o filtro
        OR
        (
            CASE
                WHEN TRUNC(CAB.AD_DTPROCOLO) IS NULL THEN TRUNC(CAB.AD_DTPROCOLO)
                ELSE TRUNC(CAB.AD_DTPROCOLO)
            END BETWEEN :DTINICIAL AND :DATAFIN -- Aplica o filtro apenas se as datas forem fornecidas
        )
    )


AND (EMP.CODEMP IN :Empresa)

AND (CAB.NUNOTA = :PKNUNOTA OR :PKNUNOTA IS NULL)

AND (CAB.TIPMOV IN ('O'))

AND CAB.AD_PROTOCOLO IS NOT NULL

AND  (cab.AD_INDEVIDO <> 'S' OR cab.AD_INDEVIDO IS NULL)