module BateriaTestes

# Inclui os seus arquivos que já estão prontos
include("DaTA.jl")                 
include("PRP_Relaxado_Cap2.jl")  

using .Dados               
using .PRP_Relaxado_Cap2 
using CSV
using DataFrames

function rodar_todas_instancias(caminho_da_pasta::String)
    println("Iniciando a bateria de testes na pasta: ", caminho_da_pasta)
    println("-"^50)
    
    # Prepara a tabela (DataFrame) que vai guardar os resultados
    resultados = DataFrame(Instancia = String[], LowerBound = Float64[], Tempo_Segundos = Float64[])
    
    # Lista todos os arquivos que terminam com .dat
    arquivos = filter(x -> endswith(x, ".dat"), readdir(caminho_da_pasta))
    
    if isempty(arquivos)
        println("Nenhum arquivo .dat encontrado nessa pasta! Verifique o caminho.")
        return
    end

    for arquivo in arquivos
        caminho_completo = joinpath(caminho_da_pasta, arquivo)
        println("-> Resolvendo: $arquivo")
        
        # Lê a instância usando o seu leitor
        d_instancia = Dados.dados()
        Dados.leitura(d_instancia, caminho_completo)
        
        # Marca o tempo e roda o modelo relaxado
        tempo_inicio = time()
        lb = resolver_modelo_221_relaxado(d_instancia)
        tempo_total = time() - tempo_inicio
        
        # Salva na tabela (se o solver der erro, salva como -1.0)
        valor_lb = isnothing(lb) ? -1.0 : round(lb, digits=2)
        push!(resultados, (arquivo, valor_lb, round(tempo_total, digits=2)))
    end
    
    # Exporta para um arquivo Excel/CSV
    nome_arquivo_saida = "resultados_limites_inferiores.csv"
    CSV.write(nome_arquivo_saida, resultados)
    
    println("-"^50)
    println("Bateria finalizada com sucesso! Foram testadas $(length(arquivos)) instâncias.")
    println("Os resultados foram salvos no arquivo: ", nome_arquivo_saida)
end

end # modulee