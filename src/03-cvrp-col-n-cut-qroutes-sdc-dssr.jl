using JuMP
using HiGHS
using LinearAlgebra
using Dates

mutable struct QROUTE
    h::Int # predecessor
    i::Int # current
    j::Int # next
    d::Int # demand for the next
    rc::Float64
    U::BitSet
    UE::Vector{Int}
end

mutable struct DAT
    n::Int
    m::Int
    Q::Int
    coordx::Vector{Float64}
    coordy::Vector{Float64}
    c::Matrix{Float64}
    q::Vector{Int}
    dpt::Int
    dptc::Int
    name::String
end

mutable struct CWSAVING
    stop1::Int
    stop2::Int
    saving::Float64
end

# Variáveis globais para armazenar as referências do modelo e gerar colunas
mutable struct CGModel
    model::Model
    x::Vector{VariableRef}
    visit_cons::Vector{ConstraintRef}
    veh_con::ConstraintRef
    sdc_cons::Vector{ConstraintRef}
end

function read_data(filename::String)
    # Tokenizer simples para replicar o comportamento do `cin >>`
    tokens = String[]
    for line in eachline(filename)
        append!(tokens, split(line))
    end
    
    pos = 1
    function next_token()
        val = tokens[pos]
        pos += 1
        return val
    end

    n = parse(Int, next_token())
    Q = parse(Int, next_token())

    # Em Julia, usaremos índices de 1 até n+2
    # 1: depot, 2..n+1: clients, n+2: depot copy
    coordx = zeros(Float64, n+2)
    coordy = zeros(Float64, n+2)
    q = zeros(Int, n+2)
    c = zeros(Float64, n+2, n+2)

    tot_of = 0
    for i in 1:n+1
        coordx[i] = parse(Float64, next_token())
        coordy[i] = parse(Float64, next_token())
        q[i] = parse(Int, next_token())
        
        if i == 1 # C++ i == 0 (depot)
            coordx[n+2] = coordx[i]
            coordy[n+2] = coordy[i]
            q[n+2] = q[i]
        end
        tot_of += q[i]
    end

    m = Int(ceil(tot_of / Q))

    for i in 1:n+1
        for j in 2:n+2
            if i != j
                if !(i == 1 && j == n+2)
                    c[i, j] = floor(sqrt((coordx[i] - coordx[j])^2 + (coordy[i] - coordy[j])^2) + 0.5)
                end
            end
        end
    end

    return DAT(n, m, Q, coordx, coordy, c, q, 1, n+2, filename)
end

function create_master_model(d::DAT)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    
    x = VariableRef[]
    
    # Restrições de visita (Partitioning) -> = 1
    visit_cons = ConstraintRef[]
    for r in 1:d.n
        push!(visit_cons, @constraint(model, AffExpr(0.0) == 1.0))
    end
    
    # Restrição de veículos -> = m
    veh_con = @constraint(model, AffExpr(0.0) == d.m)
    
    cgm = CGModel(model, x, visit_cons, veh_con, ConstraintRef[])

    # Variáveis artificiais para os clientes iniciais
    for r in 1:d.n
        node = r + 1
        obj = d.c[d.dpt, node] + d.c[node, d.dptc]
        
        col = @variable(model, lower_bound = 0.0, upper_bound = 1.0)
        push!(x, col)
        set_objective_coefficient(model, col, obj)
        set_normalized_coefficient(visit_cons[r], col, 1.0)
        set_normalized_coefficient(veh_con, col, 1.0)
    end

    return cgm
end

function add_new_columns(cgm::CGModel, d::DAT, air::Vector{Int}, cr::Float64, E::Vector{Int})
    col = @variable(cgm.model, lower_bound = 0.0, upper_bound = 1.0)
    push!(cgm.x, col)
    
    set_objective_coefficient(cgm.model, col, cr)
    
    for i in 1:d.n
        if air[i] != 0
            set_normalized_coefficient(cgm.visit_cons[i], col, Float64(air[i]))
        end
    end
    
    set_normalized_coefficient(cgm.veh_con, col, 1.0)
    
    # Atualiza coeficientes para as Strong Degree Constraints (SDC) já existentes
    for i in 1:length(cgm.sdc_cons)
        e_node = E[i]
        set_normalized_coefficient(cgm.sdc_cons[i], col, min(1.0, Float64(air[e_node])))
    end
end

