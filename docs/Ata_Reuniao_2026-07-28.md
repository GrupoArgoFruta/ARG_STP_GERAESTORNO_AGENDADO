jul. 28, 2026

## **Automatização \- Provisão mensal das NFs**

convidado [Yula Almeida](mailto:yula.almeida@argofruta.com) [Francisco Natanael Lopes Vasconcelos](mailto:natanael.lopes@argofruta.com) [Waleska Ribeiro](mailto:waleska.ribeiro@argofruta.com) [Aparecida Siqueira](mailto:aparecida@argofruta.com) [Alisson Vieira](mailto:alisson.vieira@argofruta.com) [Iranilde Moura](mailto:iranilde.moura@argofruta.com) [Jhonatan Holanda](mailto:jhonatan.holanda@argofruta.com)

Anexos [Automatização - Provisão mensal das NFs](https://calendar.google.com/calendar/event?eid=MmsxcmYyMjdtdWFzcGxla2g1bGxnZWJyYm4gaXJhbmlsZGUubW91cmFAYXJnb2ZydXRhLmNvbQ) [Anotações do Gemini](https://docs.google.com/document/d/1eQo7r5t2oK3qmZdpe2IEySALgvXUAlWnaW6Zh9gD4EI/edit?usp=meet_tnfm_calendar)

Registros da reunião [Transcrição](https://docs.google.com/document/d/1P0M_euDf5pASVUJt5188Jqm6MCsDh4hTnFdPPUoFmg0/edit?usp=drive_web&tab=t.vw3ub3y9dcox) [Gravação](https://drive.google.com/file/d/1mvHErV2ptUr0yD-n_nVrPB_LxM6s-SOT/view?usp=drive_web) 

### **Resumo**

A reunião definiu a automatização do processo de provisões contábeis via botão de ação no sistema.

**Problemas no processo manual**  
O fluxo atual de provisões depende excessivamente de planilhas manuais e processamento externo. A dependência de lançamentos manuais gera ineficiência operacional e riscos de erros.

**Automação via sistema integrado**  
Foi definida a implementação de um botão de ação no sistema para automatizar provisões via protocolo fiscal e compras. O sistema buscará o rateio diretamente nos pedidos para precisão.

**Estrutura técnica e testes**  
Configurações incluirão lotes específicos para provisões e estruturação de dados para importação. A base de homologação será atualizada para permitir a validação completa do mecanismo de lançamentos e estornos.

### **Próximas etapas**

- [ ] \[Francisco Natanael Lopes Vasconcelos\] Criar botão de automação: Desenvolver o botão de ação no sistema para automatizar a provisão contábil com base nos tipos de operação fornecidos. Implementar travas de data para garantir que a movimentação ocorra apenas no último dia do mês.

- [ ] \[Iranilde Moura\] Enviar estrutura contábil: Encaminhar para o Natã a documentação com a estrutura detalhada da contabilização utilizada nas provisões.

- [ ] \[Alisson Vieira\] Enviar tipos de operação: Enviar para o Natã a relação dos tipos de operação utilizados no setor fiscal para viabilizar o filtro da automatização.

- [ ] \[Iranilde Moura\] Enviar Planilha: Enviar a estrutura da planilha utilizada para importação de dados.

- [ ] \[Iranilde Moura\] Definir Lote: Definir um lote específico para o teste de provisão no ambiente de homologação.

- [ ] \[Aparecida Siqueira\] Replicar Base: Replicar a base de dados na homologação após o salvamento das fotos por Francisco.

### **Detalhes**

* **Objetivo da reunião e automação de provisões**: Iranilde Moura, Francisco Natanael Lopes Vasconcelos, Alisson Vieira, Emanuela e Aparecida Siqueira reuniram-se para discutir a substituição do processo manual de provisões contábeis por uma solução automática dentro do sistema ([00:02:37](?tab=t.vw3ub3y9dcox#heading=h.pcfk35aw63bc)). O problema identificado é que, ao final de cada mês, notas fiscais não lançadas pelos setores de compras e fiscal precisam ser provisionadas manualmente pela contabilidade, exigindo o envio constante de planilhas em Excel ([00:30:04](?tab=t.vw3ub3y9dcox#heading=h.nq7io2156fyh)).

* **Processo atual de provisão do setor fiscal**: Alisson Vieira explicou o fluxo atual, onde a equipe exporta as notas pendentes para uma planilha e aplica filtros para excluir itens que não geram provisão, como notas de imobilizado, remessas e materiais que geram estoque ([00:34:01](?tab=t.vw3ub3y9dcox#heading=h.56zcaw6eymxe)). Somente após essa filtragem, a planilha é enviada para a contabilidade realizar os lançamentos, garantindo que apenas as operações financeiras necessárias sejam processadas ([00:37:47](?tab=t.vw3ub3y9dcox#heading=h.wi4i1ky7nt66)).

* **Fluxo de provisão contábil e datas**: Iranilde Moura esclareceu que a contabilidade realiza o lançamento da provisão no último dia do mês e efetua o estorno no primeiro dia do mês subsequente ([00:38:55](?tab=t.vw3ub3y9dcox#heading=h.j68cy82wm9o9)) ([00:44:33](?tab=t.vw3ub3y9dcox#heading=h.fjjys2en6ogd)). O setor de compras opera de forma similar, utilizando o portal de compras para identificar pedidos pendentes que não foram processados via protocolo de recebimento fiscal ([00:39:54](?tab=t.vw3ub3y9dcox#heading=h.1gend2r4x62k)).

* **Visualização da tela de lançamentos**: Francisco Natanael Lopes Vasconcelos solicitou uma demonstração da tela de lançamentos contábeis utilizada pela contabilidade ([00:40:49](?tab=t.vw3ub3y9dcox#heading=h.qzqe9zmg8b3t)). Iranilde Moura exibiu o processo atual, no qual a contabilidade utiliza uma tabela dinâmica baseada na descrição do plano de contas para consolidar valores de diferentes notas e realizar a importação de dados para o sistema ([00:41:56](?tab=t.vw3ub3y9dcox#heading=h.d6t1iixcn28t)).

* **Proposta de automação via botão de ação**: Francisco Natanael Lopes Vasconcelos propôs implementar um "botão de ação" diretamente na tela de protocolo para eliminar a necessidade de planilhas manuais ([00:45:34](?tab=t.vw3ub3y9dcox#heading=h.2kxrh38gs5uj)) ([00:47:32](?tab=t.vw3ub3y9dcox#heading=h.bdqf54pjaa2n)). Para garantir a integridade contábil, foi discutida a implementação de uma trava de sistema que permita a operação apenas no último dia do mês, evitando que lançamentos sejam realizados em datas incorretas ([00:46:39](?tab=t.vw3ub3y9dcox#heading=h.p82a5rsvubq5)).

* **Definição de parâmetros e centros de custo**: Aparecida Siqueira e Francisco Natanael Lopes Vasconcelos debateram a necessidade de definir claramente o lote, o centro de resultado e a conta contábil durante a automação ([00:48:40](?tab=t.vw3ub3y9dcox#heading=h.vc4qkluknj9p)). Iranilde Moura esclareceu que, para itens que não geram estoque, o sistema busca a conta contábil através da "natureza" da operação, reforçando a necessidade de um vínculo um-para-um entre centro de resultado e conta contábil para evitar falhas ([00:51:17](?tab=t.vw3ub3y9dcox#heading=h.vclld14081jm)) ([00:53:18](?tab=t.vw3ub3y9dcox#heading=h.ts2i32yffm5i)).

* **Desafios com o rateio de notas**: Iranilde Moura destacou um problema crítico relacionado aos setores de recursos humanos e administrativo, que relataram lançamentos incorretos em meses anteriores ([00:54:08](?tab=t.vw3ub3y9dcox#heading=h.5m3o3tnzzjxd)) ([00:57:14](?tab=t.vw3ub3y9dcox#heading=h.6ycpl2p4q0o)). Isso ocorreu porque o processo atual, baseado na "capa" da nota, não identificava o rateio definido nos pedidos de compra ([00:55:23](?tab=t.vw3ub3y9dcox#heading=h.1yxessxsfer4)) ([00:57:14](?tab=t.vw3ub3y9dcox#heading=h.6ycpl2p4q0o)). A automação precisa, portanto, buscar a informação de rateio diretamente no pedido de compra quando esta estiver disponível ([00:55:23](?tab=t.vw3ub3y9dcox#heading=h.1yxessxsfer4)) ([00:58:16](?tab=t.vw3ub3y9dcox#heading=h.i48jhsifkrnf)).

* **Estrutura de lançamentos e documentação**: Francisco Natanael Lopes Vasconcelos e Aparecida Siqueira confirmaram que o sistema deve criar lançamentos com valores iguais de débito e crédito, mantendo a conta de "provisão de pagamento" como contrapartida fixa ([01:00:07](?tab=t.vw3ub3y9dcox#heading=h.35xd3k87fl5j)). Iranilde Moura comprometeu-se a enviar a estrutura de contabilização, previamente compartilhada com Evandro, para orientar o desenvolvimento da automação no sistema ([00:52:16](?tab=t.vw3ub3y9dcox#heading=h.h1gypyufesgo)).

* **Estrutura da planilha de importação**: Francisco Natanael Lopes Vasconcelos e Alisson Vieira debateram sobre a necessidade de mapear todas as colunas da planilha para a importação de dados. Iranilde Moura esclareceu que a importação é realizada através do arquivo TC plano, sendo necessário informar campos específicos como ID, identificador da pessoa que está lançando, número do lançamento, código da empresa, número do lote, valor a débito e valor a crédito ([01:01:35](?tab=t.vw3ub3y9dcox#heading=h.ueyrywgihmf0)). Iranilde Moura comprometeu-se a enviar a estrutura marcada para Francisco Natanael Lopes Vasconcelos realizar a conferência ([01:02:57](?tab=t.vw3ub3y9dcox#heading=h.rbgsni9hv0o5)).

* **Definição de lote de provisão**: Francisco Natanael Lopes Vasconcelos e Iranilde Moura discutiram a necessidade de definir um lote para os lançamentos, havendo consenso sobre a importância de criar um lote específico para as provisões ([01:02:57](?tab=t.vw3ub3y9dcox#heading=h.rbgsni9hv0o5)). Aparecida Siqueira reforçou a recomendação de separar esses lançamentos dos demais em um lote próprio, o que facilitaria a identificação e a resolução de eventuais problemas. Francisco Natanael Lopes Vasconcelos solicitou que Iranilde Moura definisse um lote no ambiente de homologação para permitir os testes ([01:04:14](?tab=t.vw3ub3y9dcox#heading=h.6j2wyxht37vl)).

* **Atualização da base de homologação**: Aparecida Siqueira sugeriu a replicação da base de homologação para garantir que os dados estivessem atualizados, visto que a versão utilizada estava defasada. Francisco Natanael Lopes Vasconcelos expressou preocupação em relação a um projeto de fotos em andamento na homologação, mas após confirmarem que os dados poderiam ser salvos, concordou que Aparecida Siqueira realizasse a atualização da base e que ele faria a restauração dos dados posteriormente ([01:04:54](?tab=t.vw3ub3y9dcox#heading=h.luiapbfjtc1v)) ([01:06:37](?tab=t.vw3ub3y9dcox#heading=h.smuc3q629pxt)).

* **Processo de estornos**: Iranilde Moura explicou que o mecanismo de estorno é realizado no mesmo lançamento, utilizando a data de referência para o débito (exemplo: 30/06) e a data do mês seguinte para o crédito (exemplo: 01/07), invertendo as contas. Aparecida Siqueira ressaltou a importância de registrar todas essas movimentações nos históricos para permitir a devida identificação contábil ([01:05:39](?tab=t.vw3ub3y9dcox#heading=h.elyy1zkcwdkh)).

* **Integração de setores e conclusão**: Iranilde Moura destacou a necessidade de utilizar o botão de ação adequado conforme o setor, aplicando o protocolo fiscal para o setor fiscal e o portal de compras para o setor de compras. Francisco Natanael Lopes Vasconcelos encerrou a reunião indicando que aguardaria a atualização da base por parte de Aparecida Siqueira e a definição do lote por parte de Iranilde Moura para iniciar os testes ([01:06:37](?tab=t.vw3ub3y9dcox#heading=h.smuc3q629pxt)).

*Revise as anotações do Gemini para checar se estão corretas. [Confira dicas e saiba como o Gemini faz anotações](https://support.google.com/meet/answer/14754931)*

*Como está a qualidade de **destas observações?** [Responda a uma breve pesquisa](https://google.qualtrics.com/jfe/form/SV_5bXzKQfylMIhSXc?confid=ybypqG1wpgth8QeDl3yNDxITOAIIigIgABgFCA&detailLevel=standard&hasImages=False&entryPoint=footerMain&isGoogler=False) para nos dar seu feedback, incluindo o quanto as observações foram úteis para o que você precisa.*