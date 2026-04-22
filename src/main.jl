module MeuProjeto

include("calculos.jl")
include("DaTA.jl")                 
include("PRP_Relaxado_Cap2.jl")  
include("RmP.jl") 

using .Dados               
using .PRP_Relaxado_Cap2          
using .Rmp 
using JuMP, HiGHS

# ==============================================================================
# ESTRUTURAS E UTILITÁRIOS
# ==============================================================================

mutable struct QRoute
    h::Int 
    i::Int 
    j::Int 
    d::Int 
    rc::Float64
    U::BitSet 
    UE::Vector{Int}
    
    QRoute() = new(0, 0, 0, 0, 0.0, BitSet(), Int[])
end

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

function extract_duals(rmp_struct, d_prp)
    model = rmp_struct.mdl
    T, n_clientes = d_prp.T, d_prp.n
    alpha1, alpha3 = zeros(T), zeros(T)
    alpha2 = zeros(n_clientes + 2, T)
    
    if has_duals(model)
        for t in 1:T
            alpha1[t] = dual(rmp_struct.cnst[:balanco_planta][t])
            alpha3[t] = dual(rmp_struct.cnst[:selecao_plano][t])
            for i in 2:(n_clientes+1)
                alpha2[i, t] = dual(rmp_struct.cnst[:balanco_cliente][i, t])
            end
        end
    end
    return alpha1, alpha2, alpha3
end

function adicionar_coluna_prp!(rmp_struct, d_prp, t, entregas, custo_rota)
    model = rmp_struct.mdl
    theta = @variable(model, lower_bound=0.0, upper_bound=1.0)
    
    set_objective_coefficient(model, theta, custo_rota)
    
    total_entregue = sum(entregas)
    if total_entregue > 0
        set_normalized_coefficient(rmp_struct.cnst[:balanco_planta][t], theta, -Float64(total_entregue))
    end
    
    for i in 2:(d_prp.n + 1)
        if entregas[i] > 0
            set_normalized_coefficient(rmp_struct.cnst[:balanco_cliente][i, t], theta, Float64(entregas[i]))
        end
    end
    
    set_normalized_coefficient(rmp_struct.cnst[:selecao_plano][t], theta, 1.0)
end

# ==============================================================================
# SUBPROBLEMA DE PRICING (Q-ROUTES PARA PRP)
# ==============================================================================

function qroutes_prp(d_prp, alpha1, alpha2, alpha3, t, E, UE)
    total_nodes = d_prp.n + 2
    deposito, copia = 1, total_nodes
    cap = d_prp.C 

    # 1. Custos Reduzidos dos Arcos 
    _c = zeros(Float64, total_nodes, total_nodes)
    for i in 1:(total_nodes-1), j in 2:total_nodes
        if i != j
            dist = d_prp.c[i, j]
            _c[i, j] = (j == copia) ? dist : dist - ((alpha2[j, t] - alpha1[t]) * d_prp.d[j, t])
        end
    end

    # 2. Programação Dinâmica COM ELEMENTARIEDADE (Prevenção de Ciclos)
    R = [QRoute() for o in 1:(cap + 1), i in 1:total_nodes]
    for o in 0:cap, i in 2:total_nodes
        idx = o + 1
        dem = (i == copia) ? 0 : d_prp.d[i, t]
        if o == dem
            R[idx, i].rc = (i != copia) ? _c[i, copia] : 0.0
            R[idx, i].j, R[idx, i].d = copia, o - dem
            
            # Inicializa a memória da rota (BitSet)
            R[idx, i].U = BitSet()
            if i != copia
                push!(R[idx, i].U, i)
            end
        elseif o < dem 
            R[idx, i].rc = 1e9 
        end
    end

    for o in 1:cap, i in 2:(total_nodes-1)
        dem = d_prp.d[i, t]
        if o > dem
            best_rc, next_node = 1e9, -1
            best_U = BitSet()
            prev_idx = o - dem + 1
            
            for j in 2:total_nodes
                # MÁGICA AQUI: !(i in R[prev_idx, j].U) bloqueia clientes já visitados!
                if i != j && !(i in R[prev_idx, j].U)
                    if R[prev_idx, j].rc + _c[i, j] < best_rc
                        best_rc = R[prev_idx, j].rc + _c[i, j]
                        next_node = j
                        best_U = R[prev_idx, j].U
                    end
                end
            end
            
            R[o+1, i].rc, R[o+1, i].j, R[o+1, i].d = best_rc, next_node, o - dem
            R[o+1, i].U = copy(best_U)
            push!(R[o+1, i].U, i) # Salva o cliente 'i' como visitado
        end
    end

    # 3. Recuperação da Melhor Rota
    best_total_rc, best_i, best_o = 1e9, -1, -1
    for i in 2:(total_nodes-1), o in d_prp.d[i, t]:cap
        lucro_inicial = (alpha2[i, t] - alpha1[t]) * d_prp.d[i, t]
        custo_arco_inicial = d_prp.c[deposito, i] - lucro_inicial
        
        if custo_arco_inicial + R[o+1, i].rc < best_total_rc
            best_total_rc = custo_arco_inicial + R[o+1, i].rc
            best_i, best_o = i, o
        end
    end

    final_rc = best_total_rc + alpha3[t]
    if final_rc >= -0.001 
        return final_rc, Int[], 0.0 
    end

    # Traceback da rota real
    entregas, custo_real = zeros(Int, total_nodes), d_prp.c[deposito, best_i]
    curr_i, curr_o = best_i, best_o
    entregas[curr_i] = d_prp.d[curr_i, t]
    
    while R[curr_o+1, curr_i].j != copia
        next_j = R[curr_o+1, curr_i].j
        custo_real += d_prp.c[curr_i, next_j]
        curr_o, curr_i = R[curr_o+1, curr_i].d, next_j
        entregas[curr_i] = d_prp.d[curr_i, t]
    end
    
    return final_rc, entregas, custo_real + d_prp.c[curr_i, copia]
end

# ==============================================================================
# FLUXO PRINCIPAL
# ==============================================================================

function executar()
    # 1. PARTE ORIGINAL DO SEU PROJETO
    qtd = 150
    preco = 12.50
    total = calcular_custo_total(qtd, preco)
    println("O custo total da producao e: ", formatar_moeda(total))

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

    while any_new_column
        iter += 1
        optimize!(rmp_s.mdl)
        
        if termination_status(rmp_s.mdl) != MOI.OPTIMAL 
            println("Status de término anormal no RMP: ", termination_status(rmp_s.mdl))
            break 
        end
        
        println("Iteração $iter | LB Atual: ", round(objective_value(rmp_s.mdl), digits=2))
        
        a1, a2, a3 = extract_duals(rmp_s, d_prp)
        any_new_column = false

        for t in 1:d_prp.T
            rc, entregas, custo_r = qroutes_prp(d_prp, a1, a2, a3, t, [], [])
            if rc < -0.001
                println("   -> [Adicionada] t = $t | Custo Reduzido: $(round(rc, digits=2)) | Total Entregue: $(sum(entregas))")
                adicionar_coluna_prp!(rmp_s, d_prp, t, entregas, custo_r)
                any_new_column = true
            end
        end
    end

    println("\n" * "="^40)
    println("SOLUÇÃO FINAL ALCANÇADA")
    println("Lower Bound Geração de Colunas: ", objective_value(rmp_s.mdl))
    println("Total de iterações: ", iter)
    println("="^40)
end

# Invocando a função principal no escopo correto para evitar os avisos de World Age
Base.invokelatest(executar)

end