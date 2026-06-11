quant_vendas_coca = 150
quant_vendas_pepsi = 130
preco_coca = 1.50
preco_pepsi = 1.50
custo_loja = 2500

#Parte 1
#Questão 1
faturamento_pepsi = quant_vendas_pepsi * preco_pepsi
print(faturamento_pepsi)

#Questão 2
faturamento_coca = quant_vendas_coca * preco_coca
print(faturamento_coca)

#Questão 3
lucro_loja = faturamento_coca + faturamento_pepsi - custo_loja
print(lucro_loja)

#Parte 2
#Questão 1

bebida = input("Digite o código da bebida: ")
print("BEB" in bebida)