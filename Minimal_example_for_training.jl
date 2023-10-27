# using Revise
# using JSON3
#include("cost_curves.jl")


## Initialize main parameters
CY_cap = 1984
CY_ts = 2012
VOLL = 8000
endtime = 24*10
scenario = "Distributed Energy"

# Year an ty are different for when a year after 2040 is used. In that case,
#the demand series and the capacities have to be read from the 2040 year. but some
# changes to capacities are implemented towards less carbon intensive counterparts
year = 2025
ty = 2025


# Now, with the main input parameters determined, we are going to build the actual model and solve it. 
# The command below does three important things: 
#       1. It builactivds a JuMP model, that represents the European power system based on capacities that are
#       considered to be input. The constraints are general, but the relevant input data
#       is based on the main parameters above. (Timeseries, capacities, commodity costs,..)
#       2. It solves the model to determine optimal dispatch decisions of the generationg technologies,
#        and optimal storage operations 
#       3. It extracts and returns the storage decisions of the optimized model for all nodes and all timesteps. 
# 
m2,soc,production =  optimize_and_retain_intertemporal_decisions_no_DSR(scenario,year,CY_cap,CY_ts,endtime,VOLL,ty)

#Let's have a look at the information in the soc variable
test_loc = "BE00"
soc_test_loc_PS_C = [ soc[test_loc,"PS_C",i] for i in 1:endtime]
plot(soc_test_loc_PS_C[1:240])


# We now save these storage (soc, and prod) decision variables to a file that can be read later. 
open(joinpath("soc_files","soc_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"), "w") do io
    JSON3.write(io, write_sparse_axis_to_dict(soc))
end
open(joinpath("soc_files","prod_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"), "w") do io
    JSON3.write(io, write_sparse_axis_to_dict(production))
end




#Note that untill now we have only performed the very initial step in the procedure. We have solved the 
# dispatch model with the target country included, for the sole purpose of having a reference time-series 
# for storage technologies. When demand shift or other intertemporal technologies should ever be included, these 
# should probably be fixed in a similar manner 

#Now we identify the target country, and the import levels we want to consider for the cost curve. 
country = "BE00"
import_levels = -1000:100:1000

#The files that we saved earlier can be read: 
soc_dict = JSON3.read(read(joinpath("soc_files","soc_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"),String))
production_dict = JSON3.read(read(joinpath("soc_files","prod_$(ty)_$(CY_ts)_$(scenario)_$(endtime).json"), String))

# And we will again build the relevant dispatch models. Note that in this case, the dispacth models are different in
# two ways: 
# 1. The capacity of the target country is removed, and its demand is set to 0. 
# 2. The storage variables (soc, and production) are fixed for all countries --> significantly simplifies the model.

#
if ty == year
    println("Normal")
    #m2 = build_model_for_import_curve_no_DSR_from_dict(0,country,endtime,soc_dict,production_dict,0)
    
    #There is currently a problem with the dictionary keys after reading from the file.
    m2 = build_model_for_import_curve_no_DSR_from_dict(0,country,endtime,soc_dict,production,0)

else
    println("adjusted")
    m2 = build_model_for_import_curve_no_DSR_from_dict_ty(0,country,endtime,soc_dict,production_dict,0,ty)
end

#For memory purposes, if I recall 
set_optimizer_attribute(m2, "Method", 1)

#And then solve the adjusted model: 
optimize!(m2)

#Make some checks, to see if the extra constraints were satisfied
check_production_zero!(m2,country,endtime)
check_net_import(m2,country,0 ,endtime)
check_charge_zero(m2,country,endtime)

#Finally, extract the import price by inspecting the dual variable of the nodal balance constraint in the target country
import_prices = [JuMP.dual.(m2.ext[:constraints][:demand_met][country,t]) for t in 1:endtime]

plot(import_prices)


m2.ext[:parameters][:connections][country]
Dict(neighbor => m2.ext[:parameters][:connections][neighbor][country] for neighbor in m2.ext[:sets][:connections][country])



#Below, we just repeat for many import levels, making a single simple change to the existing model,
# namely the local demand in the target country.
curve_dict = Dict()
import_dict = Dict()
export_dict = Dict()
for import_level in import_levels
    @show(import_level)
    change_import_level!(m2,endtime,import_level)

    optimize!(m2)

    check_production_zero!(m2,country,endtime)
    check_net_import(m2,country,import_level,endtime)
    check_charge_zero(m2,country,endtime)

    import_prices = [JuMP.dual.(m2.ext[:constraints][:demand_met][country,t]) for t in 1:endtime]
    curve_dict[import_level] = import_prices

    import_dict[import_level] = [sum(JuMP.value.(m2.ext[:variables][:import][country,nb,t]) for nb in m2.ext[:sets][:connections][country]) for t in 1:endtime]
    export_dict[import_level] = [sum(JuMP.value.(m2.ext[:variables][:export][country,nb,t]) for nb in m2.ext[:sets][:connections][country]) for t in 1:endtime]


end

#And finally, we write the dual variables to a csv file.
write_prices(curve_dict,scenario,sort!(collect(keys(curve_dict))),"$(ty)_CY_$(CY_ts)_$(endtime)_extended_loop")
