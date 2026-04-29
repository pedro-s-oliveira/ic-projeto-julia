module AnaliseResultados

using CSV
using DataFrames
using XLSX

function calcular_gap_e_exportar()
    println("Iniciando cruzamento e organização dos resultados (Archetti/Absi)...")
    
    # 1. Carrega os Limites Inferiores gerados pelo seu modelo
    df_lb = CSV.read("resultados_limites_inferiores.csv", DataFrame)
    
    # 2. Extrai o Número da Instância e a Quantidade de Clientes direto do nome do arquivo
    # Ex: "ABS10_50_6.dat" vira Número = 10, Clientes = 50
    df_lb.Numero_Instancia = [parse(Int, match(r"ABS(\d+)_", nome).captures[1]) for nome in df_lb.Instancia]
    df_lb.Clientes = [parse(Int, match(r"_(\d+)_", nome).captures[1]) for nome in df_lb.Instancia]
    
    # 3. Carrega a tabela consolidada do Russell
    df_ub = CSV.read("russell_archetti_completo.csv", DataFrame)
    
    # 4. Cruza os dados usando as DUAS chaves, garantindo alinhamento perfeito
    df_final = leftjoin(df_lb, df_ub, on = [:Numero_Instancia, :Clientes])
    
    # Remove qualquer linha que por ventura não encontre paridade na literatura
    dropmissing!(df_final, :UB_Russell)
    
    # 5. Calcula o Gap Percentual
    df_final.Gap_Percentual = ((df_final.UB_Russell .- df_final.LowerBound) ./ df_final.UB_Russell) .* 100
    df_final.Gap_Percentual = round.(df_final.Gap_Percentual, digits=2)
    
    # 6. Organiza a tabela: Primeiro por tamanho de Clientes, depois pelo Número da Instância
    sort!(df_final, [:Clientes, :Numero_Instancia])
    
    # Reordena as colunas para ficar visualmente bonito no Excel
    select!(df_final, :Instancia, :Clientes, :LowerBound, :UB_Russell, :Gap_Percentual)
    
# Cria uma coluna de validação matemática
df_final.Status = ifelse.(df_final.LowerBound .> df_final.UB_Russell, "⚠️ ALERTA: LB > UB", "✔️ OK")

# Reordena para a coluna nova aparecer no final
select!(df_final, :Instancia, :Clientes, :LowerBound, :UB_Russell, :Gap_Percentual, :Status)

    # 7. Exporta a planilha final
    nome_saida = "Resultados_Consolidados_PRP.xlsx"
    XLSX.writetable(nome_saida, Resultados_Iniciacao=(collect(eachcol(df_final)), names(df_final)))
    
    println("Sucesso! Planilha '", nome_saida, "' gerada e perfeitamente ordenada!")
end

end # module