function add_new_rows(cgm::CGModel, lhs_cut::Vector{Vector{Float64}}, rhs_cut::Vector{Float64})
    for l in 1:length(rhs_cut)
        expr = AffExpr(0.0)
        for r in 1:length(lhs_cut[l])
            add_to_expression!(expr, lhs_cut[l][r] * cgm.x[r])
        end
        # SDC cut sense is >= (G)
        cut = @constraint(cgm.model, expr >= rhs_cut[l])
        push!(cgm.sdc_cons, cut)
    end
end

function clarke_wright(d::DAT, cgm::CGModel, E::Vector{Int})
    cwlist = CWSAVING[]
    for i in 2:d.n+1
        for j in 2:d.n+1
            if i != j && d.q[i] + d.q[j] <= d.Q && i < j
                saving = d.c[d.dpt, i] + d.c[d.dpt, j] - d.c[i, j]
                push!(cwlist, CWSAVING(i, j, saving))
            end
        end
    end

    nodes = collect(2:d.n+1)
    route = zeros(Int, d.n)

    while !isempty(nodes)
        best_cw = CWSAVING(0, 0, 0.0)
        e = 0
        for (c, cw) in enumerate(cwlist)
            if cw.saving > best_cw.saving
                best_cw = cw
                e = c
            end
        end
        if e != 0
            deleteat!(cwlist, e)
        else
            break # Não há mais savings positivos e válidos
        end

        start_n = best_cw.stop1
        end_n = best_cw.stop2
        cr = d.c[d.dpt, start_n] + d.c[start_n, end_n] + d.c[end_n, d.dptc]
        load = d.q[start_n] + d.q[end_n]
        
        fill!(route, 0)
        for i in 2:d.n+1
            if i == start_n || i == end_n
                route[i-1] = 1
                filter!(x -> x != i, nodes)
            end
        end

        full = (load == d.Q)

        while !full
            nxtcw = CWSAVING(0, 0, 0.0)
            choose = 0
            sav = 0.0
            
            for (c, cw) in enumerate(cwlist)
                if cw.saving > sav
                    if cw.stop1 == start_n && load + d.q[cw.stop2] <= d.Q && route[cw.stop2-1] == 0
                        sav = cw.saving; nxtcw = cw; e = c; choose = 1
                    elseif cw.stop1 == end_n && load + d.q[cw.stop2] <= d.Q && route[cw.stop2-1] == 0
                        sav = cw.saving; nxtcw = cw; e = c; choose = 2
                    elseif cw.stop2 == start_n && load + d.q[cw.stop1] <= d.Q && route[cw.stop1-1] == 0
                        sav = cw.saving; nxtcw = cw; e = c; choose = 3
                    elseif cw.stop2 == end_n && load + d.q[cw.stop1] <= d.Q && route[cw.stop1-1] == 0
                        sav = cw.saving; nxtcw = cw; e = c; choose = 4
                    end
                end
            end

            exclude_i = 0

            if choose == 1
                load += d.q[nxtcw.stop2]
                cr += -d.c[d.dpt, start_n] + d.c[d.dpt, nxtcw.stop2] + d.c[nxtcw.stop2, start_n]
                exclude_i = start_n
                start_n = nxtcw.stop2
                route[start_n-1] = 1
                filter!(x -> x != start_n, nodes)
            elseif choose == 2
                load += d.q[nxtcw.stop2]
                cr += -d.c[end_n, d.dptc] + d.c[end_n, nxtcw.stop2] + d.c[nxtcw.stop2, d.dptc]
                exclude_i = end_n
                end_n = nxtcw.stop2
                route[end_n-1] = 1
                filter!(x -> x != end_n, nodes)
            elseif choose == 3
                load += d.q[nxtcw.stop1]
                cr += -d.c[d.dpt, start_n] + d.c[d.dpt, nxtcw.stop1] + d.c[nxtcw.stop1, start_n]
                exclude_i = start_n
                start_n = nxtcw.stop1
                route[start_n-1] = 1
                filter!(x -> x != start_n, nodes)
            elseif choose == 4
                load += d.q[nxtcw.stop1]
                cr += -d.c[end_n, d.dptc] + d.c[end_n, nxtcw.stop1] + d.c[nxtcw.stop1, d.dptc]
                exclude_i = end_n
                end_n = nxtcw.stop1
                route[end_n-1] = 1
                filter!(x -> x != end_n, nodes)
            elseif choose == 0
                full = true
            end

            if load == d.Q
                full = true
            end

            if choose != 0 && exclude_i != 0
                filter!(cw -> cw.stop1 != exclude_i && cw.stop2 != exclude_i, cwlist)
            end
        end

        filter!(cw -> cw.stop1 != start_n && cw.stop1 != end_n && cw.stop2 != start_n && cw.stop2 != end_n, cwlist)
        add_new_columns(cgm, d, route, cr, E)
        
        if isempty(cwlist)
            break
        end
    end
