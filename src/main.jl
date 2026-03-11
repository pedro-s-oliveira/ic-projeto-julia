# O ponto de entrada do projeto
module MeuProjeto

# O 'include' traz as funções do outro arquivo para cá
include("calculos.jl")

# Exemplo de uso das funções
qtd = 150
preco = 12.50

total = calcular_custo_total(qtd, preco)
println("O custo total da produção é: ", formatar_moeda(total))

end