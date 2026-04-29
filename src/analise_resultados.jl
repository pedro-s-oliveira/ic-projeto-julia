module AnaliseResultados

using CSV
using DataFrames
using XLSX

function calcular_gap_e_exportar()
    println("Iniciando cruzamento e organização dos resultados (Archetti/Absi)...")
    
    # 1. Carrega os Limites Inferiores
    df_lb = CSV.read("resultados_limites_inferiores.csv", DataFrame)
    
    # 2. Extrai Número e Clientes
    df_lb.Numero_Instancia = [parse(Int, match(r"ABS(\d+)_", nome).captures[1]) for nome in df_lb.Instancia]
    df_lb.Clientes = [parse(Int, match(r"_(\d+)_", nome).captures[1]) for nome in df_lb.Instancia]
    
    # 3. Carrega a tabela do Russell
    df_ub = CSV.read("russell_archetti_completo.csv", DataFrame)
    
    # 4. Cruza os dados
    df_final = leftjoin(df_lb, df_ub, on = [:Numero_Instancia, :Clientes])
    dropmissing!(df_final, :UB_Russell)
    
    # 5. Calcula o Gap e Status
    df_final.Gap_Percentual = ((df_final.UB_Russell .- df_final.LowerBound) ./ df_final.UB_Russell) .* 100
    df_final.Gap_Percentual = round.(df_final.Gap_Percentual, digits=2)
    df_final.Status = ifelse.(df_final.LowerBound .> df_final.UB_Russell, "⚠️ ALERTA: LB > UB", "✔️ OK")
    
    # 6. Organiza a tabela
    sort!(df_final, [:Clientes, :Numero_Instancia])
    select!(df_final, :Instancia, :Clientes, :LowerBound, :UB_Russell, :Gap_Percentual, :Status)
    
    # =========================================================================
    # TRAVA DE SEGURANÇA:
    nome_saida = "Resultados_Consolidados_PRP.xlsx"
    if isfile(nome_saida)
        rm(nome_saida) # Remove o arquivo antigo para evitar o erro de "já existe"
        println("Arquivo antigo removido para atualização.")
    end
    # =========================================================================
    
    # 7. Exporta a planilha final
    XLSX.writetable(nome_saida, Resultados_Iniciacao=(collect(eachcol(df_final)), names(df_final)), overwrite=true)
    
    println("Sucesso! Planilha '", nome_saida, "' gerada e atualizada!")
end

end # module