end

function heuristic_initial_solutions(d::DAT, cgm::CGModel, E::Vector{Int})
    Nx = collect(2:d.n+1)
    
    while length(Nx) > 0
        Rx = Int[]
        load = d.Q
        for ir in Nx
            if d.q[ir] <= load
                push!(Rx, ir)
                load -= d.q[ir]
            end
        end
        
        filter!(x -> !(x in Rx), Nx)
        
        if length(Rx) > 0
            air = zeros(Int, d.n)
            for j in 2:d.n+1
                if j in Rx
                    air[j-1] = 1
                end
            end
            
            b = Rx[1]
            e = Rx[end]
            
            cr = d.c[d.dpt, b] + d.c[e, d.dptc]
            for idx in 1:length(Rx)-1
                cr += d.c[Rx[idx], Rx[idx+1]]
            end
            
            add_new_columns(cgm, d, air, cr, E)
        end
    end
end

function sdc(d::DAT, cgm::CGModel, lines::Vector{Int})
    lhs_sdc = [zeros(Float64, length(cgm.x)) for _ in 1:length(lines)]
    rhs_sdc = zeros(Float64, length(lines))
    
    for l in 1:length(lines)
        i = lines[l]
        for r in 1:length(cgm.x)
            air = normalized_coefficient(cgm.visit_cons[i], cgm.x[r])
            lhs_sdc[l][r] = min(1.0, air)
        end
        rhs_sdc[l] = 1.0
    end
    add_new_rows(cgm, lhs_sdc, rhs_sdc)
end

function qroutes(d::DAT, cgm::CGModel, E::Vector{Int}, UE::Vector{Int})
    pi_vals = dual.(cgm.visit_cons)
    pi_veh = dual(cgm.veh_con)
    pi_sdc = dual.(cgm.sdc_cons)
    
    _sigma = zeros(Float64, d.n)
    for s in 1:length(cgm.sdc_cons)
        _sigma[E[s]] = pi_sdc[s]
    end
    
    _c = zeros(Float64, d.n+2, d.n+2)
    for i in 2:d.n+1
        for j in 2:d.n+2
            if i != j
                if !(i == 1 && j == d.n+2)
                    _c[i, j] = d.c[i, j] - pi_vals[i-1]
                else
                    _c[i, j] = 999999999.0
                end
            end
        end
    end
    
    # R[o, i] onde o = 1..Q+1 (capacidade 0 até Q), i = 1..n+2
    R = Matrix{QROUTE}(undef, d.Q+1, d.n+2)
    for o in 1:d.Q+1
        cap = o - 1
        for i in 2:d.n+2
            U_set = BitSet()
            UE_vec = zeros(Int, d.n+2)
            
            rc_val = 0.0
            next_j = -1
            next_d = -1
            
            if cap == d.q[i]
                if i != d.n+2
                    rc_val = _c[i, d.n+2] - _sigma[i-1]
                    UE_vec[i-1] = UE[i-1]
                    push!(U_set, i-1)
                else
                    rc_val = 0.0
                end
                next_j = d.n+2
                next_d = cap - d.q[i] + 1
            elseif cap < d.q[i]
                rc_val = 99999999.0
            elseif cap > d.q[i] && i == d.n+2
                rc_val = 0.0
                next_j = d.n+2
                next_d = 1 # equivalente a 0 na C++
            end
            
            R[o, i] = QROUTE(-1, i, next_j, next_d, rc_val, U_set, UE_vec)
        end
    end
    
    for o in 1:d.Q+1
        cap = o - 1
        for i in 2:d.n+1
            if cap > d.q[i]
                cost = 9999999.0
                nv = -1
                nd = -1
                nU = BitSet()
                U_vec = zeros(Int, d.n)
                
                prev_cap = cap - d.q[i] + 1
                
                for j in 2:d.n+2
                    if i != j
                        rcj = 9999999.0
                        if R[prev_cap, j].UE[i-1] == 0
                            if (i-1) in R[prev_cap, j].U
                                rcj = _c[i, j] + R[prev_cap, j].rc
                            else
                                rcj = _c[i, j] - _sigma[i-1] + R[prev_cap, j].rc
                            end
                        end
                        
                        if rcj < cost
                            cost = rcj
                            nv = j
                            nd = prev_cap
                            nU = BitSet([i-1])
                            for n in 1:d.n
                                if n != i-1
                                    U_vec[n] = R[prev_cap, j].UE[n]
                                elseif n == i-1 && UE[n] == 1
                                    U_vec[n] = 1
                                end
                            end
                        end
                    end
                end
                
                R[o, i].rc = cost
                R[o, i].j = nv
                R[o, i].d = nd
                R[o, i].U = nv != -1 ? union(R[nd, nv].U, nU) : nU
                for n in 1:d.n
                    R[o, i].UE[n] = U_vec[n]
                end
            end
        end
    end
    
    biggerrc = 1000.0
    auxU = zeros(Int, d.n)
    
    for i in 2:d.n+1
        cost = 9999999.0
        d_star = 1
        
        for o in (d.q[i]+1):(d.Q+1)
            if cost > R[o, i].rc
                cost = R[o, i].rc
                d_star = o
            end
        end
        
        cost += d.c[1, i]
        
        j = R[d_star, i].j
        dd = R[d_star, i].d
        
        air = zeros(Int, d.n)
        air[i-1] = 1
        if j != d.n+2 && j != -1
            air[j-1] = 1
        end
        
        cr = d.c[1, i]
        if j != -1
            cr += d.c[i, j]
            while j != d.n+2 && j != -1
                next_j = R[dd, j].j
                if next_j != -1
                    cr += d.c[j, next_j]
                end
                
                ad = R[dd, j].d
                aj = next_j
                dd = ad
                j = aj
                
                if j != d.n+2 && j != -1
                    air[j-1] += 1
                end
            end
        end
        
        add_new_columns(cgm, d, air, cr, E)
        if biggerrc > cost
            biggerrc = cost
            for n in 1:d.n
                auxU[n] = air[n]
            end
        end
    end
    
    for n in 1:d.n
        if auxU[n] > 1
            UE[n] = 1
        end
    end
    
    return biggerrc - pi_veh
