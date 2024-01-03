include("ImportExport/model_builder.jl")
using Gurobi

scenario = "National Trends"
endtime = 2400
year = 2025
CY = 1984
CY_ts = 2012
VOLL = 10000


only_bel = true
m = Model(optimizer_with_attributes(Gurobi.Optimizer))
define_sets!(m,scenario,year,CY)


all_countries = [key for key in keys(m.ext[:sets][:technologies])]

if only_bel
    define_sets!(m,scenario,year,CY,filter((e->e != "BE00"),all_countries),["BE00"])
else
    define_sets!(m,scenario,year,CY,[],["BE00"])
end

process_parameters!(m,scenario,year,CY,["BE00"])
process_time_series!(m,scenario,year,CY_ts)
remove_capacity_country!(m,"BE00")

build_isolated_investment_model!(m,endtime,VOLL)
optimize!(m)

print("Belgium only = ",only_bel, JuMP.value.(m.ext[:variables][:invested_cap]))
country = "BE00"
sum(JuMP.value.(m.ext[:expressions][:CO2_cost][country,tech,t] for tech in m.ext[:sets][:dispatchable_technologies][country] for t in 1:endtime))
sum(JuMP.value.(m.ext[:expressions][:load_shedding_cost][country,t] for t in 1:endtime))
sum(JuMP.value.(m.ext[:expressions][:VOM_cost][country,tech,t] for tech in m.ext[:sets][:technologies][country] for t in 1:endtime))
sum(JuMP.value.(m.ext[:expressions][:fuel_cost][country,tech,t] for tech in m.ext[:sets][:dispatchable_technologies][country] for t in 1:endtime))
sum(JuMP.value.(m.ext[:expressions][:investment_cost][country,tech] for tech in m.ext[:sets][:investment_technologies][country]))

