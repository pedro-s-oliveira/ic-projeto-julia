module PRP_Relaxado_Cap2

using JuMP
using HiGHS

export resolver_modelo_221_relaxado

function resolver_modelo_221_relaxado(d)
    modelo = Model(HiGHS.Optimizer)
    # set_silent(modelo)

    T_set = 1:d.T
    N_set = 1:d.n
    N0_set = 0:d.n
    
    k_unico = 1 
    Q_homogeneo = d.Q[1] 

    M_prod = zeros(d.T)
    for t in T_set
        demanda_restante = sum(d.d[(i, k_unico, tau)] for tau in t:d.T, i in N_set)
        M_prod[t] = min(d.C[k_unico], demanda_restante)
    end

    M_deliv = zeros(d.n, d.T)
    for i in N_set, t in T_set
        demanda_restante_cli = sum(d.d[(i, k_unico, tau)] for tau in t:d.T)
        M_deliv[i, t] = min(d.U[(i, k_unico)], Q_homogeneo, demanda_restante_cli)
    end

    # Função salva-vidas: Calcula o custo na hora e evita o KeyError da matriz d.c!
    function custo_rota(i, j)
        return sqrt((d.x[i] - d.x[j])^2 + (d.y[i] - d.y[j])^2)
    end

    @variable(modelo, p[t in T_set] >= 0)                  
    @variable(modelo, I[i in N0_set, t in 0:d.T] >= 0)     
    @variable(modelo, q[i in N_set, t in T_set] >= 0)      
    @variable(modelo, o[i in N_set, t in T_set] >= 0)      
    
    @variable(modelo, 0 <= y[t in T_set] <= 1)             
    @variable(modelo, 0 <= x[i in N0_set, j in N0_set, t in T_set; i != j] <= 1) 
    @variable(modelo, 0 <= z[i in N_set, t in T_set] <= 1) 
    @variable(modelo, 0 <= z0[t in T_set] <= d.V)

    @objective(modelo, Min, 
        sum(d.l[k_unico] * y[t] + d.u[k_unico] * p[t] + 
            sum(d.h[(i, k_unico)] * I[i, t] for i in N0_set) + 
            sum(custo_rota(i,j) * x[i,j,t] for i in N0_set, j in N0_set if i != j) 
        for t in T_set)
    )

    for i in N0_set
        fix(I[i, 0], d.I0[(i, k_unico)]; force=true)
    end

    @constraint(modelo, [t in T_set], p[t] <= M_prod[t] * y[t])

    @constraint(modelo, [t in T_set], 
        I[0, t] == I[0, t-1] + p[t] - sum(q[i, t] for i in N_set)
    )

    @constraint(modelo, [i in N_set, t in T_set], 
        I[i, t] == I[i, t-1] + q[i, t] - d.d[(i, k_unico, t)]
    )

    @constraint(modelo, [t in T_set], I[0, t] <= d.U[(0, k_unico)])
    @constraint(modelo, [i in N_set, t in T_set], I[i, t] + q[i, t] <= d.U[(i, k_unico)])
    @constraint(modelo, [i in N_set, t in T_set], q[i, t] <= M_deliv[i, t] * z[i, t])

    @constraint(modelo, [i in N_set, t in T_set], 
        sum(x[i, j, t] for j in N0_set if j != i) == z[i, t]
    )
    @constraint(modelo, [i in N_set, t in T_set], 
        sum(x[j, i, t] for j in N0_set if j != i) + sum(x[i, j, t] for j in N0_set if j != i) == 2 * z[i, t]
    )
    
    @constraint(modelo, [t in T_set], sum(x[0, j, t] for j in N_set) == z0[t])
    @constraint(modelo, [t in T_set], sum(x[i, 0, t] for i in N_set) == z0[t])

    @constraint(modelo, [i in N_set, j in N_set, t in T_set; i != j], 
        o[i, t] - o[j, t] >= q[i, t] - M_deliv[i, t] * (1 - x[i, j, t])
    )

    @constraint(modelo, [i in N_set, t in T_set], o[i, t] <= Q_homogeneo * z[i, t])

    optimize!(modelo)
    
    if termination_status(modelo) == MOI.OPTIMAL
        bound = objective_value(modelo)
        println("=> [Cap 2.2.1 Relaxado] Resolvido! Lower Bound: ", round(bound, digits=2))
        return bound
    else
        println("=> [Cap 2.2.1 Relaxado] O modelo nao convergiu. Status: ", termination_status(modelo))
        return nothing
    end
end

end # module