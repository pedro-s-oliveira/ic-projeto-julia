#module MeuProjeto

#include("calculos.jl")
include("DaTA.jl")                 
include("PRP_Relaxado_Cap2.jl")  
include("RmP.jl") 
include("PMR.jl")
include("PsP.jl")

using .Dados               
using .PRP_Relaxado_Cap2          
using .Rmp 
#using .PMR
using .Psp
using JuMP, HiGHS

# ==============================================================================
# ESTRUTURAS E UTILITÁRIOS
# ==============================================================================

function adaptar_dados_prp(d_original::Dados.dados)
    n_clientes = d_original.n
    T = d_original.T
    total_nos = n_clientes + 2
    custo_rota = zeros(Float64, total_nos, total_nos)
    demanda = zeros(Int, total_nos, T)
    estoque_maximo = zeros(Int, total_nos)
    custo_estoque = zeros(Float64, total_nos)
    
    for a in d_original.A
        i, j = a[1], a[2]
        idx_i = i == 0 ? 1 : i + 1
        idx_j = j == d_original.n + 1 ? total_nos : j + 1
        custo_rota[idx_i, idx_j] = d_original.c[a]
    end
    
    for i in 1:n_clientes
        idx = i + 1
        estoque_maximo[idx] = d_original.U[(i, 1)]
        custo_estoque[idx] = d_original.h[(i, 1)]
        for t in 1:T demanda[idx, t] = d_original.d[(i, 1, t)] end
    end
    
    estoque_maximo[1] = d_original.U[(0, 1)]
    custo_estoque[1] = d_original.h[(0, 1)]
    
    return (n=n_clientes, T=T, c=custo_rota, d=demanda, 
            L=estoque_maximo, h=custo_estoque, 
            u=d_original.u[1], f=d_original.l[1], C=d_original.C[1])
end

# ==============================================================================
# GESTÃO DE COLUNAS E DUAIS
# ==============================================================================

# ==============================================================================
# FLUXO PRINCIPAL
# ==============================================================================
function executar()
    println("--------------------------------------------------")
    println("Localizando e lendo a instância ABS2_50_6.dat...")
    caminho_arquivo = joinpath(@__DIR__, "ABS2_50_6.dat")
    dados_instancia = Dados.dados()
    Dados.leitura(dados_instancia, caminho_arquivo)

    println("Dados carregados! Resolvendo modelo compacto relaxado (Cap 2.2.1)...")
    lb_relaxado = resolver_modelo_221_relaxado(dados_instancia)
    println("--------------------------------------------------")

    # 2. GERAÇÃO DE COLUNAS
    println("\nIniciando a adaptação dos dados para o Problema Mestre (RMP)...")
    d_prp = adaptar_dados_prp(dados_instancia)
    rmp_s = Rmp.createRMP(d_prp)

    println("\nIniciando Geração de Colunas...")
    any_new_column = true
    iter = 0
    
    # --- VARIÁVEIS DE CONTROLE RESTAURADAS ---
    best_lb = Inf
    stagnation_counter = 0
    max_stagnation = 5
    tolerancia = 50.0
    maxIter = 1500

    while any_new_column && iter < maxIter 
        iter += 1
        
        # 1. Resolve o Problema Mestre Restrito (RMP) atual
        optimize!(rmp_s.mdl)
        
        # 2. Verifica o status da otimização para garantir que não deu Inviável
        status_mestre = termination_status(rmp_s.mdl)
        if status_mestre != MOI.OPTIMAL 
            println("Status de término anormal no RMP: ", status_mestre)
            break 
        end
        
        current_lb = objective_value(rmp_s.mdl)
        println("Iteração $iter | LB Atual: ", round(current_lb, digits=2))
        
        # --- VERIFICAÇÃO DE ESTAGNAÇÃO (MINIMIZAÇÃO) ---
        if current_lb < best_lb - tolerancia
            best_lb = current_lb
            stagnation_counter = 0 
        else
            stagnation_counter += 1
        end

        if stagnation_counter >= max_stagnation
            println("\n[!] ALERTA: O algoritmo atingiu o limite de estagnação ($max_stagnation iterações com melhoria menor que $tolerancia).")
            break
        end

        # 3. Chama o subproblema com os duais já gerados
        Psp.qroutes(dados_instancia, rmp_s)
        
        # Nota: Como o bloco antigo do any_new_column foi comentado, 
        # o laço vai rodar até atingir a estagnação.
    end

    #=
    a1, a2, a3 = extract_duals(rmp_s, d_prp)
    any_new_column = false

    for t in 1:d_prp.T
        rc, entregas, custo_r = qroutes_prp(d_prp, a1, a2, a3, t, [], [])
        # Usamos uma tolerância um pouco maior para evitar rotas "fantasmas"
        if rc < -1.0 
            adicionar_coluna_prp!(rmp_s, d_prp, t, entregas, custo_r)
            any_new_column = true
        end
    end
    =#

    println("\n" * "="^50)
    println("🏁 SOLUÇÃO FINAL DA GERAÇÃO DE COLUNAS")
    println("Lower Bound Compacto original : 102600.82")
    
    # Trava de segurança para evitar crash na impressão
    if has_values(rmp_s.mdl)
        println("Lower Bound Geração de Colunas: ", round(objective_value(rmp_s.mdl), digits=2))
    else
        println("Lower Bound Geração de Colunas: Indisponível (Falha no solver)")
    end
    
    println("Total de iterações executadas : ", iter)
    println("="^50)
end

# Invocando a função principal no escopo correto para evitar os avisos de World Age
Base.invokelatest(executar)