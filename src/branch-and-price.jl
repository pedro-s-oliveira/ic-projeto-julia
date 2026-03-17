using JuMP
using HiGHS

# -----------------------------
# Dados do problema
# -----------------------------
L = 100                # comprimento da barra
demand = [20, 30, 15]  # demanda de cada tipo
sizes = [45, 36, 31]   # tamanhos das peças
n = length(sizes)

# -----------------------------
# Modelo Mestre Restrito
# -----------------------------
master = Model(HiGHS.Optimizer)
set_silent(master)

# Padrões iniciais (um padrão por item)
patterns = [[i == j ? floor(Int, L / sizes[j]) : 0 for j in 1:n] for i in 1:n]

@variable(master, λ[1:length(patterns)] >= 0)
@constraint(master, [i in 1:n], sum(patterns[j][i] * λ[j] for j in 1:length(patterns)) >= demand[i])
@objective(master, Min, sum(λ))

optimize!(master)

# -----------------------------
# Função para resolver subproblema (Knapsack)
# -----------------------------
function generate_column(prices)
    sub = Model(HiGHS.Optimizer)
    set_silent(sub)
    @variable(sub, x[1:n] >= 0, Int)
    @constraint(sub, sum(sizes[i] * x[i] for i in 1:n) <= L)
    @objective(sub, Max, sum(prices[i] * x[i] for i in 1:n))
    optimize!(sub)
    return value.(x), objective_value(sub)
end

# -----------------------------
# Loop de geração de colunas
# -----------------------------
while true
    duals = dual.(master[:constraint])
    new_pattern, reduced_cost = generate_column(duals)
    if reduced_cost <= 1 + 1e-6
        break
    end
    push!(patterns, new_pattern)
    @variable(master, λ_new >= 0)
    @constraint(master, [i in 1:n], sum(patterns[j][i] * λ[j] for j in 1:length(patterns)) >= demand[i])
    @objective(master, Min, sum(λ))
    optimize!(master)
end

println("Valor ótimo relaxado: ", objective_value(master))