end

function main(filename::String)
    d = read_data(filename)
    cgm = create_master_model(d)

    E = Int[] 
    clarke_wright(d, cgm, E)
    heuristic_initial_solutions(d, cgm, E)
    
    UE = zeros(Int, d.n)
    
    timer1 = time()
    foValueInit = 0.0
    anyCycle = true
    iterfw = 0
    rcaux = 0.0
    
    while anyCycle
        iterfw += 1
        optimize!(cgm.model)
        
        if termination_status(cgm.model) != MOI.OPTIMAL
            println("\nNon solved!")
        end
        
        objval = objective_value(cgm.model)
        if foValueInit == 0.0
            foValueInit = objval
        end
        
        rc = -1000.0
        fovl = 0.0
        rc_ = 0.0
        cntit = 0
        itercnt = 0
        rcaux = 0.0
        
        while rc < -0.0001
            itercnt += 1
            rc = qroutes(d, cgm, E, UE)
            
            optimize!(cgm.model)
            objval = objective_value(cgm.model)
            
            rcaux = rc
            
            if rc_ == rc && objval == fovl
                cntit += 1
                if cntit > (floor(d.n/10) - 1)
                    break
                end
            elseif rc_ != rc || objval != fovl
                cntit = 0
                fovl = objval
                rc_ = rc
            end
        end
        
        x_vals = value.(cgm.x)
        lines = Int[]
        
        for r in 1:length(cgm.x)
            if x_vals[r] > 1e-5
                for i in 1:d.n
                    addsdc = true
                    if !isempty(E)
                        if i in E
                            addsdc = false
                        end
                    end
                    
                    if addsdc
                        air_val = normalized_coefficient(cgm.visit_cons[i], cgm.x[r])
                        if air_val > 0.5 && air_val < 1.5 # air[0] != 0 && air[0] != 1
                            if !(i in lines)
                                push!(lines, i)
                                push!(E, i)
                            end
                        end
                    end
                end
            end
        end
        
        if !isempty(lines)
            sdc(d, cgm, lines)
        else
            anyCycle = false
        end
    end
    
    timer3 = time()
    t = timer3 - timer1
    
    objval = objective_value(cgm.model)
    ueCount = sum(UE .> 0)
    
    println("\n__________________________________________\nPrinting SOLUTION")
    println("LB: ", objval)
    println("q-routes-SDC-DSSR")
    println("foInit: \t", foValueInit)
    println("LB : \t\t", objval - rcaux)
    println("rc : \t\t", rcaux)
    println("UE: \t\t", ueCount)
    println("#col: \t\t", length(cgm.x))
    println("#cut: \t\t", length(cgm.sdc_cons))
    println("time: \t\t", t)
    println("#m: \t\t", d.m)
    println("inst: \t\t", filename)
    println("__________________________________________")
end

main("E-n51-k5.dat")
