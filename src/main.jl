# O ponto de entrada do projeto
module MeuProjeto

include("calculos.jl")
include("DaTA.jl")                 
include("PRP_Relaxado_Cap2.jl")  

using .Dados               
using .PRP_Relaxado_Cap2          

function executar()
    # Seu código original
    qtd = 150
    preco = 12.50
    total = calcular_custo_total(qtd, preco)
    println("O custo total da producao e: ", formatar_moeda(total))

    # O nosso código
    println("--------------------------------------------------")
    println("Localizando e lendo a instância ABS2_50_6.dat...")

    caminho_arquivo = joinpath(@__DIR__, "ABS2_50_6.dat")
    dados_instancia = Dados.dados()
    Dados.leitura(dados_instancia, caminho_arquivo)

    println("Dados carregados! Resolvendo modelo compacto relaxado (Cap 2.2.1)...")

    # A chamada ao modelo está protegida aqui dentro!
    lb_relaxado = resolver_modelo_221_relaxado(dados_instancia)

    println("--------------------------------------------------")
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
        
        for t in 1:T
            demanda[idx, t] = d_original.d[(i, 1, t)]
        end
    end
    
    estoque_maximo[1] = d_original.U[(0, 1)]
    custo_estoque[1] = d_original.h[(0, 1)]
    
    u = d_original.u[1] 
    f = d_original.l[1] 
    C = d_original.C[1] 
    
    return (n=n_clientes, T=T, c=custo_rota, d=demanda, 
            L=estoque_maximo, h=custo_estoque, u=u, f=f, C=C)
end

function build_RMP(d_prp)
    # Inicializa o modelo com HiGHS
    model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false))
    
    T = d_prp.T
    n_clientes = d_prp.n
    clientes = 2:(n_clientes + 1)
    deposito = 1
    
    # --- VARIÁVEIS ORIGINAIS (CONFORME FORMULAÇÃO 34-38 DO ARTIGO) ---
    @variable(model, p[1:T] >= 0)                   # Produção (pt) [cite: 164]
    @variable(model, I[1:(n_clientes+1), 0:T] >= 0) # Estoque (Iit) [cite: 165]
    @variable(model, 0 <= y[1:T] <= 1)              # Setup relaxado (yt) [cite: 166]
    
    # Variáveis Artificiais (Big-M) para garantir viabilidade na iteração zero
    @variable(model, art_plant[1:T] >= 0)
    @variable(model, art_cust[clientes, 1:T] >= 0)
    
    # --- FUNÇÃO OBJETIVO (EQUAÇÃO 34) --- 
    # Nota: A parte dos planos de entrega (theta) será adicionada dinamicamente
    @objective(model, Min, 
        sum(d_prp.u * p[t] + d_prp.f * y[t] for t in 1:T) +                # Produção + Setup
        sum(d_prp.h[1] * I[deposito, t] for t in 1:T) +                    # Estoque Fábrica
        sum(d_prp.h[i] * I[i, t] for i in clientes, t in 1:T) +            # Estoque Clientes
        1e7 * (sum(art_plant[t] for t in 1:T) + sum(art_cust[i, t] for i in clientes, t in 1:T)) # Penalidade
    )
    
    # --- RESTRIÇÕES FIXAS ---
    
    # Estoque inicial (I0) [cite: 162]
    for i in 1:(n_clientes+1)
        fix(I[i, 0], d_prp.L[i] * 0.0, force=true) # Ajuste para d_prp.I0 se necessário
    end

    # (35) Balanço de Estoque na Fábrica [cite: 343]
    @constraint(model, balanco_planta[t=1:T],
        I[deposito, t-1] + p[t] + art_plant[t] == I[deposito, t]
    )

    # (36) Balanço de Estoque nos Clientes [cite: 347]
    @constraint(model, balanco_cliente[i=clientes, t=1:T],
        I[i, t-1] + art_cust[i, t] == d_prp.d[i, t] + I[i, t]
    )

    # (37) Seleção de plano de entrega (No máximo 1 por período) [cite: 351]
    @constraint(model, selecao_plano[t=1:T], 0.0 <= 1.0)

    # (4) Capacidade de Produção [cite: 194]
    @constraint(model, cap_prod[t=1:T], p[t] <= d_prp.C * y[t])

    # (5) e (6) Capacidades de Estoque [cite: 194]
    @constraint(model, cap_est_planta[t=1:T], I[deposito, t] <= d_prp.L[deposito])
    @constraint(model, cap_est_cliente[i=clientes, t=1:T], I[i, t] <= d_prp.L[i])
    
    return model
end

function main()
    # Inicializa a struct e lê os dados brutos do arquivo .dat
    d_bruto = Dados.dados()
    Dados.leitura(d_bruto)
    
    # Executa o adaptador: agora d_prp tem matrizes rápidas para o JuMP
    d_prp = adaptar_dados_prp(d_bruto)
    
    println("Dados adaptados com sucesso! Clientes: ", d_prp.n, " | Períodos: ", d_prp.T)
    
    # A partir daqui construiremos o create_master_model do PRP
    # ...
end

# Isso invoca a sua função sem causar o erro de World Age
Base.invokelatest(executar)

end
