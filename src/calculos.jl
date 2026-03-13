# Este arquivo vai guardar apenas as "ferramentas" de cálculo
function calcular_custo_total(quantidade, custo_unitario)
    return quantidade * custo_unitario
end

function formatar_moeda(valor)
    return "R\$ $(round(valor, digits=2))"
end

println("Hello world!")