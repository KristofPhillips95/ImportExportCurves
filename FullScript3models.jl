include("ImportExport/build_and_run.jl")
include("ImportExport/build_and_save_cost_curves.jl")
using Gurobi
using Plots

#Initialise global parameters
gpd = Dict()

run_name = "Test_loop_3"
gpd["endtime"] = 24*10
gpd["Climate_year"] = 1984
gpd["Climate_year_ts"] = 2012
gpd["ValOfLostLoad"] = 8000
gpd["country"] = "BE00"
gpd["scenario"] = "National Trends"
gpd["year"] = 2025
gpd["stepsize"] = 100
gpd["transport_cost"] = 0.1

types = ["isolated","NTC","TradeCurves"]
#Start looping over desired global parameters: 

for type in types: 
    gpd["type"] = type

    #Then, build the relevant cost curves 
    if gpd["type"] == "TradeCurves"
        build_and_save_cost_curves(global_param_dict = gpd)
    end
    results = DataFrame()
    m = Model(optimizer_with_attributes(Gurobi.Optimizer))

    row = full_build_and_optimize_investment_model(m,global_param_dict = gpd)
    global results = vcat(results,row)
    CSV.write(joinpath("Results","InvestmentModelResults",run_name),results)


m.ext[:objective]









#Inspection

trade_prices = m.ext[:sets][:trade_prices]
timesteps = collect(1:gpd["endtime"])
imports = [JuMP.value.(sum(m.ext[:variables][:import]["BE00",p,t] for p in trade_prices)) for t in timesteps]
exports = [JuMP.value.(sum(m.ext[:variables][:export]["BE00",p,t] for p in trade_prices)) for t in timesteps]


c_import = [sum(JuMP.value.(m.ext[:variables][:import][gpd["country"],neighbor,t] for neighbor in m.ext[:sets][:connections][gpd["country"]])) for t in timesteps]
c_export = [sum(JuMP.value.(m.ext[:variables][:export][gpd["country"],neighbor,t] for neighbor in m.ext[:sets][:connections][gpd["country"]])) for t in timesteps]


#Visualise total imports and exports
plot(imports,label = "Imports TC")
plot!(-exports, label = "Exports TC")
plot!(c_import -c_export, label = "Net import interconnected")

m.ext[:objective]