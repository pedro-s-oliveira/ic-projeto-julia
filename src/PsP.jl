# modulo para tratar o subproblema de precificacao (PSP - pricing subproblem)
module Psp
    include("DaTA.jl") 
    using .Dados
    include("RmP.jl") 
    using .Rmp
    include("PMR.jl") 

    Base.@kwdef mutable struct qroute
        pred::Tuple{Int, Int} = (0, 0)
        load::Vector{Int} = Int[]
        cred::Float64 = 0.0
        bset::BitVector = BitVector()
        cost::Float64 = 0.0
        rseq::Vector{Int} = Int[]
    end

    function qroutes(d, rmp)
        println("q-routes")
        
        π = Dict{Tuple{Int,Int},Float64}() 
        δ = Dict{Tuple{Int,Int},Float64}() 
        c̄ = Dict{Tuple{Int,Int},Float64}()
        
        # --- CORREÇÃO CRÍTICA ---
        # Extrair todos os duais de todos os períodos ANTES de injetar qualquer coluna
        for t_all in 1:d.T
            for i_all in 1:d.n
                δ[(i_all, t_all)] = dual(rmp.cnst[:balanco_cliente][i_all, t_all])
                π[(i_all, t_all)] = dual(rmp.cnst[:limite_visitas][i_all, t_all])
            end
        end
        
        k = 1
        v = 1

        for t in 1:d.T
            println("t = ", t)

            # Cálculo do custo reduzido da distância 
            for a in d.A
                i = a[1]
                if i > 0 && i < d.n + 1
                    c̄[a] = d.c[a] - π[(i,t)]
                else
                    c̄[a] = d.c[a]
                end
            end
            
            # Inicialização
            R = [qroute() for q in 1:d.Q[v], j in 1:d.n]
            for q in 1:d.Q[v]
                for j in 1:d.n
                    if q <= d.Mtil[(j,k,v,t)]
                        qⱼ = Int(q)
                        R[q, j] = qroute(
                            pred = (0, 0), 
                            load = [cliente == j ? qⱼ : 0 for cliente in 1:d.n], 
                            cred = d.c[(0,j)] - qⱼ*δ[(j,t)], 
                            bset = BitVector(cliente == j for cliente in 1:d.n),
                            cost = d.c[(0,j)],
                            rseq = [j]
                        )
                    else
                        R[q, j] = qroute(
                            pred = (-1, -1), 
                            load = zeros(Int, d.n), 
                            cred = +Inf, 
                            bset = falses(d.n),
                            cost = +Inf,
                            rseq = Int[]
                        )
                    end
                end
            end
            
            # Preenchimento
            for q₁ in 1:d.Q[v]
                for i in 1:d.n
                    if R[q₁, i].cred != +Inf
                        for q₂ in (Int(q₁)+1):d.Q[v]
                            for j in 1:d.n
                                
                                # CORREÇÃO: O caminhão NÃO PODE visitar um cliente que já está na rota! (Evita os ciclos)
                                if i != j && !R[q₁, i].bset[Int(j)]
                                    
                                    Δ = Int(q₂) - Int(q₁)
                                    if R[q₁, i].load[j] + Δ <= d.Mtil[(j,k,v,t)]
                                        cᵣ = R[q₁, i].cred - c̄[(i,j)] - Δ*δ[(j,t)]
                                        if cᵣ < R[q₂, j].cred
                                            
                                            novo_load = copy(R[q₁, i].load)
                                            novo_load[Int(j)] = novo_load[Int(j)] + Δ

                                            novo_bset = copy(R[q₁, i].bset)
                                            novo_bset[Int(j)] = true

                                            R[q₂, j] = qroute(
                                                pred = (q₁, i), 
                                                load = novo_load, 
                                                cred = cᵣ, 
                                                bset = novo_bset,
                                                cost = R[q₁, i].cost + d.c[(i,j)],
                                                rseq = [R[q₁, i].rseq; j]
                                            )
                                        end
                                    end
                                end
                                
                            end
                        end
                    end
                end
            end
            
            # Recuperacao e injeção (APENAS A MELHOR ROTA DO DIA)
            melhor_q = -1
            melhor_j = -1
            melhor_cr = 0.0

            # 1. Encontra a rota mais lucrativa (mais negativa)
            for q in 1:d.Q[v]
                for j in 1:d.n
                    cᵣ = R[q, j].cred
                    if cᵣ < melhor_cr
                        melhor_cr = cᵣ
                        melhor_q = q
                        melhor_j = j
                    end
                end
            end

            # 2. Injeta APENAS a melhor rota encontrada no dia
            if melhor_cr < -1e-4
                vNumVisitas = zeros(Int64, d.n)
                for i in R[melhor_q, melhor_j].rseq
                    vNumVisitas[i] += 1
                end

                adicionar_coluna_prp!(rmp, d, t, R[melhor_q, melhor_j].load, vNumVisitas, R[melhor_q, melhor_j].cost)
                println("   -> Nova rota adicionada! Custo Reduzido: ", round(melhor_cr, digits=2))
            end            
        end
    end
end