module AnaliseResultados

using CSV
using DataFrames
using XLSX
using Dates # Novo pacote para lidar com tempo

function calcular_gap_e_exportar()
    println("Iniciando cruzamento e organização dos resultados (Archetti/Absi)...")
    
    # 1. Carregamento e Processamento (Igual ao anterior)
    df_lb = CSV.read("resultados_limites_inferiores.csv", DataFrame)
    df_lb.Numero_Instancia = [parse(Int, match(r"ABS(\d+)_", nome).captures[1]) for nome in df_lb.Instancia]
    df_lb.Clientes = [parse(Int, match(r"_(\d+)_", nome).captures[1]) for nome in df_lb.Instancia]
    
    df_ub = CSV.read("russell_archetti_completo.csv", DataFrame)
    
    df_final = leftjoin(df_lb, df_ub, on = [:Numero_Instancia, :Clientes])
    dropmissing!(df_final, :UB_Russell)
    
    df_final.Gap_Percentual = ((df_final.UB_Russell .- df_final.LowerBound) ./ df_final.UB_Russell) .* 100
    df_final.Gap_Percentual = round.(df_final.Gap_Percentual, digits=2)
    df_final.Status = ifelse.(df_final.LowerBound .> df_final.UB_Russell, "⚠️ ALERTA: LB > UB", "✔️ OK")
    
    sort!(df_final, [:Clientes, :Numero_Instancia])
    select!(df_final, :Instancia, :Clientes, :LowerBound, :UB_Russell, :Gap_Percentual, :Status)
    
    # =========================================================================
    # LÓGICA DE NOME ÚNICO (TIMESTAMP):
    # Gera uma string no formato: 2026-04-29_15h30min
    carimbo_tempo = Dates.format(now(), "yyyy-mm-dd_HH-MM")
    nome_saida = "Resultados_Consolidados_$(carimbo_tempo).xlsx"
    # =========================================================================
    
    # 2. Exportação
    XLSX.writetable(nome_saida, Resultados_Iniciacao=(collect(eachcol(df_final)), names(df_final)))
    
    println("Sucesso! Novo arquivo gerado: ", nome_saida)
end

end # module