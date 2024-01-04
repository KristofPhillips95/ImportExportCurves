include("../ImportExport/cost_curves_builder.jl")
import JSON3

#Define global parameters
scenario = "National Trends"
endtime = 24*2
year = 2025
CY_cap = 1984
CY_ts = 2012
VOLL = 8000
ty = 2025

country = "BE00"
curve_dict = Dict()
import_dict = Dict()
export_dict = Dict()

import_levels = -2000:100:2000

#Optimize dispatch model with given capacities from input data
m2,soc,production =  optimize_and_retain_intertemporal_decisions_no_DSR(scenario::String,year::Int,CY_cap::Int,CY_ts,endtime,VOLL,ty)

#Save the soc and production levels of dispatch model
open(joinpath("soc_files","soc_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"), "w") do io
    JSON3.write(io, write_sparse_axis_to_dict(soc))
end


open(joinpath("soc_files","prod_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"), "w") do io
    JSON3.write(io, write_sparse_axis_to_dict(production))
end


# Load the soc and production levels of dispatch model
soc_dict = JSON3.read(read(joinpath("soc_files","soc_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"), String))
production_dict = JSON3.read(read(joinpath("soc_files","prod_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"), String))

#Test equality of soc and production dict

m2 = build_model_for_import_curve(m2,0,country,endtime,soc,production,0)

m3 = build_model_for_import_curve_from_dict(0,country,endtime,soc_dict,production_dict,0)



for import_level in import_levels
    country_fail = "DE00"
    change_import_level!(m2,endtime,import_level)
    change_import_level!(m3,endtime,import_level)

    optimize!(m2)
    optimize!(m3)

    check_production_zero!(m2,country,endtime)
    check_net_import(m2,country,import_level,endtime)

    # check_production_zero!(m2,country_fail,endtime)
    #check_net_import(m2,country_fail,import_level,endtime)

    check_production_zero!(m3,country,endtime)
    check_net_import(m3,country,import_level,endtime)

    check_equal_soc_for_all_but(m3,m2,country,endtime)

    #TODO: Check why this one does not fail the assertion 
    check_equal_soc_for_all_but(m3,m2,country_fail,endtime)
    println(JuMP.objective_value(m2))
    println(JuMP.objective_value(m3) - JuMP.objective_value(m2))
    @assert(round(JuMP.objective_value(m2),digits = 0) == round(JuMP.objective_value(m3),digits = 0))

    import_prices = [JuMP.dual.(m2.ext[:constraints][:demand_met][country,t]) for t in 1:endtime]
    curve_dict[import_level] = import_prices

    import_dict[import_level] = [sum(JuMP.value.(m2.ext[:variables][:import][country,nb,t]) for nb in m2.ext[:sets][:connections][country]) for t in 1:endtime]
    export_dict[import_level] = [sum(JuMP.value.(m2.ext[:variables][:export][country,nb,t]) for nb in m2.ext[:sets][:connections][country]) for t in 1:endtime]
    end

write_prices(curve_dict,scenario,import_levels,"$(year)_CY_$(CY_ts)_$(endtime)")

# import_dict[1000]
# export_dict[1000]
# m2.ext[:objective]